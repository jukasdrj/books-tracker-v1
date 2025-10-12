/**
 * Search Context Handlers - Specialized routing for different search types
 *
 * This module implements three dedicated search contexts with optimal provider routing:
 * 1. Author Search: OpenLibrary canonical works → ISBNdb edition enhancement
 * 2. Title Search: Google Books primary → OpenLibrary cross-validation
 * 3. Subject Search: OpenLibrary subjects → Google Books category filtering
 *
 * Each context uses different:
 * - Provider routing strategies (sequential vs parallel)
 * - Cache TTLs (24h author, 6h title, 12h subject)
 * - Fallback patterns (graceful degradation)
 * - Response enhancement pipelines
 */

import {
    transformWorkToGoogleFormat,
    deduplicateGoogleBooksItems,
    filterGoogleBooksItems
} from './transformers.js';

/**
 * Cache TTL Configuration (in seconds)
 */
export const CACHE_TTLS = {
    AUTHOR: 86400,      // 24 hours - author bibliographies change slowly
    TITLE: 21600,       // 6 hours - title searches are more dynamic
    SUBJECT: 43200,     // 12 hours - subject catalogs change moderately
    ISBN: 604800,       // 7 days - ISBN lookups are essentially immutable
};

/**
 * Context identifiers for response metadata
 */
export const SEARCH_CONTEXTS = {
    AUTHOR: 'author',
    TITLE: 'title',
    SUBJECT: 'subject',
    ISBN: 'isbn',
    GENERAL: 'general'
};

/**
 * Author Search Handler
 *
 * Strategy: OpenLibrary-first for canonical works list, then parallel ISBNdb enhancement
 * Rationale: OpenLibrary has the most comprehensive author bibliography data
 * Fallback: Google Books if OpenLibrary fails
 * Cache: 24 hours (author bibliographies are relatively stable)
 *
 * @param {string} query - Author name
 * @param {object} params - { maxResults, page }
 * @param {object} env - Worker environment bindings
 * @param {object} ctx - Execution context
 * @returns {Promise<object>} - Orchestrated search results
 */
