import { transformWorkToGoogleFormat, deduplicateGoogleBooksItems, filterGoogleBooksItems, filterPrimaryWorks } from './transformers.js';
import { advancedDeduplication, isLikelyAuthorQuery } from './utils.js';

export async function handleAuthorSearch(query, { maxResults, page }, env, ctx) {
    // Implement author search logic here
}

export async function handleTitleSearch(query, { maxResults, page }, env, ctx) {
    // Implement title search logic here
}

export async function handleSubjectSearch(query, { maxResults, page }, env, ctx) {
    // Implement subject search logic here
}

export async function handleISBNSearch(query, { maxResults, page }, env, ctx) {
    // Implement ISBN search logic here
}

export async function handleAdvancedSearch({ authorName, bookTitle, isbn }, { maxResults, page }, env, ctx) {
    // Implement advanced search logic here
}

export async function handleGeneralSearch(request, env, ctx, headers) {
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
        const isAuthorSearch = isLikelyAuthorQuery(query);

        if (isAuthorSearch) {
            console.log(`Detected author search for: ${query}. Using OpenLibrary-first workflow.`);

            const olResult = await env.EXTERNAL_APIS_WORKER.getOpenLibraryAuthorWorks(query);
            if (!olResult.success) {
                throw new Error(`OpenLibrary author search failed: ${olResult.error}`);
            }

            let { works, author } = olResult;
            console.log(`Retrieved ${works.length} works from OpenLibrary for ${query}`);

            const topWorks = works.slice(0, maxResults);
            const enhancementPromises = topWorks.map(async (work) => {
                const isbndbResult = await env.EXTERNAL_APIS_WORKER.getISBNdbEditionsForWork(work.title, author.name);
                if (isbndbResult.success && isbndbResult.editions) {
                    work.editions = [...(work.editions || []), ...isbndbResult.editions];
                }
                return work;
            });

            const enhancedWorks = await Promise.allSettled(enhancementPromises);
            const finalWorks = enhancedWorks
                .filter(result => result.status === 'fulfilled')
                .map(result => result.value);

            const responseData = {
                kind: "books#volumes",
                totalItems: finalWorks.length,
                items: finalWorks.map(work => transformWorkToGoogleFormat(work)),
                format: "enhanced_work_edition_v1",
                provider: "orchestrated:openlibrary+isbndb",
                cached: false,
                responseTime: Date.now() - startTime
            };

            ctx.waitUntil(env.CACHE.put(cacheKey, JSON.stringify(responseData), { expirationTtl: 3600 }));
            return new Response(JSON.stringify(responseData), {
                headers: { ...headers, 'X-Cache': 'MISS', 'X-Provider': responseData.provider }
            });
        }

        console.log(`General book search for: ${query}. Using parallel provider workflow.`);
        const searchPromises = [
            env.EXTERNAL_APIS_WORKER.searchGoogleBooks(query, { maxResults }),
            env.EXTERNAL_APIS_WORKER.searchOpenLibrary(query, { maxResults }),
        ];

        const results = await Promise.allSettled(searchPromises);

        let finalItems = [];
        let successfulProviders = [];

        if (results[0].status === 'fulfilled' && results[0].value.success) {
            const googleData = results[0].value;
            if (googleData.items) {
                const filteredItems = filterGoogleBooksItems(googleData.items, query);
                finalItems = [...finalItems, ...filteredItems];
            } else if (googleData.works) {
                const transformedItems = googleData.works.map(work => transformWorkToGoogleFormat(work));
                finalItems = [...finalItems, ...transformedItems];
            }
            successfulProviders.push('google');
        }

        if (results[1].status === 'fulfilled' && results[1].value.success) {
            const olData = results[1].value;
            if (olData.works) {
                const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
                finalItems = [...finalItems, ...transformedItems];
            }
            successfulProviders.push('openlibrary');
        }

        const dedupedItems = deduplicateGoogleBooksItems(finalItems);
        const finalFilteredItems = filterGoogleBooksItems(dedupedItems, query);

        const responseData = {
            kind: "books#volumes",
            totalItems: finalFilteredItems.length,
            items: finalFilteredItems,
            format: "enhanced_work_edition_v1",
            provider: `orchestrated:${successfulProviders.join('+')}`,
            cached: false,
            responseTime: Date.now() - startTime
        };

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
