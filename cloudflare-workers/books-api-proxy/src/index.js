/**
 * Books API Proxy - RPC Enhanced
 *
 * Orchestrates calls to specialty workers (ISBNdb, OpenLibrary) using direct RPC
 * for maximum performance and reliability. Caches the aggregated results.
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle CORS preflight requests first
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    // Add CORS headers to all responses
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json'
    };

    try {
        if (path.startsWith('/author/enhanced/')) {
            const response = await handleEnhancedAuthorBibliography(request, env, ctx);
            // Clone the response to add CORS headers
            const newResponse = new Response(response.body, response);
            Object.entries(corsHeaders).forEach(([key, value]) => {
                newResponse.headers.set(key, value);
            });
            return newResponse;
        }

        // Health check endpoint
        if (path === '/health') {
            return new Response(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }), {
                headers: corsHeaders,
            });
        }

        // Fallback for other routes
        return new Response(JSON.stringify({ error: 'Endpoint not found' }), {
            status: 404,
            headers: corsHeaders,
        });

    } catch (error) {
        console.error('Error in main fetch handler:', error);
        return new Response(JSON.stringify({ error: 'Internal Server Error', details: error.message }), {
            status: 500,
            headers: corsHeaders,
        });
    }
  }
};

/**
 * Enhanced Author Bibliography Handler
 * 1. Calls OpenLibrary worker via RPC to get the list of works.
 * 2. Calls ISBNdb worker via RPC to enhance those works with edition data.
 * 3. Caches the final, merged result.
 */
async function handleEnhancedAuthorBibliography(request, env, ctx) {
    const url = new URL(request.url);
    const authorName = decodeURIComponent(url.pathname.replace('/author/enhanced/', ''));

    if (!authorName) {
        return new Response(JSON.stringify({ success: false, error: "Author name is required." }), { status: 400 });
    }

    const cacheKey = `author_enhanced:${authorName.toLowerCase()}`;
    
    try {
        const cached = await env.CACHE.get(cacheKey, 'json');
        if (cached) {
            console.log(`Cache HIT for enhanced author: ${authorName}`);
            return new Response(JSON.stringify({ ...cached, cached: true }));
        }
    } catch (e) {
        console.error("Cache read error:", e);
    }

    console.log(`Cache MISS. Starting enhanced lookup for: ${authorName}`);

    // Step 1: Get authoritative works list from OpenLibrary worker via RPC
    const olData = await env.OPENLIBRARY_WORKER.getAuthorBibliography(authorName);
    if (!olData || !olData.success) {
        throw new Error(`OpenLibrary worker failed: ${olData.error || 'No works found'}`);
    }
    console.log(`OpenLibrary returned ${olData.works?.length || 0} works for ${authorName}`);

    // Step 2: Enhance works with ISBNdb edition data via RPC
    const enhancementResult = await env.ISBNDB_WORKER.enhanceWorksWithEditions(olData.works, authorName);
    if (!enhancementResult || !enhancementResult.success) {
        console.warn(`ISBNdb enhancement failed, returning OpenLibrary data only.`);
    }

    const finalWorks = enhancementResult.success ? enhancementResult.works : olData.works;

    const responseData = {
        success: true,
        provider: 'openlibrary+isbndb',
        author: olData.authors ? olData.authors[0] : { name: authorName },
        works: finalWorks,
    };

    // Step 3: Cache the final result asynchronously
    ctx.waitUntil(env.CACHE.put(cacheKey, JSON.stringify(responseData), { expirationTtl: 86400 })); // 24 hours

    return new Response(JSON.stringify({ ...responseData, cached: false }));
}