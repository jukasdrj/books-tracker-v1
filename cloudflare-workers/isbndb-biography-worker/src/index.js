/**
 * ISBNdb Biography Worker - Source of Truth for Editions (v3 - Final)
 *
 * This worker specializes in two high-fidelity tasks:
 * 1. Finding a book by its specific ISBN.
 * 2. Finding, filtering, de-duplicating, and CLEANING all editions for a title,
 * including page counts and normalized genres.
 */
import { WorkerEntrypoint } from "cloudflare:workers";

const RATE_LIMIT_KEY = 'isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000; // 1 second between requests

export class ISBNdbWorker extends WorkerEntrypoint {
  /**
   * RPC Method: Get all known, filtered, and de-duplicated editions.
   */
  async getEditionsForWork(title, authorName) {
    try {
      console.log(`RPC: getEditionsForWork v3 ("${title}", "${authorName}")`);
      const searchUrl = `https://api2.isbndb.com/books/${encodeURIComponent(title)}?column=title&language=en&shouldMatchAll=1&pageSize=100`;
      
      await enforceRateLimit(this.env);
      const searchResponse = await fetchWithAuth(searchUrl, this.env);

      if (!searchResponse.books || searchResponse.books.length === 0) {
        return { success: true, editions: [] };
      }

      // Filter to ensure the primary author matches
      const relevantBooks = searchResponse.books.filter(book =>
        book.authors?.some(a => a.toLowerCase().includes(authorName.toLowerCase()))
      );

      // Final processing step to clean, score, and de-duplicate
      const cleanedEditions = processAndDeduplicateEditions(relevantBooks);

      // Sort by final score to present the best editions first.
      cleanedEditions.sort((a, b) => b.qualityScore - a.qualityScore);

      return { success: true, editions: cleanedEditions };

    } catch (error) {
      console.error(`RPC Error in getEditionsForWork for "${title}":`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * RPC Method: Get a specific book by its ISBN.
   */
  async getBookByISBN(isbn) {
    try {
      console.log(`RPC: getBookByISBN("${isbn}")`);
      const url = `https://api2.isbndb.com/book/${isbn}?with_prices=0`;
      await enforceRateLimit(this.env);
      const response = await fetchWithAuth(url, this.env);
      return { success: true, book: response.book };
    } catch (error) {
      console.error(`RPC Error in getBookByISBN for "${isbn}":`, error);
      return { success: false, error: error.message };
    }
  }

  // HTTP Fetch Handler (required for deployment)
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ status: 'healthy', worker: 'isbndb-biography-worker', version: 'v3' }));
    }
    return new Response('Not Found', { status: 404 });
  }
}

// --- ADVANCED FILTERING, SCORING, & NORMALIZATION ---

/**
 * Processes a raw list of books from ISBNdb, turning it into a clean, scored,
 * and de-duplicated list of high-quality editions with normalized genres.
 */
function processAndDeduplicateEditions(books) {
    const unwantedTitleKeywords = [
        'study guide', 'summary', 'workbook', 'audiobook', 'box set', 'collection',
        'companion', 'large print', 'classroom', 'abridged', 'collectors', 'deluxe',
        ' unabridged', 'audio cd'
    ];
    const unwantedPublishers = [
        'createspace', 'independently published', 'kdp', 'lulu.com',
        'lightning source', 'ingramspark', 'bibliolife', 'apple books', 'smashwords'
    ];

    const editionMap = new Map();

    for (const book of books) {
        const title = (book.title || '').toLowerCase();
        const publisher = (book.publisher || '').toLowerCase();
        const binding = (book.binding || '').toLowerCase();
        const isbn13 = book.isbn13;

        // --- Step 1: Hard Filters ---
        if (!isbn13) continue;
        if (unwantedTitleKeywords.some(keyword => title.includes(keyword))) continue;
        if (unwantedPublishers.some(pub => publisher.includes(pub))) continue;
        if (binding.includes('audio')) continue;

        // --- Step 2: Scoring ---
        let score = 50;
        if (book.image) score += 40;
        if (binding.includes('hardcover')) score += 25;
        if (binding.includes('trade paperback')) score += 20;
        if (binding.includes('paperback')) score += 15;
        if (binding.includes('mass market paperback')) score += 5;
        if (binding.includes('library')) score -= 20;
        if (['penguin', 'random house', 'harpercollins', 'simon & schuster', 'hachette', 'macmillan', 'scholastic', 'knopf', 'doubleday', 'viking'].some(p => publisher.includes(p))) {
            score += 15;
        }
        if (book.pages) score += 10; // Bonus for having page count
        if (book.synopsis) score += 5;
        const year = parseInt(book.date_published, 10);
        if (!isNaN(year) && year > 2015) score += 5;

        // --- Step 3: Data Extraction and Normalization ---
        const currentEdition = {
            isbn13: book.isbn13,
            isbn10: book.isbn,
            title: book.title,
            publisher: book.publisher,
            publishDate: book.date_published,
            binding: book.binding,
            pages: book.pages, // Capture page count
            genres: normalizeGenres(book.subjects), // Process and clean genres
            coverImageURL: book.image,
            source: 'isbndb',
            qualityScore: score
        };

        // --- Step 4: De-duplication ---
        if (!editionMap.has(isbn13) || score > editionMap.get(isbn13).qualityScore) {
            editionMap.set(isbn13, currentEdition);
        }
    }

    return Array.from(editionMap.values());
}

/**
 * Cleans the raw "subjects" array from ISBNdb into a reportable genre list.
 * @param {Array<string>} subjects - The raw array of subjects from the API.
 * @returns {Array<string>} A clean, capitalized array of top genres.
 */
function normalizeGenres(subjects) {
    if (!subjects || subjects.length === 0) {
        return [];
    }

    const genreBlacklist = new Set([
        'fiction', 'history', 'biography & autobiography', 'juvenile fiction', 'social science'
    ]);

    const cleanedGenres = subjects
        .map(s => s.split(' / ')[0].trim()) // Take the primary category before slashes
        .filter(s => s.length > 2 && !genreBlacklist.has(s.toLowerCase())) // Filter out blacklist and short strings
        .map(s => s.charAt(0).toUpperCase() + s.slice(1)); // Capitalize

    // If "Juvenile Fiction" was the ONLY genre, allow "Young Adult" as a fallback.
    if (cleanedGenres.length === 0 && subjects.some(s => s.toLowerCase().includes('juvenile fiction'))) {
        return ['Young Adult'];
    }
    
    // Return a de-duplicated and limited list of the best genres
    return [...new Set(cleanedGenres)].slice(0, 4);
}


// --- API & UTILITY FUNCTIONS (No changes needed below) ---

async function fetchWithAuth(url, env) {
  const apiKey = await env.ISBNDB_API_KEY.get();
  if (!apiKey) throw new Error('ISBNDB_API_KEY secret not found');
  const response = await fetch(url, {
    headers: { 'Authorization': apiKey, 'Accept': 'application/json' },
  });
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`ISBNdb API error: ${response.status} - ${errorText}`);
  }
  return response.json();
}

async function enforceRateLimit(env) {
  const lastRequest = await env.KV_CACHE.get(RATE_LIMIT_KEY);
  if (lastRequest) {
    const timeDiff = Date.now() - parseInt(lastRequest);
    if (timeDiff < RATE_LIMIT_INTERVAL) {
      const waitTime = RATE_LIMIT_INTERVAL - timeDiff;
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
  await env.KV_CACHE.put(RATE_LIMIT_KEY, Date.now().toString(), { expirationTtl: 5 });
}

export default ISBNdbWorker;