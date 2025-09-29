/**
 * Google Books Search Worker - Specialist
 *
 * This worker's primary responsibility is to execute searches against the
 * Google Books API and normalize the response into a consistent format that
 * matches the output of the other specialist workers.
 */
import { WorkerEntrypoint } from "cloudflare:workers";

const USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) GoogleBooksWorker/1.0.0';

export class GoogleBooksWorker extends WorkerEntrypoint {
  /**
   * RPC Method: Executes a general search against the Google Books API.
   * @param {string} query - The search query.
   * @param {object} params - Optional parameters like maxResults, searchField.
   * @returns {Promise<object>} - A normalized list of works and their editions.
   */
  async search(query, params = {}) {
    const startTime = Date.now();
    try {
      console.log(`RPC: GoogleBooks search for "${query}"`);

      const apiKey = await this.env.GOOGLE_BOOKS_API_KEY.get();
      if (!apiKey) {
        return { success: false, error: "Google Books API key not configured." };
      }

      const maxResults = params.maxResults || 20;
      const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(query)}&maxResults=${maxResults}&key=${apiKey}`;

      const response = await fetch(searchUrl, {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Google Books API error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const normalizedData = normalizeGoogleBooksResponse(data);

      const processingTime = Date.now() - startTime;

      // Analytics tracking
      if (this.env.GOOGLE_BOOKS_ANALYTICS) {
        this.env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [query, 'search'],
          doubles: [processingTime, normalizedData.works.length],
          indexes: ['google-books-search']
        });
      }

      return {
        success: true,
        provider: 'google-books',
        processingTime,
        ...normalizedData,
      };
    } catch (error) {
      const processingTime = Date.now() - startTime;
      console.error(`RPC Error in GoogleBooksWorker.search:`, error);

      // Track errors in analytics
      if (this.env.GOOGLE_BOOKS_ANALYTICS) {
        this.env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [query, 'search_error'],
          doubles: [processingTime, 0],
          indexes: ['google-books-error']
        });
      }

      return { success: false, error: error.message, processingTime };
    }
  }

  /**
   * RPC Method: Search by ISBN specifically.
   * @param {string} isbn - The ISBN to search for.
   * @returns {Promise<object>} - A normalized response.
   */
  async searchByISBN(isbn) {
    const startTime = Date.now();
    try {
      console.log(`RPC: GoogleBooks ISBN search for "${isbn}"`);

      const apiKey = await this.env.GOOGLE_BOOKS_API_KEY.get();
      if (!apiKey) {
        return { success: false, error: "Google Books API key not configured." };
      }

      const searchUrl = `https://www.googleapis.com/books/v1/volumes?q=isbn:${encodeURIComponent(isbn)}&key=${apiKey}`;

      const response = await fetch(searchUrl, {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Google Books API error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const normalizedData = normalizeGoogleBooksResponse(data);

      const processingTime = Date.now() - startTime;

      // Analytics tracking
      if (this.env.GOOGLE_BOOKS_ANALYTICS) {
        this.env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [isbn, 'isbn_search'],
          doubles: [processingTime, normalizedData.works.length],
          indexes: ['google-books-isbn']
        });
      }

      return {
        success: true,
        provider: 'google-books',
        processingTime,
        ...normalizedData,
      };
    } catch (error) {
      const processingTime = Date.now() - startTime;
      console.error(`RPC Error in GoogleBooksWorker.searchByISBN:`, error);

      // Track errors in analytics
      if (this.env.GOOGLE_BOOKS_ANALYTICS) {
        this.env.GOOGLE_BOOKS_ANALYTICS.writeDataPoint({
          blobs: [isbn, 'isbn_search_error'],
          doubles: [processingTime, 0],
          indexes: ['google-books-error']
        });
      }

      return { success: false, error: error.message, processingTime };
    }
  }

  // Basic fetch handler for health checks or direct testing
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        status: 'healthy',
        worker: 'google-books-worker',
        version: '1.0.0',
        timestamp: new Date().toISOString()
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    return new Response('Not Found', { status: 404 });
  }
}

/**
 * Normalizes the raw Google Books API response into our standard Work/Edition format.
 * @param {object} apiResponse - The raw JSON from the Google Books API.
 * @returns {{works: Array<object>, authors: Array<object>}} - Normalized data.
 */
function normalizeGoogleBooksResponse(apiResponse) {
  if (!apiResponse.items || apiResponse.items.length === 0) {
    return { works: [], authors: [] };
  }

  const worksMap = new Map();
  const authorsMap = new Map();

  apiResponse.items.forEach(item => {
    const volumeInfo = item.volumeInfo;
    if (!volumeInfo || !volumeInfo.title) {
      return;
    }

    // Handle missing authors gracefully
    const authors = volumeInfo.authors || ['Unknown Author'];

    // Create a canonical work key from title and first author
    const workKey = `${volumeInfo.title.toLowerCase()}-${authors[0].toLowerCase()}`;

    if (!worksMap.has(workKey)) {
      worksMap.set(workKey, {
        title: volumeInfo.title,
        subtitle: volumeInfo.subtitle,
        authors: authors.map(name => ({ name })),
        editions: [],
        firstPublishYear: extractYear(volumeInfo.publishedDate),
      });
    }

    const work = worksMap.get(workKey);

    // Extract ISBNs
    const isbn13 = volumeInfo.industryIdentifiers?.find(id => id.type === 'ISBN_13')?.identifier;
    const isbn10 = volumeInfo.industryIdentifiers?.find(id => id.type === 'ISBN_10')?.identifier;

    // Create the edition object for this specific volume
    work.editions.push({
      googleBooksVolumeId: item.id,
      isbn13: isbn13,
      isbn10: isbn10,
      title: volumeInfo.title,
      subtitle: volumeInfo.subtitle,
      publisher: volumeInfo.publisher,
      publishDate: volumeInfo.publishedDate,
      publishYear: extractYear(volumeInfo.publishedDate),
      pages: volumeInfo.pageCount,
      language: volumeInfo.language,
      genres: volumeInfo.categories || [],
      description: volumeInfo.description,
      coverImageURL: volumeInfo.imageLinks?.thumbnail?.replace('http:', 'https:'),
      previewLink: volumeInfo.previewLink,
      infoLink: volumeInfo.infoLink,
      source: 'google-books',
    });

    // Collect unique authors
    authors.forEach(authorName => {
      if (!authorsMap.has(authorName)) {
        authorsMap.set(authorName, {
          name: authorName,
          source: 'google-books'
        });
      }
    });
  });

  return {
    works: Array.from(worksMap.values()),
    authors: Array.from(authorsMap.values())
  };
}

/**
 * Extracts a 4-digit year from a date string.
 * @param {string} dateString - The date string (e.g., "2023", "2023-05", "2023-05-15").
 * @returns {number|null} - The extracted year or null if not found.
 */
function extractYear(dateString) {
  if (!dateString) return null;
  const yearMatch = dateString.match(/(\d{4})/);
  return yearMatch ? parseInt(yearMatch[1], 10) : null;
}

export default GoogleBooksWorker;