/**
 * OpenLibrary Search Worker - RPC Enhanced
 *
 * Exposes a direct getAuthorBibliography RPC method for the main proxy worker to call.
 * This is faster and more reliable than making HTTP requests between workers.
 */

import { WorkerEntrypoint } from "cloudflare:workers";

const USER_AGENT = 'BooksTracker/1.0 (contact@bookstrack.app) OpenLibraryWorker/1.0.0';

export class OpenLibraryWorker extends WorkerEntrypoint {
  /**
   * RPC Method: Get an author's bibliography from OpenLibrary.
   * @param {string} authorName - The name of the author to look up.
   * @returns {Promise<object>} - The normalized author and works data.
   */
  async getAuthorBibliography(authorName) {
    try {
      console.log(`RPC: getAuthorBibliography("${authorName}")`);
      const authorInfo = await findAuthorByName(authorName, this.env);
      if (!authorInfo) {
        return { success: false, error: 'Author not found' };
      }

      const works = await getAuthorWorksFromKey(authorInfo.key, this.env);
      const normalizedData = normalizeWorksFromOpenLibrary(works, authorInfo);
      
      return {
        success: true,
        provider: 'openlibrary',
        ...normalizedData,
      };
    } catch (error) {
      console.error(`RPC Error in getAuthorBibliography for "${authorName}":`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * HTTP Fetch Handler (for direct calls or backward compatibility)
   */
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    if (path.startsWith('/author/')) {
      const authorName = decodeURIComponent(path.replace('/author/', ''));
      const result = await this.getAuthorBibliography(authorName);
      return new Response(JSON.stringify(result), {
        status: result.success ? 200 : 404,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    
    return new Response('Not Found', { status: 404 });
  }
}

// --- API & UTILITY FUNCTIONS ---

async function findAuthorByName(authorName, env) {
  const searchUrl = `https://openlibrary.org/search/authors.json?q=${encodeURIComponent(authorName)}&limit=1`;
  const response = await fetch(searchUrl, { headers: { 'User-Agent': USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary author search failed');
  const data = await response.json();
  return data.docs && data.docs.length > 0 ? data.docs[0] : null;
}

async function getAuthorWorksFromKey(authorKey, env) {
  const worksUrl = `https://openlibrary.org/authors/${authorKey}/works.json?limit=200`;
  const response = await fetch(worksUrl, { headers: { 'User-Agent': USER_AGENT } });
  if (!response.ok) throw new Error('OpenLibrary works fetch failed');
  const data = await response.json();
  return data.entries || [];
}

function normalizeWorksFromOpenLibrary(works, authorInfo) {
  const normalizedWorks = works
    .filter(work => !work.title.toLowerCase().includes("(editions)")) // Filter out edition aggregate works
    .map(work => ({
        title: work.title,
        openLibraryWorkKey: work.key,
        firstPublicationYear: work.first_publish_year,
        editions: [], // To be populated by ISBNdb enhancement
    }));
  
  const author = {
    name: authorInfo.name,
    openLibraryKey: authorInfo.key
  };

  return { works: normalizedWorks, authors: [author] };
}

// Default export for ES module format
export default OpenLibraryWorker;