export async function handleAuthorSearch(query, params, env, ctx) {
    const startTime = Date.now();
    const maxResults = params.maxResults || 20;
    const page = params.page || 0;

    const cacheKey = `search:author:${query.toLowerCase()}:${maxResults}:${page}`;

    try {
        // Step 1: Check cache
        const cached = await env.CACHE.get(cacheKey, 'json');
        if (cached) {
            console.log(`✅ Cache HIT - Author search: "${query}"`);
            await trackCacheMetric(env, 'author', 'hit', query);
            return {
                ...cached,
                cached: true,
                cacheAge: Date.now() - (cached.timestamp || startTime)
            };
        }

        console.log(`❌ Cache MISS - Author search: "${query}". Orchestrating providers.`);
        await trackCacheMetric(env, 'author', 'miss', query);

        // Step 2: Primary strategy - OpenLibrary canonical works
        console.log(`📚 Primary: Fetching canonical works from OpenLibrary for "${query}"`);
        const olResult = await env.OPENLIBRARY_WORKER.getAuthorWorks(query);

        if (olResult.success && olResult.works && olResult.works.length > 0) {
            console.log(`✅ OpenLibrary: Found ${olResult.works.length} works for "${query}"`);

            // Step 3: Parallel enhancement with ISBNdb for edition details
            const paginatedWorks = paginateResults(olResult.works, page, maxResults);
            const enhancedWorks = await enhanceWorksWithEditions(
                paginatedWorks,
                olResult.author.name,
                env
            );

            const responseData = {
                kind: "books#volumes",
                totalItems: olResult.works.length,
                items: enhancedWorks.map(work => transformWorkToGoogleFormat(work)),
                format: "enhanced_work_edition_v1",
                provider: "orchestrated:openlibrary+isbndb",
                searchContext: SEARCH_CONTEXTS.AUTHOR,
                cached: false,
                responseTime: Date.now() - startTime,
                timestamp: Date.now(),
                pagination: {
                    page,
                    maxResults,
                    totalPages: Math.ceil(olResult.works.length / maxResults)
                }
            };

            // Cache for 24 hours
            ctx.waitUntil(
                env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                    expirationTtl: CACHE_TTLS.AUTHOR
                })
            );

            await trackProviderMetric(env, 'openlibrary', 'success', 'author', Date.now() - startTime);
            return responseData;
        }

        // Step 4: Fallback to Google Books for author search
        console.log(`⚠️ OpenLibrary failed for "${query}". Falling back to Google Books.`);
        await trackProviderMetric(env, 'openlibrary', 'failure', 'author', Date.now() - startTime);

        const googleResult = await env.GOOGLE_BOOKS_WORKER.search(`inauthor:"${query}"`, { maxResults });

        if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
            console.log(`✅ Google Books fallback: Found ${googleResult.works.length} works`);

            const responseData = {
                kind: "books#volumes",
                totalItems: googleResult.works.length,
                items: googleResult.works.map(work => transformWorkToGoogleFormat(work)),
                format: "enhanced_work_edition_v1",
                provider: "fallback:google-books",
                searchContext: SEARCH_CONTEXTS.AUTHOR,
                cached: false,
                responseTime: Date.now() - startTime,
                timestamp: Date.now(),
                fallbackReason: "OpenLibrary unavailable"
            };

            // Cache fallback results for shorter duration (1 hour)
            ctx.waitUntil(
                env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                    expirationTtl: 3600
                })
            );

            await trackProviderMetric(env, 'google-books', 'success', 'author-fallback', Date.now() - startTime);
            return responseData;
        }

        // Step 5: No results from any provider
        throw new Error(`No author results found for "${query}" from any provider`);

    } catch (error) {
        console.error(`❌ Author search failed for "${query}":`, error);
        await trackProviderMetric(env, 'all', 'error', 'author', Date.now() - startTime);

        return {
            kind: "books#volumes",
            totalItems: 0,
            items: [],
            error: 'Author search failed',
            details: error.message,
            searchContext: SEARCH_CONTEXTS.AUTHOR,
            provider: 'none',
            responseTime: Date.now() - startTime
        };
    }
}

/**
 * Title Search Handler
 *
 * Strategy: Google Books primary (best title matching), OpenLibrary cross-validation
 * Rationale: Google Books has superior title search algorithms and relevance ranking
 * Fallback: OpenLibrary if Google fails
 * Cache: 6 hours (title searches benefit from fresh data)
 *
 * @param {string} query - Book title
 * @param {object} params - { maxResults, page }
 * @param {object} env - Worker environment bindings
 * @param {object} ctx - Execution context
 * @returns {Promise<object>} - Orchestrated search results
 */
