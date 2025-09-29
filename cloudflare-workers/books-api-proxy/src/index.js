/**
 * Books API Proxy - Orchestrator
 *
 * Implements the "best-of-both-worlds" strategy:
 * 1. Fetches canonical works from OpenLibrary.
 * 2. Enhances each work with rich edition data from ISBNdb.
 * 3. Handles direct ISBN lookups.
 * 4. Caches the final, aggregated results.
 */
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle CORS preflight requests
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
      if (path.startsWith('/author/enhanced/')) {
        return await handleEnhancedAuthor(request, env, ctx, headers);
      }
      if (path.startsWith('/book/isbn/')) {
        return await handleDirectISBN(request, env, ctx, headers);
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

/**
 * Handles the primary author lookup and enhancement workflow.
 */
async function handleEnhancedAuthor(request, env, ctx, headers) {
    const url = new URL(request.url);
    const authorName = decodeURIComponent(url.pathname.replace('/author/enhanced/', ''));
    if (!authorName) return new Response(JSON.stringify({ error: "Author name required" }), { status: 400, headers });

    const cacheKey = `author_v2:${authorName.toLowerCase()}`;
    const cached = await env.CACHE.get(cacheKey, 'json');
    if (cached) {
        console.log(`Cache HIT for author v2: ${authorName}`);
        return new Response(JSON.stringify({ ...cached, cached: true }), { headers });
    }

    console.log(`Cache MISS for author v2. Orchestrating lookup for: ${authorName}`);

    // Step 1: Get canonical works list from OpenLibrary worker
    const olResult = await env.OPENLIBRARY_WORKER.getAuthorWorks(authorName);
    if (!olResult.success) throw new Error(`OpenLibrary failed: ${olResult.error}`);

    let { works, author } = olResult;
    console.log(`Received ${works.length} works from OpenLibrary for ${authorName}`);

    // Step 2: Concurrently enhance each work with editions from ISBNdb worker
    const enhancementPromises = works.map(async (work) => {
        const isbndbResult = await env.ISBNDB_WORKER.getEditionsForWork(work.title, author.name);
        if (isbndbResult.success) {
            work.editions = isbndbResult.editions;
        }
        return work;
    });

    const enhancedWorks = await Promise.all(enhancementPromises);
    
    const responseData = {
        success: true,
        provider: 'orchestrated:openlibrary+isbndb',
        author: author,
        works: enhancedWorks,
    };

    ctx.waitUntil(env.CACHE.put(cacheKey, JSON.stringify(responseData), { expirationTtl: 86400 })); // 24 hours

    return new Response(JSON.stringify({ ...responseData, cached: false }), { headers });
}

/**
 * Handles a direct ISBN lookup via the ISBNdb worker.
 */
async function handleDirectISBN(request, env, ctx, headers) {
    const url = new URL(request.url);
    const isbn = decodeURIComponent(url.pathname.replace('/book/isbn/', ''));
    if (!isbn) return new Response(JSON.stringify({ error: "ISBN required" }), { status: 400, headers });
    
    const cacheKey = `isbn:${isbn}`;
    const cached = await env.CACHE.get(cacheKey, 'json');
    if (cached) {
        console.log(`Cache HIT for ISBN: ${isbn}`);
        return new Response(JSON.stringify({ ...cached, cached: true }), { headers });
    }

    console.log(`Cache MISS for ISBN: ${isbn}. Calling ISBNdb worker.`);
    
    const result = await env.ISBNDB_WORKER.getBookByISBN(isbn);
    if (!result.success) throw new Error(`ISBNdb failed for ${isbn}: ${result.error}`);

    ctx.waitUntil(env.CACHE.put(cacheKey, JSON.stringify(result), { expirationTtl: 86400 * 7 })); // 7 days

    return new Response(JSON.stringify({ ...result, cached: false }), { headers });
}