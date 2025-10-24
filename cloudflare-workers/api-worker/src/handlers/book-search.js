/**
 * Book search handlers with KV caching
 * Migrated from books-api-proxy
 *
 * Caching rules:
 * - Title search: 6 hour TTL (21600 seconds)
 * - ISBN search: 7 day TTL (604800 seconds) - ISBN data is stable
 */

import * as externalApis from '../services/external-apis.js';
import { getCached, setCached, generateCacheKey } from '../utils/cache.js';

/**
 * Search books by title with multi-provider orchestration
 * @param {string} title - Book title to search
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results to return (default: 20)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Search results in Google Books format
 */
export async function searchByTitle(title, options, env, ctx) {
  const { maxResults = 20 } = options;
  const cacheKey = generateCacheKey('search:title', { title: title.toLowerCase(), maxResults });

  // Try cache first
  const cached = await getCached(cacheKey, env);
  if (cached) {
    return { ...cached, cached: true };
  }

  const startTime = Date.now();

  try {
    // Search both Google Books and OpenLibrary in parallel
    const searchPromises = [
      externalApis.searchGoogleBooks(title, { maxResults }, env),
      externalApis.searchOpenLibrary(title, { maxResults }, env)
    ];

    const results = await Promise.allSettled(searchPromises);

    let finalItems = [];
    let successfulProviders = [];

    // Process Google Books results
    if (results[0].status === 'fulfilled' && results[0].value.success) {
      const googleData = results[0].value;
      if (googleData.items && googleData.items.length > 0) {
        finalItems = [...finalItems, ...googleData.items];
        successfulProviders.push('google');
      }
    }

    // Process OpenLibrary results
    if (results[1].status === 'fulfilled' && results[1].value.success) {
      const olData = results[1].value;
      if (olData.works && olData.works.length > 0) {
        // Transform OpenLibrary works to Google Books format
        const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
        finalItems = [...finalItems, ...transformedItems];
        successfulProviders.push('openlibrary');
      }
    }

    // Simple deduplication by title
    const dedupedItems = deduplicateByTitle(finalItems);

    const responseData = {
      kind: "books#volumes",
      totalItems: dedupedItems.length,
      items: dedupedItems.slice(0, maxResults),
      provider: `orchestrated:${successfulProviders.join('+')}`,
      cached: false,
      responseTime: Date.now() - startTime
    };

    // Cache for 6 hours
    const ttl = 6 * 60 * 60; // 21600 seconds
    ctx.waitUntil(setCached(cacheKey, responseData, ttl, env));

    return responseData;
  } catch (error) {
    console.error(`Title search failed for "${title}":`, error);
    return {
      error: 'Title search failed',
      details: error.message,
      items: []
    };
  }
}

/**
 * Search books by ISBN with multi-provider orchestration
 * @param {string} isbn - ISBN-10 or ISBN-13
 * @param {Object} options - Search options
 * @param {number} options.maxResults - Maximum results to return (default: 1)
 * @param {Object} env - Worker environment bindings
 * @param {Object} ctx - Execution context
 * @returns {Promise<Object>} Book details in Google Books format
 */