export async function handleTitleSearch(query, params, env, ctx) {
    const startTime = Date.now();
    const maxResults = params.maxResults || 20;
    const page = params.page || 0;

    const cacheKey = `search:title:${query.toLowerCase()}:${maxResults}:${page}`;

    try {
        // Step 1: Check cache
        const cached = await env.CACHE.get(cacheKey, 'json');
        if (cached) {
            console.log(`✅ Cache HIT - Title search: "${query}"`);
            await trackCacheMetric(env, 'title', 'hit', query);
            return {
                ...cached,
                cached: true,
                cacheAge: Date.now() - (cached.timestamp || startTime)
            };
        }

        console.log(`❌ Cache MISS - Title search: "${query}". Orchestrating providers.`);
        await trackCacheMetric(env, 'title', 'miss', query);

        // Step 2: Primary strategy - Google Books (best title matching)
        console.log(`🔍 Primary: Searching Google Books for title "${query}"`);
        const googlePromise = env.GOOGLE_BOOKS_WORKER.search(`intitle:"${query}"`, { maxResults: maxResults * 2 });

        // Step 3: Parallel cross-validation with OpenLibrary
        console.log(`📚 Secondary: Cross-validating with OpenLibrary for "${query}"`);
        const openLibraryPromise = env.OPENLIBRARY_WORKER.search(query, { maxResults: maxResults });

        // Execute both searches in parallel
        const [googleResult, olResult] = await Promise.allSettled([
            googlePromise,
            openLibraryPromise
        ]);

        // Step 4: Process results with intelligent merging
        let finalItems = [];
        let providers = [];

        // Process Google Books results (primary)
        if (googleResult.status === 'fulfilled' && googleResult.value.success) {
            const googleData = googleResult.value;
            console.log(`✅ Google Books: Found ${googleData.works?.length || 0} works`);

            if (googleData.works && googleData.works.length > 0) {
                const googleItems = googleData.works.map(work => transformWorkToGoogleFormat(work));
                finalItems = [...finalItems, ...googleItems];
                providers.push('google-books');
                await trackProviderMetric(env, 'google-books', 'success', 'title', Date.now() - startTime);
            }
        } else {
            console.log(`⚠️ Google Books failed for title "${query}"`);
            await trackProviderMetric(env, 'google-books', 'failure', 'title', Date.now() - startTime);
        }

        // Process OpenLibrary results (cross-validation)
        if (olResult.status === 'fulfilled' && olResult.value.success) {
            const olData = olResult.value;
            console.log(`✅ OpenLibrary: Found ${olData.works?.length || 0} works`);

            if (olData.works && olData.works.length > 0) {
                const olItems = olData.works.map(work => transformWorkToGoogleFormat(work));

                // Merge with Google results, avoiding duplicates
                const existingTitles = new Set(
                    finalItems.map(item => item.volumeInfo.title.toLowerCase())
                );

                const newItems = olItems.filter(item =>
                    !existingTitles.has(item.volumeInfo.title.toLowerCase())
                );

                finalItems = [...finalItems, ...newItems];
                providers.push('openlibrary');
                await trackProviderMetric(env, 'openlibrary', 'success', 'title', Date.now() - startTime);
            }
        } else {
            console.log(`⚠️ OpenLibrary failed for title "${query}"`);
            await trackProviderMetric(env, 'openlibrary', 'failure', 'title', Date.now() - startTime);
        }

        // Step 5: Apply filtering and deduplication
        const dedupedItems = deduplicateGoogleBooksItems(finalItems);
        const filteredItems = filterGoogleBooksItems(dedupedItems, query);

        // Step 6: Apply pagination
        const paginatedItems = paginateResults(filteredItems, page, maxResults);

        if (paginatedItems.length === 0) {
            throw new Error(`No title results found for "${query}"`);
        }

        const responseData = {
            kind: "books#volumes",
            totalItems: filteredItems.length,
            items: paginatedItems,
            format: "enhanced_work_edition_v1",
            provider: `orchestrated:${providers.join('+')}`,
            searchContext: SEARCH_CONTEXTS.TITLE,
            cached: false,
            responseTime: Date.now() - startTime,
            timestamp: Date.now(),
            pagination: {
                page,
                maxResults,
                totalPages: Math.ceil(filteredItems.length / maxResults)
            }
        };

        // Cache for 6 hours
        ctx.waitUntil(
            env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                expirationTtl: CACHE_TTLS.TITLE
            })
        );

        return responseData;

    } catch (error) {
        console.error(`❌ Title search failed for "${query}":`, error);
        await trackProviderMetric(env, 'all', 'error', 'title', Date.now() - startTime);

        return {
            kind: "books#volumes",
            totalItems: 0,
            items: [],
            error: 'Title search failed',
            details: error.message,
            searchContext: SEARCH_CONTEXTS.TITLE,
            provider: 'none',
            responseTime: Date.now() - startTime
        };
    }
}

