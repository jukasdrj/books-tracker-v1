import { WorkerEntrypoint } from 'cloudflare:workers';
import { handleGeneralSearch, handleAuthorSearch, handleTitleSearch, handleSubjectSearch, handleAdvancedSearch, handleISBNSearch } from './search-handlers.js';

/**
 * Books API Proxy - RPC-enabled worker
 * Exposes both HTTP endpoints (for external clients) and RPC methods (for other workers)
 */
export class BooksAPIProxyWorker extends WorkerEntrypoint {
  /**
   * RPC Method: Search for books by general query
   * @param {string} query - Search query
   * @param {Object} options - Search options {maxResults, page}
   * @returns {Promise<Object>} Search results
   */
  async searchBooks(query, options = {}) {
    const { maxResults = 20, page = 0 } = options;
    return await handleGeneralSearch(
      { url: `?q=${encodeURIComponent(query)}&maxResults=${maxResults}&page=${page}` },
      this.env,
      this.ctx,
      {}
    );
  }

  /**
   * RPC Method: Search for books by author
   * @param {string} authorName - Author name
   * @param {Object} options - Search options
   * @returns {Promise<Object>} Author bibliography
   */
  async searchByAuthor(authorName, options = {}) {
    const { maxResults = 20, page = 0 } = options;
    return await handleAuthorSearch(authorName, { maxResults, page }, this.env, this.ctx);
  }

  /**
   * RPC Method: Search for books by ISBN
   * @param {string} isbn - ISBN-10 or ISBN-13
   * @param {Object} options - Search options
   * @returns {Promise<Object>} Book details
   */
  async searchByISBN(isbn, options = {}) {
    const { maxResults = 1, page = 0 } = options;
    return await handleISBNSearch(isbn, { maxResults, page }, this.env, this.ctx);
  }

  /**
   * RPC Method: Advanced search with multiple criteria
   * @param {Object} criteria - {authorName, bookTitle, isbn}
   * @param {Object} options - Search options
   * @returns {Promise<Object>} Search results
   */
  async advancedSearch(criteria, options = {}) {
    const { maxResults = 20, page = 0 } = options;
    return await handleAdvancedSearch(criteria, { maxResults, page }, this.env, this.ctx);
  }

  /**
   * HTTP fetch handler (for external requests)
   */
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    };

    try {
      // Bookshelf image scanning endpoint (from ship branch)
      if (path.startsWith('/api/scan-bookshelf')) {
        if (request.method !== 'POST') {
          return new Response(JSON.stringify({ error: 'Method not allowed. Use POST.' }), {
            status: 405, headers
          });
        }
        const result = await handleBookshelfScan(request, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      // Query parameters for search endpoints
      const query = url.searchParams.get('q');
      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const page = parseInt(url.searchParams.get('page') || '0');

      // Multi-context search endpoints
      if (path.startsWith('/search/author')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleAuthorSearch(query, { maxResults, page }, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/title')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleTitleSearch(query, { maxResults, page }, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/subject')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleSubjectSearch(query, { maxResults, page }, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/isbn')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleISBNSearch(query, { maxResults, page }, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/advanced')) {
        const authorName = url.searchParams.get('author');
        const bookTitle = url.searchParams.get('title');
        const isbn = url.searchParams.get('isbn');
        if (!authorName && !bookTitle && !isbn) return new Response(JSON.stringify({ error: "At least one search parameter required (author, title, or isbn)" }), { status: 400, headers });
        const result = await handleAdvancedSearch({ authorName, bookTitle, isbn }, { maxResults, page }, env, ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/auto') || path.startsWith('/search')) {
        return await handleGeneralSearch(request, env, ctx, headers);
      }

      if (path === '/health') {
        return new Response(JSON.stringify({ status: 'healthy', worker: 'books-api-proxy' }), { headers });
      }

      return new Response(JSON.stringify({ error: 'Endpoint not found' }), { status: 404, headers });
    } catch (error) {
      return new Response(JSON.stringify({ error: 'Internal Server Error', details: error.message }), { status: 500, headers });
    }
  }
}

export default BooksAPIProxyWorker;

/**
 * Handles bookshelf image scanning.
 * In the future, this will call an AI service to detect books.
 */
async function handleBookshelfScan(request, env, ctx) {
    // In the future, we'll get the image data from the request body
    // const imageData = await request.arrayBuffer();

    // For now, return mocked data
    const mockedResponse = {
        kind: "books#volumes",
        totalItems: 2,
        items: [
            {
                volumeInfo: {
                    title: "The Hobbit",
                    authors: ["J.R.R. Tolkien"],
                    imageLinks: {
                        thumbnail: "https://books.google.com/books/content?id=pD6arNyKyi8C&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api"
                    }
                }
            },
            {
                volumeInfo: {
                    title: "The Lord of the Rings",
                    authors: ["J.R.R. Tolkien"],
                    imageLinks: {
                        thumbnail: "https://books.google.com/books/content?id=pD6arNyKyi8C&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api"
                    }
                }
            }
        ],
        provider: "mocked-ai-scan",
        cached: false,
        responseTime: 100
    };

    return mockedResponse;
}