export async function searchByISBN(isbn, options, env, ctx) {
  const { maxResults = 1 } = options;
  const cacheKey = generateCacheKey('search:isbn', { isbn });

  // Try cache first
  const cached = await getCached(cacheKey, env);
  if (cached) {
    return { ...cached, cached: true };
  }

  const startTime = Date.now();

  try {
    // Search both Google Books and OpenLibrary in parallel
    const searchPromises = [
      externalApis.searchGoogleBooksByISBN(isbn, env),
      externalApis.searchOpenLibrary(isbn, { maxResults, isbn }, env)
    ];

    const results = await Promise.allSettled(searchPromises);

    let finalItems = [];
    let successfulProviders = [];

    // Process Google Books results
    if (results[0].status === 'fulfilled' && results[0].value.success) {
      const googleData = results[0].value;
      if (googleData.items && googleData.items.length > 0) {
        finalItems = [...finalItems, ...googleData.items];
        successfulProviders.push('google');
      }
    }

    // Process OpenLibrary results
    if (results[1].status === 'fulfilled' && results[1].value.success) {
      const olData = results[1].value;
      if (olData.works && olData.works.length > 0) {
        const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
        finalItems = [...finalItems, ...transformedItems];
        successfulProviders.push('openlibrary');
      }
    }

    // Simple deduplication by ISBN
    const dedupedItems = deduplicateByISBN(finalItems);

    const responseData = {
      kind: "books#volumes",
      totalItems: dedupedItems.length,
      items: dedupedItems.slice(0, maxResults),
      provider: `orchestrated:${successfulProviders.join('+')}`,
      cached: false,
      responseTime: Date.now() - startTime
    };

    // Cache for 7 days (ISBN data is stable)
    const ttl = 7 * 24 * 60 * 60; // 604800 seconds
    ctx.waitUntil(setCached(cacheKey, responseData, ttl, env));

    return responseData;
  } catch (error) {
    console.error(`ISBN search failed for "${isbn}":`, error);
    return {
      error: 'ISBN search failed',
      details: error.message,
      items: []
    };
  }
}

/**
 * Transform OpenLibrary work to Google Books format
 * Simplified version for api-worker
 */
function transformWorkToGoogleFormat(work) {
  const primaryEdition = work.editions && work.editions.length > 0 ? work.editions[0] : null;

  // Handle different author formats
  let authors = [];
  if (work.authors) {
    if (Array.isArray(work.authors)) {
      authors = work.authors.map(a => {
        if (typeof a === 'string') return a;
        if (a && a.name) return a.name;
        return String(a);
      });
    } else if (typeof work.authors === 'string') {
      authors = [work.authors];
    }
  }

  // If no authors in work, try edition
  if (authors.length === 0 && primaryEdition?.authors) {
    authors = Array.isArray(primaryEdition.authors)
      ? primaryEdition.authors.map(a => typeof a === 'string' ? a : a.name || String(a))
      : [String(primaryEdition.authors)];
  }

  // Prepare industry identifiers
  const industryIdentifiers = [];
  if (primaryEdition?.isbn13) {
    industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn13 });
  }
  if (primaryEdition?.isbn10) {
    industryIdentifiers.push({ type: "ISBN_10", identifier: primaryEdition.isbn10 });
  }

  const volumeInfo = {
    title: work.title,
    subtitle: work.subtitle || "",
    authors: authors,
    publisher: primaryEdition?.publisher || "",
    publishedDate: work.firstPublicationYear ? work.firstPublicationYear.toString() : (primaryEdition?.publicationDate || ""),
    description: work.description || primaryEdition?.description || "",
    industryIdentifiers: industryIdentifiers,
    pageCount: primaryEdition?.pageCount || 0,
    categories: work.subjects || [],
    imageLinks: primaryEdition?.coverImageURL ? {
      thumbnail: primaryEdition.coverImageURL,
      smallThumbnail: primaryEdition.coverImageURL
    } : undefined
  };

  const volumeId = work.id ||
    work.openLibraryWorkKey ||
    `synthetic-${work.title.replace(/\s+/g, '-').toLowerCase()}`;

  return {
    kind: "books#volume",
    id: volumeId,
    volumeInfo: volumeInfo
  };
}

/**
 * Deduplicate items by title (case-insensitive)
 */
function deduplicateByTitle(items) {
  const seen = new Set();
  return items.filter(item => {
    const title = item.volumeInfo?.title?.toLowerCase() || '';
    if (seen.has(title)) {
      return false;
    }
    seen.add(title);
    return true;
  });
}

/**
 * Deduplicate items by ISBN
 */
function deduplicateByISBN(items) {
  const seen = new Set();
  return items.filter(item => {
    const identifiers = item.volumeInfo?.industryIdentifiers || [];
    const isbns = identifiers.map(id => id.identifier).join(',');
    if (!isbns) return true; // Keep items without ISBNs
    if (seen.has(isbns)) {
      return false;
    }
    seen.add(isbns);
    return true;
  });
}