/**
 * Subject/Genre Search Handler
 *
 * Strategy: OpenLibrary subjects primary, Google Books category filtering secondary
 * Rationale: OpenLibrary has rich subject taxonomies; Google categories provide commercial validation
 * Parallel: Both providers execute simultaneously for speed
 * Cache: 12 hours (subject catalogs change moderately)
 *
 * @param {string} query - Subject/genre (e.g., "science fiction", "biography")
 * @param {object} params - { maxResults, page }
 * @param {object} env - Worker environment bindings
 * @param {object} ctx - Execution context
 * @returns {Promise<object>} - Orchestrated search results
 */
export async function handleSubjectSearch(query, params, env, ctx) {
    const startTime = Date.now();
    const maxResults = params.maxResults || 20;
    const page = params.page || 0;

    const cacheKey = `search:subject:${query.toLowerCase()}:${maxResults}:${page}`;

    try {
        // Step 1: Check cache
        const cached = await env.CACHE.get(cacheKey, 'json');
        if (cached) {
            console.log(`✅ Cache HIT - Subject search: "${query}"`);
            await trackCacheMetric(env, 'subject', 'hit', query);
            return {
                ...cached,
                cached: true,
                cacheAge: Date.now() - (cached.timestamp || startTime)
            };
        }

        console.log(`❌ Cache MISS - Subject search: "${query}". Orchestrating providers.`);
        await trackCacheMetric(env, 'subject', 'miss', query);

        // Step 2: Parallel execution - OpenLibrary subjects + Google Books categories
        console.log(`📚 Parallel: Fetching from OpenLibrary subjects + Google Books categories for "${query}"`);

        // Use raw query without subject: prefix - workers will handle subject filtering internally
        const olPromise = env.OPENLIBRARY_WORKER.search(query, { maxResults: maxResults * 2 });
        const googlePromise = env.GOOGLE_BOOKS_WORKER.search(query, { maxResults: maxResults * 2 });

        const [olResult, googleResult] = await Promise.allSettled([
            olPromise,
            googlePromise
        ]);

        // Step 3: Intelligent result merging with subject validation
        let allItems = [];
        let providers = [];

        // Process OpenLibrary subject results
        if (olResult.status === 'fulfilled' && olResult.value.success) {
            const olData = olResult.value;
            console.log(`✅ OpenLibrary subjects: Found ${olData.works?.length || 0} works`);

            if (olData.works && olData.works.length > 0) {
                const olItems = olData.works.map(work => transformWorkToGoogleFormat(work));
                allItems = [...allItems, ...olItems];
                providers.push('openlibrary-subjects');
                await trackProviderMetric(env, 'openlibrary', 'success', 'subject', Date.now() - startTime);
            }
        } else {
            console.log(`⚠️ OpenLibrary subjects failed for "${query}"`);
            await trackProviderMetric(env, 'openlibrary', 'failure', 'subject', Date.now() - startTime);
        }

        // Process Google Books category results
        if (googleResult.status === 'fulfilled' && googleResult.value.success) {
            const googleData = googleResult.value;
            console.log(`✅ Google Books categories: Found ${googleData.works?.length || 0} works`);

            if (googleData.works && googleData.works.length > 0) {
                const googleItems = googleData.works.map(work => transformWorkToGoogleFormat(work));

                // Merge avoiding duplicates by title
                const existingTitles = new Set(
                    allItems.map(item => item.volumeInfo.title.toLowerCase())
                );

                const newItems = googleItems.filter(item =>
                    !existingTitles.has(item.volumeInfo.title.toLowerCase())
                );

                allItems = [...allItems, ...newItems];
                providers.push('google-books-categories');
                await trackProviderMetric(env, 'google-books', 'success', 'subject', Date.now() - startTime);
            }
        } else {
            console.log(`⚠️ Google Books categories failed for "${query}"`);
            await trackProviderMetric(env, 'google-books', 'failure', 'subject', Date.now() - startTime);
        }

        // Step 4: Deduplicate and filter
        const dedupedItems = deduplicateGoogleBooksItems(allItems);
        const filteredItems = filterGoogleBooksItems(dedupedItems, query);

        // Step 5: Sort by relevance (subjects/categories match)
        const sortedItems = sortBySubjectRelevance(filteredItems, query);

        // Step 6: Apply pagination
        const paginatedItems = paginateResults(sortedItems, page, maxResults);

        if (paginatedItems.length === 0) {
            throw new Error(`No subject results found for "${query}"`);
        }

        const responseData = {
            kind: "books#volumes",
            totalItems: sortedItems.length,
            items: paginatedItems,
            format: "enhanced_work_edition_v1",
            provider: `orchestrated:${providers.join('+')}`,
            searchContext: SEARCH_CONTEXTS.SUBJECT,
            cached: false,
            responseTime: Date.now() - startTime,
            timestamp: Date.now(),
            pagination: {
                page,
                maxResults,
                totalPages: Math.ceil(sortedItems.length / maxResults)
            }
        };

        // Cache for 12 hours
        ctx.waitUntil(
            env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                expirationTtl: CACHE_TTLS.SUBJECT
            })
        );

        return responseData;

    } catch (error) {
        console.error(`❌ Subject search failed for "${query}":`, error);
        await trackProviderMetric(env, 'all', 'error', 'subject', Date.now() - startTime);

        return {
            kind: "books#volumes",
            totalItems: 0,
            items: [],
            error: 'Subject search failed',
            details: error.message,
            searchContext: SEARCH_CONTEXTS.SUBJECT,
            provider: 'none',
            responseTime: Date.now() - startTime
        };
    }
}

