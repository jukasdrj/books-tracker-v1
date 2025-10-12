import { handleGeneralSearch, handleAuthorSearch, handleTitleSearch, handleSubjectSearch, handleAdvancedSearch, handleISBNSearch } from './search-handlers.js';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }

    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    };

    try {
      const query = url.searchParams.get('q');
      const maxResults = parseInt(url.searchParams.get('maxResults') || '20');
      const page = parseInt(url.searchParams.get('page') || '0');

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
};

