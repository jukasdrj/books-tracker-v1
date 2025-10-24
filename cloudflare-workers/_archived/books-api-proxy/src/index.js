import { WorkerEntrypoint } from 'cloudflare:workers';
import { handleGeneralSearch, handleAuthorSearch, handleTitleSearch, handleSubjectSearch, handleAdvancedSearch, handleISBNSearch } from './search-handlers.js';
import { EnrichmentCoordinator } from './enrichment-coordinator.js';
import {
  StructuredLogger,
  PerformanceTimer,
  CachePerformanceMonitor,
  ProviderHealthMonitor
} from '../../structured-logging-infrastructure.js';

/**
 * Books API Proxy - RPC-enabled worker
 * Exposes both HTTP endpoints (for external clients) and RPC methods (for other workers)
 */
export class BooksAPIProxyWorker extends WorkerEntrypoint {
  constructor(ctx, env) {
    super(ctx, env);
    // Initialize structured logging (Phase B)
    this.logger = new StructuredLogger('books-api-proxy', env);
    this.cacheMonitor = new CachePerformanceMonitor(this.logger);
    this.providerMonitor = new ProviderHealthMonitor(this.logger);
  }
  /**
   * RPC Method: Search for books by general query
   * @param {string} query - Search query
   * @param {Object} options - Search options {maxResults, page}
   * @returns {Promise<Object>} Search results
   */
  async searchBooks(query, options = {}) {
    const timer = new PerformanceTimer(this.logger, 'rpc_searchBooks');
    const { maxResults = 20, page = 0 } = options;

    const result = await handleGeneralSearch(
      { url: `?q=${encodeURIComponent(query)}&maxResults=${maxResults}&page=${page}` },
      this.env,
      this.ctx,
      {},
      {
        logger: this.logger,
        cacheMonitor: this.cacheMonitor,
        providerMonitor: this.providerMonitor
      }
    );

    await timer.end({ query, resultsCount: result.items?.length || 0 });
    return result;
  }

  /**
   * RPC Method: Search for books by author
   * @param {string} authorName - Author name
   * @param {Object} options - Search options
   * @returns {Promise<Object>} Author bibliography
   */
  async searchByAuthor(authorName, options = {}) {
    const timer = new PerformanceTimer(this.logger, 'rpc_searchByAuthor');
    const { maxResults = 20, page = 0 } = options;

    const result = await handleAuthorSearch(
      authorName,
      { maxResults, page },
      this.env,
      this.ctx,
      {
        logger: this.logger,
        cacheMonitor: this.cacheMonitor,
        providerMonitor: this.providerMonitor
      }
    );

    await timer.end({ authorName, resultsCount: result.items?.length || 0 });
    return result;
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
   * RPC Method: Start batch enrichment with WebSocket progress
   * Called by clients (iOS app) to enrich multiple works
   * @param {string} jobId - Job identifier for WebSocket tracking
   * @param {string[]} workIds - Array of work IDs to enrich
   * @param {Object} options - Enrichment options
   * @returns {Promise<Object>} Enrichment result
   */
  async startBatchEnrichment(jobId, workIds, options = {}) {
    const timer = new PerformanceTimer(this.logger, 'rpc_startBatchEnrichment');

    const coordinator = new EnrichmentCoordinator(this.env, this.logger);
    const result = await coordinator.startEnrichment(jobId, workIds, options);

    await timer.end({ jobId, workIdsCount: workIds.length, success: result.success });
    return result;
  }

  /**
   * Handle enrichment job start request
   * Triggers background enrichment with WebSocket progress
   * @param {Request} request - POST request with jobId and workIds
   * @returns {Promise<Response>} Job start confirmation
   */
  async handleEnrichmentStart(request) {
    try {
      const { jobId, workIds } = await request.json();

      if (!jobId || !workIds || !Array.isArray(workIds)) {
        return new Response(JSON.stringify({
          error: 'Missing required fields: jobId, workIds'
        }), {
          status: 400,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        });
      }

      // Trigger enrichment worker (non-blocking)
      // Worker will push progress updates via WebSocket
      this.ctx.waitUntil(
        this.env.ENRICHMENT_WORKER.enrichBatch(jobId, workIds)
      );

      // Return immediately - client will receive updates via WebSocket
      return new Response(JSON.stringify({
        success: true,
        jobId: jobId,
        totalCount: workIds.length,
        processedCount: 0,
        status: 'started',
        message: 'Connect to /ws/progress?jobId=' + jobId + ' for real-time updates'
      }), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });

    } catch (error) {
      return new Response(JSON.stringify({
        error: 'Failed to start enrichment',
        details: error.message
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    }
  }

  /**
   * Handle WebSocket upgrade request
   * Delegates to Durable Object for connection management
   * @param {Request} request - WebSocket upgrade request
   * @returns {Promise<Response>} WebSocket response or error
   */
  async handleWebSocketUpgrade(request) {
    const url = new URL(request.url);
    const jobId = url.searchParams.get('jobId');

    if (!jobId) {
      return new Response('Missing jobId parameter', {
        status: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'text/plain'
        }
      });
    }

    // Get Durable Object stub for this jobId
    const doId = this.env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
    const stub = this.env.PROGRESS_WEBSOCKET_DO.get(doId);

    // Forward upgrade request to Durable Object
    return await stub.fetch(request);
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
      // WebSocket progress endpoint
      if (path === '/ws/progress') {
        return this.handleWebSocketUpgrade(request);
      }

      // Enrichment trigger endpoint
      if (path === '/api/enrichment/start' && request.method === 'POST') {
        return await this.handleEnrichmentStart(request);
      }

      // Bookshelf image scanning endpoint (from ship branch)
      if (path.startsWith('/api/scan-bookshelf')) {
        if (request.method !== 'POST') {
          return new Response(JSON.stringify({ error: 'Method not allowed. Use POST.' }), {
            status: 405, headers
          });
        }
        const result = await handleBookshelfScan(request, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      // Query parameters for search endpoints
      const query = url.searchParams.get('q');
      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const page = parseInt(url.searchParams.get('page') || '0');

      // Multi-context search endpoints
      if (path.startsWith('/search/author')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleAuthorSearch(query, { maxResults, page }, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/title')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleTitleSearch(query, { maxResults, page }, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/subject')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleSubjectSearch(query, { maxResults, page }, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/isbn')) {
        if (!query) return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
        const result = await handleISBNSearch(query, { maxResults, page }, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/advanced')) {
        const authorName = url.searchParams.get('author');
        const bookTitle = url.searchParams.get('title');
        const isbn = url.searchParams.get('isbn');
        if (!authorName && !bookTitle && !isbn) return new Response(JSON.stringify({ error: "At least one search parameter required (author, title, or isbn)" }), { status: 400, headers });
        const result = await handleAdvancedSearch({ authorName, bookTitle, isbn }, { maxResults, page }, this.env, this.ctx);
        return new Response(JSON.stringify(result), { headers });
      }

      if (path.startsWith('/search/auto') || path.startsWith('/search')) {
        return await handleGeneralSearch(request, this.env, this.ctx, headers);
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