/**
 * Helper: Enhance works with edition details from ISBNdb
 * Executes parallel enhancement for performance
 */
async function enhanceWorksWithEditions(works, authorName, env) {
    const enhancementPromises = works.map(async (work) => {
        // Ensure author name is set on the work
        if (!work.authors || work.authors.length === 0) {
            work.authors = [authorName];
        }

        try {
            const isbndbResult = await env.ISBNDB_WORKER.getEditionsForWork(work.title, authorName);
            if (isbndbResult.success && isbndbResult.editions) {
                work.editions = [...(work.editions || []), ...isbndbResult.editions];
            }
        } catch (error) {
            console.warn(`⚠️ ISBNdb enhancement failed for "${work.title}":`, error.message);
            // Continue without enhancement
        }
        return work;
    });

    const results = await Promise.allSettled(enhancementPromises);
    return results
        .filter(result => result.status === 'fulfilled')
        .map(result => result.value);
}

/**
 * Helper: Paginate results
 */
function paginateResults(items, page, maxResults) {
    const start = page * maxResults;
    const end = start + maxResults;
    return items.slice(start, end);
}

/**
 * Helper: Sort by subject relevance
 * Books with matching subjects/categories appear first
 */
function sortBySubjectRelevance(items, query) {
    const queryLower = query.toLowerCase();

    return items.sort((a, b) => {
        const aCategories = (a.volumeInfo.categories || []).map(c => c.toLowerCase());
        const bCategories = (b.volumeInfo.categories || []).map(c => c.toLowerCase());

        const aRelevance = aCategories.some(c => c.includes(queryLower)) ? 1 : 0;
        const bRelevance = bCategories.some(c => c.includes(queryLower)) ? 1 : 0;

        return bRelevance - aRelevance;
    });
}

/**
 * Analytics: Track cache metrics
 */
async function trackCacheMetric(env, context, outcome, query) {
    if (!env.CACHE_ANALYTICS) return;

    try {
        await env.CACHE_ANALYTICS.writeDataPoint({
            blobs: [context, outcome, query.substring(0, 100)],
            doubles: [Date.now()],
            indexes: ['cache-metrics']
        });
    } catch (error) {
        // Silent failure - analytics shouldn't break search
        console.warn('Cache analytics failed:', error.message);
    }
}

/**
 * Advanced Search: Multi-field filtering
 * Handles author + title + ISBN combined searches with proper filtering
 */
