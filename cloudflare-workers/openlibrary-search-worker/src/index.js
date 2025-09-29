/**
 * OpenLibrary Search Worker - Source of Truth for Works
 *
 * This worker's primary responsibility is to provide a canonical list of an
 * author's creative works. It does not concern itself with editions.
 */
import { WorkerEntrypoint } from "cloudflare:workers";

const USER_AGENT = 'BooksTracker/1.0 (nerd@ooheynerds.com) OpenLibraryWorker/1.1.0';

export class OpenLibraryWorker extends WorkerEntrypoint {
  /**
   * RPC Method: General search that prefers Works over Editions
   * @param {string} query - The search query (author, title, etc.)
   * @param {object} params - Optional parameters like maxResults
   * @returns {Promise<object>} - Normalized search results focusing on Works
   */
  async search(query, params = {}) {
    try {
      console.log(`RPC: OpenLibrary general search for "${query}"`);

      const maxResults = params.maxResults || 20;

      // Search OpenLibrary with preference for works
      const searchUrl = `https://openlibrary.org/search.json?q=${encodeURIComponent(query)}&limit=${maxResults}`;
      const response = await fetch(searchUrl, {
        headers: { 'User-Agent': USER_AGENT }
      });

      if (!response.ok) {
        throw new Error(`OpenLibrary search API failed: ${response.status}`);
      }

      const data = await response.json();
      const works = normalizeOpenLibrarySearchResults(data.docs || []);

      return {
        success: true,
        provider: 'openlibrary',
        works: works,
        totalResults: data.numFound || 0
      };

    } catch (error) {
      console.error(`RPC Error in OpenLibrary search for "${query}":`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * RPC Method: Get an author's canonical list of works.
   * @param {string} authorName - The name of the author to look up.
   * @returns {Promise<object>} - An object containing author details and a list of their works.
   */
  async getAuthorWorks(authorName) {
    try {
      console.log(`RPC: getAuthorWorks("${authorName}")`);

      const authorKey = await findAuthorKeyByName(authorName);
      if (!authorKey) {
        return { success: false, error: 'Author not found in OpenLibrary' };
      }

      const works = await getWorksByAuthorKey(authorKey);
      
      const response = {
        success: true,
        provider: 'openlibrary',
        author: {
          name: authorName, // Use the searched name for consistency
          openLibraryKey: authorKey,
        },
        works: works,
      };

      return response;

    } catch (error) {
      console.error(`RPC Error in getAuthorWorks for "${authorName}":`, error);
      return { success: false, error: error.message };
    }
  }

  // Basic fetch handler for health checks or direct testing
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({ status: 'healthy', worker: 'openlibrary-search-worker' }));
    }
    return new Response('Not Found', { status: 404 });
  }
}

// --- API & UTILITY FUNCTIONS ---

/**
 * Normalize OpenLibrary search results to prefer Works over Editions
 * and collect external cross-reference IDs
 */
function normalizeOpenLibrarySearchResults(docs) {
  const worksMap = new Map();

  docs.forEach(doc => {
    // Prefer works over editions
    const isWork = doc.type === 'work' || (doc.key && doc.key.startsWith('/works/'));

    if (!isWork) {
      // Skip editions unless we don't have the work yet
      const potentialWorkKey = doc.key?.replace('/books/', '/works/').replace(/M$/, 'W');
      if (worksMap.has(potentialWorkKey)) {
        return; // Skip edition if we already have the work
      }
    }

    const workKey = doc.key || `synthetic-${doc.title?.replace(/\s+/g, '-').toLowerCase()}`;

    if (!worksMap.has(workKey)) {
      const work = {
        title: doc.title || 'Unknown Title',
        subtitle: doc.subtitle,
        authors: (doc.author_name || []).map(name => ({ name })),
        firstPublicationYear: doc.first_publish_year,
        subjects: doc.subject || [],

        // External cross-reference IDs for future workers
        externalIds: {
          openLibraryWorkId: isWork ? extractWorkId(doc.key) : null,
          openLibraryEditionId: !isWork ? extractEditionId(doc.key) : null,
          goodreadsWorkIds: doc.id_goodreads || [],
          amazonASINs: doc.id_amazon || [],
          librarythingIds: doc.id_librarything || [],
          googleBooksVolumeIds: doc.id_google || [],
          isbndbIds: [], // ISBNdb IDs to be added by ISBNdb worker
        },

        // Edition information
        editions: [{
          isbn10: doc.isbn?.[0],
          isbn13: doc.isbn?.find(isbn => isbn.length === 13),
          publisher: doc.publisher?.[0],
          publicationDate: doc.publish_date?.[0],
          pageCount: doc.number_of_pages_median,
          language: doc.language?.[0],
          coverImageURL: doc.cover_i ? `https://covers.openlibrary.org/b/id/${doc.cover_i}-L.jpg` : null,
          externalIds: {
            openLibraryEditionId: !isWork ? extractEditionId(doc.key) : null,
            googleBooksVolumeIds: doc.id_google || [],
            amazonASINs: doc.id_amazon || []
          }
        }],

        source: 'openlibrary'
      };

      worksMap.set(workKey, work);
    }
  });

  return Array.from(worksMap.values());
}

/**
 * Extract OpenLibrary Work ID from key
 */
function extractWorkId(key) {
  if (!key) return null;
  const match = key.match(/\/works\/([^\/]+)/);
  return match ? match[1] : null;
}

/**
 * Extract OpenLibrary Edition ID from key
 */
function extractEditionId(key) {
  if (!key) return null;
  const match = key.match(/\/books\/([^\/]+)/);
  return match ? match[1] : null;
}

async function findAuthorKeyByName(authorName) {
  const searchUrl = `https://openlibrary.org/search/authors.json?q=${encodeURIComponent(authorName)}&limit=1`;
  const response = await fetch(searchUrl, { headers: { 'User-Agent': USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary author search API failed');
  const data = await response.json();
  return data.docs && data.docs.length > 0 ? data.docs[0].key : null;
}

async function getWorksByAuthorKey(authorKey) {
  const worksUrl = `https://openlibrary.org/authors/${authorKey}/works.json?limit=1000`;
  const response = await fetch(worksUrl, { headers: { 'User-Agent': USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary works fetch API failed');
  const data = await response.json();

  console.log(`OpenLibrary returned ${data.entries?.length || 0} works for ${authorKey}`);

  // Normalize the response to a consistent "Work" format
  return (data.entries || []).map(work => ({
    title: work.title,
    openLibraryWorkKey: work.key,
    firstPublicationYear: work.first_publish_year,
    editions: [], // This will be populated by the ISBNdb worker
  }));
}

export default OpenLibraryWorker;