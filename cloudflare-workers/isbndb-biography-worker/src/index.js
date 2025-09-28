/**
 * ISBNdb Biography Worker - RPC Enhanced
 *
 * Exposes direct RPC methods for other workers to call, in addition to a standard
 * HTTP fetch handler for backward compatibility. This is the recommended pattern.
 *
 * Primary RPC Methods:
 * - getAuthorBibliography(authorName)
 * - enhanceWorksWithEditions(works, authorName)
 */

import { WorkerEntrypoint } from "cloudflare:workers";

// Rate limiting constants
const RATE_LIMIT_KEY = 'isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000; // 1 second between requests

// Main RPC class that other workers will call
export class ISBNdbWorker extends WorkerEntrypoint {
  /**
   * RPC Method: Get author bibliography with Work/Edition normalization.
   * This is the primary method for other workers to use.
   * @param {string} authorName - The name of the author to look up.
   * @returns {Promise<object>} - The normalized author and works data.
   */
  async getAuthorBibliography(authorName) {
    try {
      console.log(`RPC: getAuthorBibliography("${authorName}")`);
      // Reuses the existing handler logic but returns raw data instead of a Response object.
      return await handleAuthorLogic(authorName, this.env);
    } catch (error) {
      console.error(`RPC Error in getAuthorBibliography for "${authorName}":`, error);
      return { success: false, error: error.message, author: authorName };
    }
  }

  /**
   * RPC Method: Enhance a list of works with edition data from ISBNdb.
   * @param {Array<object>} works - An array of work objects from OpenLibrary.
   * @param {string} authorName - The name of the primary author.
   * @returns {Promise<object>} - The list of works, now enhanced with ISBNdb editions.
   */
  async enhanceWorksWithEditions(works, authorName) {
    try {
        console.log(`RPC: enhanceWorksWithEditions for "${authorName}" (${works.length} works)`);
        return await enhanceWorksLogic(works, authorName, this.env);
    } catch (error)
    {
        console.error(`RPC Error in enhanceWorksWithEditions for "${authorName}":`, error);
        return { success: false, error: error.message, works };
    }
  }

  /**
   * HTTP Fetch Handler (for direct calls or backward compatibility)
   * This handler is still available if you hit the worker's public URL directly.
   */
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    console.log(`HTTP: ${request.method} ${path}`);

    if (path.startsWith('/author/')) {
      const authorName = decodeURIComponent(path.replace('/author/', ''));
      const result = await this.getAuthorBibliography(authorName);
      return new Response(JSON.stringify(result), {
        status: result.success === false ? 500 : 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (path === '/enhance/works' && request.method === 'POST') {
        const { works, authorName } = await request.json();
        const result = await this.enhanceWorksWithEditions(works, authorName);
        return new Response(JSON.stringify(result), {
            status: result.success === false ? 500 : 200,
            headers: { 'Content-Type': 'application/json' },
        });
    }

    return new Response(JSON.stringify({ error: 'Endpoint not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Core logic for handling author requests, shared by RPC and fetch.
 */
async function handleAuthorLogic(authorName, env) {
    if (!authorName || authorName.trim().length === 0) {
        return { success: false, error: 'Author name is required' };
    }

    const cacheKey = `author:${authorName.toLowerCase()}`;
    const cached = await env.KV_CACHE.get(cacheKey, 'json');

    if (cached) {
        console.log(`Cache hit for ${authorName}`);
        return { ...cached, cached: true };
    }

    await enforceRateLimit(env);

    const bibliography = await fetchAuthorBibliographyFromAPI(authorName, env);
    if (!bibliography.books || bibliography.books.length === 0) {
        return { success: false, error: 'No books found for author', author: authorName };
    }

    const processedData = normalizeWorksFromISBNdb(bibliography.books, authorName);

    const cacheData = {
      success: true,
      author: authorName,
      ...processedData,
      timestamp: new Date().toISOString(),
      source: 'isbndb',
      format: 'enhanced_work_edition_v1'
    };

    await env.KV_CACHE.put(cacheKey, JSON.stringify(cacheData), { expirationTtl: 86400 }); // 24 hours

    return { ...cacheData, cached: false };
}

/**
 * Core logic for enhancing works, shared by RPC and fetch.
 */
async function enhanceWorksLogic(works, authorName, env) {
    const enhancedWorks = [];
    let enhancementCount = 0;

    for (const work of works) {
        const enhanced = { ...work, isbndbEnhanced: false };
        try {
            const searchQuery = `${work.title} ${authorName}`;
            const searchUrl = `https://api2.isbndb.com/search/books?text=${encodeURIComponent(searchQuery)}&author=${encodeURIComponent(authorName)}&pageSize=5`;
            
            await enforceRateLimit(env); // Respect rate limit for each search
            const searchResponse = await fetchWithAuth(searchUrl, env);

            if (searchResponse.books && searchResponse.books.length > 0) {
                 const matchingEditions = searchResponse.books.map(book => ({
                    isbn: book.isbn13 || book.isbn,
                    title: book.title,
                    publisher: book.publisher,
                    publishDate: book.date_published,
                    source: 'isbndb'
                 }));

                enhanced.editions = [...(enhanced.editions || []), ...matchingEditions];
                enhanced.isbndbEnhanced = true;
                enhancementCount++;
            }
        } catch (error) {
            console.warn(`Failed to enhance "${work.title}":`, error.message);
        }
        enhancedWorks.push(enhanced);
    }
    return {
        success: true,
        works: enhancedWorks,
        enhancementStats: {
            totalWorks: works.length,
            enhanced: enhancementCount,
            enhancementRate: works.length > 0 ? enhancementCount / works.length : 0
        }
    };
}


// --- API & UTILITY FUNCTIONS ---

async function fetchAuthorBibliographyFromAPI(authorName, env) {
  const url = `https://api2.isbndb.com/author/${encodeURIComponent(authorName)}?pageSize=500&language=en`;
  return await fetchWithAuth(url, env);
}

async function fetchWithAuth(url, env) {
  const apiKey = await env.ISBNDB_API_KEY.get();
  if (!apiKey) throw new Error('ISBNDB_API_KEY secret not found');

  const response = await fetch(url, {
    headers: { 'Authorization': apiKey },
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

function normalizeWorksFromISBNdb(books, searchAuthor) {
  // This function remains the same as your provided implementation
  // It correctly groups editions under a single work.
  const worksMap = new Map();
  const authorsMap = new Map();
  
  books.forEach(book => {
    if (!book.title || !book.authors) return;
    const primaryAuthor = Array.isArray(book.authors) ? book.authors[0] : book.authors;
    const workKey = `${book.title.toLowerCase()}-${primaryAuthor.toLowerCase()}`;
    
    if (!worksMap.has(workKey)) {
        worksMap.set(workKey, {
            title: book.title,
            authors: [],
            editions: []
        });
    }

    const work = worksMap.get(workKey);
    work.editions.push({
        isbn: book.isbn13 || book.isbn,
        publisher: book.publisher,
        publicationDate: book.date_published,
        coverImageURL: book.image,
    });

    (Array.isArray(book.authors) ? book.authors : [book.authors]).forEach(name => {
        if (!authorsMap.has(name)) {
            authorsMap.set(name, { name, works: new Set() });
        }
        authorsMap.get(name).works.add(workKey);
    });
  });

  const authors = Array.from(authorsMap.values()).map(a => ({ name: a.name, workCount: a.works.size }));

  return { works: Array.from(worksMap.values()), authors };
}

// Default export for ES module format
export default ISBNdbWorker;