export async function handleAdvancedSearch(criteria, options, env, ctx) {
    const { authorName, bookTitle, isbn } = criteria;
    const { maxResults = 20, page = 0 } = options;

    console.log('📋 Advanced Search:', { authorName, bookTitle, isbn, maxResults, page });

    try {
        let results = [];

        // ISBN has highest priority - direct lookup
        if (isbn) {
            console.log('🔍 ISBN search takes priority');
            // Use existing ISBN search logic (would need to add this endpoint)
            // For now, treat as title search with strict filtering
            const response = await env.GOOGLE_BOOKS_WORKER.search(isbn, { maxResults });
            if (response.success && response.items) {
                results = response.items;
            }
        }
        // Author + Title combination - strictest filtering
        else if (authorName && bookTitle) {
            console.log('🔍 Author + Title combined search');

            // Search by author first (more specific)
            const authorResults = await handleAuthorSearch(authorName, { maxResults: maxResults * 2, page }, env, ctx);

            // Filter results to match title
            const titleLower = bookTitle.toLowerCase();
            results = (authorResults.items || []).filter(item => {
                const itemTitle = (item.volumeInfo?.title || '').toLowerCase();
                return itemTitle.includes(titleLower);
            });

            console.log(`📊 Filtered ${authorResults.items?.length || 0} → ${results.length} results matching both criteria`);
        }
        // Single field searches - use existing specialized endpoints
        else if (authorName) {
            console.log('🔍 Author-only search');
            const authorResults = await handleAuthorSearch(authorName, { maxResults, page }, env, ctx);
            results = authorResults.items || [];
        }
        else if (bookTitle) {
            console.log('🔍 Title-only search');
            const titleResults = await handleTitleSearch(bookTitle, { maxResults, page }, env, ctx);
            results = titleResults.items || [];
        }

        // Apply pagination if needed
        const startIndex = page * maxResults;
        const paginatedResults = results.slice(startIndex, startIndex + maxResults);

        return {
            kind: 'books#volumes',
            totalItems: results.length,
            items: paginatedResults,
            provider: 'advanced-search',
            cached: false
        };

    } catch (error) {
        console.error('❌ Advanced search failed:', error);
        return {
            kind: 'books#volumes',
            totalItems: 0,
            items: [],
            error: error.message
        };
    }
}

/**
 * ISBN Search Handler
 *
 * Strategy: ISBNdb-first for direct ISBN lookup (most accurate source)
 * Rationale: ISBNdb specializes in ISBN-based lookups with comprehensive edition data
 * Fallback: Google Books if ISBNdb fails or has no data
 * Cache: 7 days (ISBNs are immutable identifiers)
 *
 * @param {string} query - ISBN-10 or ISBN-13 (with or without hyphens)
 * @param {object} params - { maxResults, page }
 * @param {object} env - Worker environment bindings
 * @param {object} ctx - Execution context
 * @returns {Promise<object>} - ISBN lookup result with edition details
 */
