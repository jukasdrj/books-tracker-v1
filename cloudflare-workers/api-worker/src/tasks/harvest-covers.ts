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
