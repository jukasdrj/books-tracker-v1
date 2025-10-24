import { ProgressWebSocketDO } from './durable-objects/progress-socket.js';
import * as externalApis from './services/external-apis.js';

// Export the Durable Object class for Cloudflare Workers runtime
export { ProgressWebSocketDO };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Route WebSocket connections to the Durable Object
    if (url.pathname === '/ws/progress') {
      const jobId = url.searchParams.get('jobId');
      if (!jobId) {
        return new Response('Missing jobId parameter', { status: 400 });
      }

      // Get Durable Object instance for this specific jobId
      const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
      const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

      // Forward the request to the Durable Object
      return doStub.fetch(request);
    }

    // ========================================================================
    // External API Routes (backward compatibility - temporary during migration)
    // ========================================================================

    // Google Books search
    if (url.pathname === '/external/google-books') {
      const query = url.searchParams.get('q');
      if (!query) {
        return new Response(JSON.stringify({ error: 'Missing query parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const result = await externalApis.searchGoogleBooks(query, { maxResults }, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Google Books ISBN search
    if (url.pathname === '/external/google-books-isbn') {
      const isbn = url.searchParams.get('isbn');
      if (!isbn) {
        return new Response(JSON.stringify({ error: 'Missing isbn parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.searchGoogleBooksByISBN(isbn, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // OpenLibrary search
    if (url.pathname === '/external/openlibrary') {
      const query = url.searchParams.get('q');
      if (!query) {
        return new Response(JSON.stringify({ error: 'Missing query parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const result = await externalApis.searchOpenLibrary(query, { maxResults }, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // OpenLibrary author works
    if (url.pathname === '/external/openlibrary-author') {
      const author = url.searchParams.get('author');
      if (!author) {
        return new Response(JSON.stringify({ error: 'Missing author parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getOpenLibraryAuthorWorks(author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb search
    if (url.pathname === '/external/isbndb') {
      const title = url.searchParams.get('title');
      if (!title) {
        return new Response(JSON.stringify({ error: 'Missing title parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const author = url.searchParams.get('author') || '';
      const result = await externalApis.searchISBNdb(title, author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb editions for work
    if (url.pathname === '/external/isbndb-editions') {
      const title = url.searchParams.get('title');
      const author = url.searchParams.get('author');

      if (!title || !author) {
        return new Response(JSON.stringify({ error: 'Missing title or author parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getISBNdbEditionsForWork(title, author, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // ISBNdb book by ISBN
    if (url.pathname === '/external/isbndb-isbn') {
      const isbn = url.searchParams.get('isbn');
      if (!isbn) {
        return new Response(JSON.stringify({ error: 'Missing isbn parameter' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }

      const result = await externalApis.getISBNdbBookByISBN(isbn, env);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Health check endpoint
    if (url.pathname === '/health') {
      return new Response(JSON.stringify({
        status: 'ok',
        worker: 'api-worker',
        version: '1.0.0',
        endpoints: [
          '/ws/progress?jobId={id}',
          '/external/google-books?q={query}&maxResults={n}',
          '/external/google-books-isbn?isbn={isbn}',
          '/external/openlibrary?q={query}&maxResults={n}',
          '/external/openlibrary-author?author={name}',
          '/external/isbndb?title={title}&author={author}',
          '/external/isbndb-editions?title={title}&author={author}',
          '/external/isbndb-isbn?isbn={isbn}'
        ]
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Default 404
    return new Response(JSON.stringify({
      error: 'Not Found',
      message: 'The requested endpoint does not exist. Use /health to see available endpoints.'
    }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
