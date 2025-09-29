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
      if (path.startsWith('/search/auto') || path.startsWith('/search')) {
        return await handleGeneralSearch(request, env, ctx, headers);
      }
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

/**
 * Handles general search queries using the multi-provider worker orchestration
 */
async function handleGeneralSearch(request, env, ctx, headers) {
    const url = new URL(request.url);
    const query = url.searchParams.get('q');
    const maxResults = parseInt(url.searchParams.get('maxResults') || '20');

    if (!query) {
        return new Response(JSON.stringify({ error: "Query parameter 'q' required" }), { status: 400, headers });
    }

    const cacheKey = `search:${query.toLowerCase()}:${maxResults}`;
    const cached = await env.CACHE.get(cacheKey, 'json');
    if (cached) {
        console.log(`Cache HIT for search: ${query}`);
        return new Response(JSON.stringify({ ...cached, cached: true }), {
            headers: { ...headers, 'X-Cache': 'HIT', 'X-Provider': cached.provider }
        });
    }

    console.log(`Cache MISS for search: ${query}. Orchestrating multi-provider search.`);
    const startTime = Date.now();

    try {
        // Execute parallel searches across multiple providers
        const searchPromises = [
            env.GOOGLE_BOOKS_WORKER.search(query, { maxResults }),
            env.OPENLIBRARY_WORKER.search(query, { maxResults }),
            // ISBNdb for text search is typically less relevant for general search
        ];

        // Wait for all providers to respond (with timeout)
        const results = await Promise.allSettled(searchPromises);

        // Process results and combine them intelligently
        let aggregatedWorks = [];
        let primaryProvider = 'multi-provider';
        let successfulProviders = [];

        // Process Google Books results
        if (results[0].status === 'fulfilled' && results[0].value.success) {
            const googleData = results[0].value;
            aggregatedWorks = [...aggregatedWorks, ...googleData.works];
            successfulProviders.push('google');
            if (!primaryProvider || primaryProvider === 'multi-provider') {
                primaryProvider = 'google';
            }
        }

        // Process OpenLibrary results
        if (results[1].status === 'fulfilled' && results[1].value.success) {
            const olData = results[1].value;
            // Merge works, avoiding duplicates by title
            const existingTitles = new Set(aggregatedWorks.map(w => w.title.toLowerCase()));
            const newWorks = olData.works.filter(w => !existingTitles.has(w.title.toLowerCase()));
            aggregatedWorks = [...aggregatedWorks, ...newWorks];
            successfulProviders.push('openlibrary');
        }

        if (aggregatedWorks.length === 0) {
            throw new Error('No results from any provider');
        }

        // Transform to Google Books API compatible format for iOS app
        const responseData = {
            kind: "books#volumes",
            totalItems: aggregatedWorks.length,
            items: aggregatedWorks.map(work => transformWorkToGoogleFormat(work)),
            format: "enhanced_work_edition_v1",
            provider: `orchestrated:${successfulProviders.join('+')}`,
            cached: false,
            responseTime: Date.now() - startTime
        };

        // Cache for 1 hour (searches change frequently)
        ctx.waitUntil(env.CACHE.put(cacheKey, JSON.stringify(responseData), { expirationTtl: 3600 }));

        return new Response(JSON.stringify(responseData), {
            headers: { ...headers, 'X-Cache': 'MISS', 'X-Provider': responseData.provider }
        });

    } catch (error) {
        console.error(`Search failed for "${query}":`, error);
        return new Response(JSON.stringify({
            error: 'Search failed',
            details: error.message
        }), { status: 500, headers });
    }
}

/**
 * Transform a Work object to Google Books API format for iOS app compatibility
 */
function transformWorkToGoogleFormat(work) {
    const primaryEdition = work.editions && work.editions.length > 0 ? work.editions[0] : null;

    return {
        kind: "books#volume",
        id: work.id || work.googleBooksVolumeID || `synthetic-${work.title.replace(/\s+/g, '-').toLowerCase()}`,
        volumeInfo: {
            title: work.title,
            subtitle: work.subtitle || "",
            authors: work.authors ? work.authors.map(a => typeof a === 'string' ? a : a.name) : [],
            publisher: primaryEdition?.publisher || "",
            publishedDate: work.firstPublicationYear ? work.firstPublicationYear.toString() : (primaryEdition?.publicationDate || ""),
            description: work.description || primaryEdition?.description || "",
            industryIdentifiers: primaryEdition?.isbn ? [
                { type: "ISBN_13", identifier: primaryEdition.isbn }
            ] : [],
            pageCount: primaryEdition?.pageCount || 0,
            categories: work.subjects || [],
            imageLinks: primaryEdition?.coverImageURL ? {
                thumbnail: primaryEdition.coverImageURL,
                smallThumbnail: primaryEdition.coverImageURL
            } : undefined
        }
    };
}