export async function handleISBNSearch(query, params, env, ctx) {
    const startTime = Date.now();
    const cleanISBN = query.replace(/[-\s]/g, ''); // Remove hyphens and spaces

    const cacheKey = `search:isbn:${cleanISBN}`;

    try {
        // Step 1: Check cache (7-day TTL for ISBNs)
        const cached = await env.CACHE.get(cacheKey, 'json');
        if (cached) {
            console.log(`✅ Cache HIT - ISBN search: "${cleanISBN}"`);
            await trackCacheMetric(env, 'isbn', 'hit', cleanISBN);
            return {
                ...cached,
                cached: true,
                cacheAge: Date.now() - (cached.timestamp || startTime)
            };
        }

        console.log(`❌ Cache MISS - ISBN search: "${cleanISBN}". Querying ISBNdb worker.`);
        await trackCacheMetric(env, 'isbn', 'miss', cleanISBN);

        // Step 2: Primary strategy - ISBNdb direct lookup
        console.log(`📘 Primary: ISBNdb lookup for ISBN "${cleanISBN}"`);
        const isbndbResult = await env.ISBNDB_WORKER.getBookByISBN(cleanISBN);

        if (isbndbResult.success && isbndbResult.book) {
            console.log(`✅ ISBNdb: Found book for ISBN "${cleanISBN}"`);
            await trackProviderMetric(env, 'isbndb', 'success', 'isbn', Date.now() - startTime);

            // Transform ISBNdb result to Google Books format
            const work = isbndbResult.book;
            const responseData = {
                kind: "books#volumes",
                totalItems: 1,
                items: [transformWorkToGoogleFormat(work)],
                format: "enhanced_work_edition_v1",
                provider: "isbndb",
                searchContext: SEARCH_CONTEXTS.ISBN,
                cached: false,
                responseTime: Date.now() - startTime,
                timestamp: Date.now()
            };

            // Cache for 7 days (ISBNs are immutable)
            ctx.waitUntil(
                env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                    expirationTtl: CACHE_TTLS.ISBN
                })
            );

            return responseData;
        }

        console.log(`⚠️ ISBNdb: No data for ISBN "${cleanISBN}". Trying Google Books fallback.`);
        await trackProviderMetric(env, 'isbndb', 'no-data', 'isbn', Date.now() - startTime);

        // Step 3: Fallback - Google Books
        console.log(`📗 Fallback: Google Books lookup for ISBN "${cleanISBN}"`);
        const googleResult = await env.GOOGLE_BOOKS_WORKER.search(cleanISBN, { maxResults: 1 });

        if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
            console.log(`✅ Google Books: Found book for ISBN "${cleanISBN}"`);
            await trackProviderMetric(env, 'google-books', 'success', 'isbn', Date.now() - startTime);

            const googleItems = googleResult.works.map(work => transformWorkToGoogleFormat(work));
            const responseData = {
                kind: "books#volumes",
                totalItems: googleItems.length,
                items: googleItems,
                format: "enhanced_work_edition_v1",
                provider: "google-books",
                searchContext: SEARCH_CONTEXTS.ISBN,
                cached: false,
                responseTime: Date.now() - startTime,
                timestamp: Date.now()
            };

            // Cache for 7 days
            ctx.waitUntil(
                env.CACHE.put(cacheKey, JSON.stringify(responseData), {
                    expirationTtl: CACHE_TTLS.ISBN
                })
            );

            return responseData;
        }

        console.log(`❌ Both providers failed for ISBN "${cleanISBN}"`);
        await trackProviderMetric(env, 'google-books', 'failure', 'isbn', Date.now() - startTime);

        // No results from any provider
        return {
            kind: "books#volumes",
            totalItems: 0,
            items: [],
            error: 'ISBN not found in any provider',
            searchContext: SEARCH_CONTEXTS.ISBN,
            provider: 'none',
            responseTime: Date.now() - startTime
        };

    } catch (error) {
        console.error(`❌ ISBN search failed for "${cleanISBN}":`, error);
        await trackProviderMetric(env, 'all', 'error', 'isbn', Date.now() - startTime);

        return {
            kind: "books#volumes",
            totalItems: 0,
            items: [],
            error: 'ISBN search failed',
            details: error.message,
            searchContext: SEARCH_CONTEXTS.ISBN,
            provider: 'error',
            responseTime: Date.now() - startTime
        };
    }
}

/**
 * Analytics: Track provider performance
 */
async function trackProviderMetric(env, provider, outcome, context, duration) {
    if (!env.PROVIDER_ANALYTICS) return;

    try {
        await env.PROVIDER_ANALYTICS.writeDataPoint({
            blobs: [provider, outcome, context],
            doubles: [duration, Date.now()],
            indexes: ['provider-performance']
        });
    } catch (error) {
        // Silent failure - analytics shouldn't break search
        console.warn('Provider analytics failed:', error.message);
    }
}
