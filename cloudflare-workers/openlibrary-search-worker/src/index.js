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