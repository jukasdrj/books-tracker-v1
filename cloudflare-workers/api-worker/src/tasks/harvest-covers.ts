import type {
  BookEntry,
  CoverData,
  CoverMetadata,
  HarvestResult,
  HarvestReport,
  Env
} from './types/harvest-types';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Load and parse all CSV files from docs/testImages/csv-expansion/
 */
async function loadISBNsFromCSVs(): Promise<BookEntry[]> {
  const csvDir = path.join(process.cwd(), '../../docs/testImages/csv-expansion');

  console.log(`📂 Loading CSVs from: ${csvDir}`);

  const files = fs.readdirSync(csvDir).filter(f => f.endsWith('.csv'));
  console.log(`Found ${files.length} CSV files`);

  const allEntries: BookEntry[] = [];

  for (const file of files) {
    const filePath = path.join(csvDir, file);
    const entries = await parseCSV(filePath);
    allEntries.push(...entries);
    console.log(`  ✓ ${file}: ${entries.length} books`);
  }

  return allEntries;
}

/**
 * Parse a single CSV file
 * Expected format: Title,Author,ISBN-13
 */
async function parseCSV(filePath: string): Promise<BookEntry[]> {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n').filter(line => line.trim());

  // Skip header row
  const dataLines = lines.slice(1);

  const entries: BookEntry[] = [];

  for (const line of dataLines) {
    // Simple CSV parsing (handles quoted fields)
    const match = line.match(/^"([^"]+)","([^"]+)",(\d{13})$/);
    if (!match) continue;

    const [, title, author, isbn] = match;
    entries.push({ title, author, isbn });
  }

  return entries;
}

/**
 * Deduplicate books by ISBN-13
 */
function deduplicateISBNs(entries: BookEntry[]): BookEntry[] {
  const seen = new Set<string>();
  const unique: BookEntry[] = [];

  for (const entry of entries) {
    if (!seen.has(entry.isbn)) {
      seen.add(entry.isbn);
      unique.push(entry);
    }
  }

  console.log(`📊 Deduplicated: ${entries.length} → ${unique.length} unique ISBNs`);
  return unique;
}

/**
 * Fetch cover data from ISBNdb API
 */
async function fetchFromISBNdb(isbn: string, env: Env): Promise<CoverData | null> {
  try {
    // Enforce rate limit (1000ms between requests)
    await enforceRateLimit(env);

    const apiKey = typeof env.ISBNDB_API_KEY === 'object'
      ? await env.ISBNDB_API_KEY.get()
      : env.ISBNDB_API_KEY;

    if (!apiKey) {
      throw new Error('ISBNDB_API_KEY not found');
    }

    const url = `https://api2.isbndb.com/book/${isbn}`;
    const response = await fetch(url, {
      headers: {
        'Authorization': apiKey,
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      if (response.status === 404) {
        return null; // Book not found, will try fallback
      }
      throw new Error(`ISBNdb API error: ${response.status}`);
    }

    const data = await response.json();
    const coverUrl = data.book?.image;

    if (!coverUrl) {
      return null; // No cover available
    }

    return {
      url: coverUrl,
      source: 'isbndb',
      isbn,
    };
  } catch (error) {
    console.error(`ISBNdb error for ${isbn}: ${error.message}`);
    return null;
  }
}

/**
 * Rate limiting: 1 second between ISBNdb requests
 */
const RATE_LIMIT_KEY = 'harvest_isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000; // 1 second

async function enforceRateLimit(env: Env): Promise<void> {
  const lastRequest = await env.KV_CACHE.get(RATE_LIMIT_KEY);

  if (lastRequest) {
    const timeDiff = Date.now() - parseInt(lastRequest);
    if (timeDiff < RATE_LIMIT_INTERVAL) {
      const waitTime = RATE_LIMIT_INTERVAL - timeDiff;
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }

  await env.KV_CACHE.put(RATE_LIMIT_KEY, Date.now().toString(), {
    expirationTtl: 60
  });
}

/**
 * Main entry point for ISBNdb cover harvest task
 *
 * Usage: npx wrangler dev --remote --task harvest-covers
 */
export async function harvestCovers(env: Env): Promise<HarvestReport> {
  console.log('🚀 ISBNdb Cover Harvest Starting...');
  console.log('━'.repeat(60));

  const startTime = Date.now();

  // Load and deduplicate books from CSVs
  const allEntries = await loadISBNsFromCSVs();
  const books = deduplicateISBNs(allEntries);

  console.log(`\n📚 Loaded ${books.length} unique books to harvest\n`);

  // TODO: Harvest each book
  const results: HarvestResult[] = [];

  const report: HarvestReport = {
    totalBooks: books.length,
    successCount: results.filter(r => r.success).length,
    isbndbCount: results.filter(r => r.success && r.source === 'isbndb').length,
    googleBooksCount: results.filter(r => r.success && r.source === 'google-books').length,
    failureCount: results.filter(r => !r.success).length,
    executionTimeMs: Date.now() - startTime,
    failures: results
      .filter(r => !r.success)
      .map(r => ({
        isbn: r.isbn,
        title: r.title,
        author: r.author,
        isbndbError: r.error,
      })),
  };

  console.log('\n✅ Harvest Complete!');
  console.log('━'.repeat(60));
  console.log(`✓ Total Harvested: ${report.successCount} / ${report.totalBooks}`);
  console.log(`✓ ISBNdb Covers: ${report.isbndbCount}`);
  console.log(`↻ Google Fallback: ${report.googleBooksCount}`);
  console.log(`✗ Failed: ${report.failureCount}`);
  console.log(`⏱ Execution Time: ${(report.executionTimeMs / 1000).toFixed(1)}s`);

  return report;
}
