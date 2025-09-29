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
        // Detect if this is an author search vs book/title search
        const isAuthorSearch = false; // Temporarily disabled for debugging
        // const isAuthorSearch = isLikelyAuthorQuery(query);

        if (isAuthorSearch) {
            console.log(`Detected author search for: ${query}. Using OpenLibrary-first workflow.`);

            // For author searches: OpenLibrary first to get canonical works list
            const olResult = await env.OPENLIBRARY_WORKER.getAuthorWorks(query);
            if (!olResult.success) {
                throw new Error(`OpenLibrary author search failed: ${olResult.error}`);
            }

            let { works, author } = olResult;
            console.log(`Retrieved ${works.length} works from OpenLibrary for ${query}`);

            // Enhance top works with additional provider data if needed
            const topWorks = works.slice(0, maxResults);
            const enhancementPromises = topWorks.map(async (work) => {
                // Try to get additional edition data from ISBNdb
                const isbndbResult = await env.ISBNDB_WORKER.getEditionsForWork(work.title, author.name);
                if (isbndbResult.success && isbndbResult.editions) {
                    work.editions = [...(work.editions || []), ...isbndbResult.editions];
                }
                return work;
            });

            const enhancedWorks = await Promise.allSettled(enhancementPromises);
            const finalWorks = enhancedWorks
                .filter(result => result.status === 'fulfilled')
                .map(result => result.value);

            // Transform to Google Books format for iOS compatibility
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

        // For general book/title searches: Use parallel provider approach
        console.log(`General book search for: ${query}. Using parallel provider workflow.`);
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
            // Filter out collections, study guides, and special editions
            const filteredWorks = filterPrimaryWorks(googleData.works);
            aggregatedWorks = [...aggregatedWorks, ...filteredWorks];
            successfulProviders.push('google');
            if (!primaryProvider || primaryProvider === 'multi-provider') {
                primaryProvider = 'google';
            }
        }

        // Process OpenLibrary results
        if (results[1].status === 'fulfilled' && results[1].value.success) {
            const olData = results[1].value;
            // Filter and merge works, avoiding duplicates by title
            const filteredOLWorks = filterPrimaryWorks(olData.works);
            const existingTitles = new Set(aggregatedWorks.map(w => w.title.toLowerCase()));
            const newWorks = filteredOLWorks.filter(w => !existingTitles.has(w.title.toLowerCase()));
            aggregatedWorks = [...aggregatedWorks, ...newWorks];
            successfulProviders.push('openlibrary');
        }

        if (aggregatedWorks.length === 0) {
            throw new Error('No results from any provider');
        }

        // Advanced deduplication by author + title similarity
        const dedupedWorks = advancedDeduplication(aggregatedWorks);

        // But wait - if we're getting results directly from Google Books API format,
        // we need to handle the data differently based on the provider response format
        let finalItems = [];

        // Process each provider's results based on their format
        if (results[0].status === 'fulfilled' && results[0].value.success) {
            const googleData = results[0].value;
            if (googleData.items) {
                // This is Google Books API format - filter and transform directly
                const filteredItems = filterGoogleBooksItems(googleData.items, query);
                finalItems = [...finalItems, ...filteredItems];
            } else if (googleData.works) {
                // This is normalized Work format - transform to Google Books format
                const transformedItems = googleData.works.map(work => transformWorkToGoogleFormat(work));
                finalItems = [...finalItems, ...transformedItems];
            }
        }

        if (results[1].status === 'fulfilled' && results[1].value.success) {
            const olData = results[1].value;
            if (olData.works) {
                const transformedItems = olData.works.map(work => transformWorkToGoogleFormat(work));
                finalItems = [...finalItems, ...transformedItems];
            }
        }

        // Deduplicate at the Google Books format level
        const dedupedItems = deduplicateGoogleBooksItems(finalItems);

        // Apply final filtering to remove collections and unwanted items
        const finalFilteredItems = filterGoogleBooksItems(dedupedItems, query);

        // Transform to Google Books API compatible format for iOS app
        const responseData = {
            kind: "books#volumes",
            totalItems: finalFilteredItems.length,
            items: finalFilteredItems,
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

    // Handle different author formats from different providers
    let authors = [];
    if (work.authors) {
        if (Array.isArray(work.authors)) {
            authors = work.authors.map(a => {
                if (typeof a === 'string') return a;
                if (a && a.name) return a.name;
                return String(a);
            });
        } else if (typeof work.authors === 'string') {
            authors = [work.authors];
        }
    }

    // If no authors in work, try to get from edition or use a fallback
    if (authors.length === 0 && primaryEdition?.authors) {
        authors = Array.isArray(primaryEdition.authors)
            ? primaryEdition.authors.map(a => typeof a === 'string' ? a : a.name || String(a))
            : [String(primaryEdition.authors)];
    }

    // Collect external IDs from both work and edition level
    const workExternalIds = work.externalIds || {};
    const editionExternalIds = primaryEdition?.externalIds || {};

    // Prepare industry identifiers including ISBNs and enhanced external IDs
    const industryIdentifiers = [];

    // Add ISBNs
    if (primaryEdition?.isbn13) {
        industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn13 });
    }
    if (primaryEdition?.isbn10) {
        industryIdentifiers.push({ type: "ISBN_10", identifier: primaryEdition.isbn10 });
    }
    // Fallback for legacy isbn field
    if (primaryEdition?.isbn && !primaryEdition?.isbn13 && !primaryEdition?.isbn10) {
        industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn });
    }

    // Enhanced Google Books format with cross-reference IDs
    const volumeInfo = {
        title: work.title,
        subtitle: work.subtitle || "",
        authors: authors,
        publisher: primaryEdition?.publisher || "",
        publishedDate: work.firstPublicationYear ? work.firstPublicationYear.toString() : (primaryEdition?.publicationDate || primaryEdition?.publishedDate || ""),
        description: work.description || primaryEdition?.description || "",
        industryIdentifiers: industryIdentifiers,
        pageCount: primaryEdition?.pageCount || 0,
        categories: work.subjects || work.categories || [],
        imageLinks: primaryEdition?.coverImageURL ? {
            thumbnail: primaryEdition.coverImageURL,
            smallThumbnail: primaryEdition.coverImageURL
        } : undefined,

        // Enhanced cross-reference identifiers for future provider integration
        crossReferenceIds: {
            // OpenLibrary IDs
            openLibraryWorkId: workExternalIds.openLibraryWorkId || work.openLibraryWorkKey,
            openLibraryEditionId: editionExternalIds.openLibraryEditionId || workExternalIds.openLibraryEditionId,

            // Commercial platform IDs
            goodreadsWorkIds: [...(workExternalIds.goodreadsWorkIds || []), ...(editionExternalIds.goodreadsWorkIds || [])],
            amazonASINs: [...(workExternalIds.amazonASINs || []), ...(editionExternalIds.amazonASINs || [])],
            googleBooksVolumeIds: [...(workExternalIds.googleBooksVolumeIds || []), ...(editionExternalIds.googleBooksVolumeIds || [])],

            // Future provider IDs
            librarythingIds: [...(workExternalIds.librarythingIds || []), ...(editionExternalIds.librarythingIds || [])],
            isbndbIds: [...(workExternalIds.isbndbIds || []), ...(editionExternalIds.isbndbIds || [])]
        }
    };

    // Determine best ID for the volume
    const volumeId = work.id ||
                    workExternalIds.googleBooksVolumeIds?.[0] ||
                    workExternalIds.openLibraryWorkId ||
                    work.openLibraryWorkKey ||
                    work.googleBooksVolumeID ||
                    `synthetic-${work.title.replace(/\s+/g, '-').toLowerCase()}`;

    return {
        kind: "books#volume",
        id: volumeId,
        volumeInfo: volumeInfo
    };
}

/**
 * Filter out collections, study guides, conversation starters, and special editions
 * to focus on primary works by the author
 */
function filterPrimaryWorks(works) {
    if (!works || !Array.isArray(works)) return [];

    const excludePatterns = [
        // Collections and box sets - more aggressive
        /collection/i,
        /set\b/i,
        /series\b/i,
        /boxed/i,
        /box set/i,
        /\d+-book/i,
        /bundle/i,
        /\bbinge\b/i,                    // "Binge Reads"
        /compilation/i,
        /omnibus/i,

        // Study materials - enhanced
        /study guide/i,
        /conversation starter/i,
        /conversation starters/i,        // Plural form
        /summary/i,
        /analysis/i,
        /cliff.*notes/i,
        /sparknotes/i,
        /discussion/i,
        /questions/i,
        /study.*notes/i,

        // Special editions and formats (but not primary graphic novels)
        /annotated/i,
        /illustrated/i,
        /companion/i,
        /workbook/i,
        /journal/i,
        /diary/i,

        // Exclude graphic novels only if they're supplementary (not primary works)
        /graphic novel.*guide/i,
        /graphic novel.*companion/i,

        // Meta books about the author/work
        /about\s+\w+/i,
        /guide to/i,
        /understanding/i,
        /introduction to/i,

        // Publisher-specific exclusions for study materials
        /by.*daily.*books/i,
        /\|.*conversation/i,            // "Title | Conversation Starters"
        /\|.*summary/i,                 // "Title | Summary"
        /\|.*study/i,                   // "Title | Study Guide"
    ];

    const includeIfContains = [
        // These patterns indicate it's likely a primary work
        /novel/i,
        /book/i,
        /story/i,
        /tales/i,
    ];

    return works.filter(work => {
        const title = work.title || '';
        const subtitle = work.subtitle || '';
        const fullTitle = `${title} ${subtitle}`.toLowerCase();

        // Exclude if matches any exclude pattern
        for (const pattern of excludePatterns) {
            if (pattern.test(fullTitle)) {
                return false;
            }
        }

        // If it's a very short title (likely primary work), include it
        if (title.length <= 50) {
            return true;
        }

        // For longer titles, check if they contain positive indicators
        return includeIfContains.some(pattern => pattern.test(fullTitle));
    });
}

/**
 * Advanced deduplication that considers author + title similarity
 */
function advancedDeduplication(works) {
    if (!works || works.length <= 1) return works;

    const dedupedWorks = [];
    const seenKeys = new Set();

    for (const work of works) {
        // Create a normalized key for comparison
        const title = (work.title || '').toLowerCase()
            .replace(/[^\w\s]/g, '') // Remove punctuation
            .replace(/\s+/g, ' ')     // Normalize whitespace
            .trim();

        const authors = Array.isArray(work.authors)
            ? work.authors.map(a => (typeof a === 'string' ? a : a.name || '').toLowerCase()).join(',')
            : '';

        const normalizedKey = `${authors}:${title}`;

        // Check for near-duplicates (90% similarity)
        let isDuplicate = false;
        for (const existingKey of seenKeys) {
            if (calculateSimilarity(normalizedKey, existingKey) > 0.9) {
                isDuplicate = true;
                break;
            }
        }

        if (!isDuplicate) {
            seenKeys.add(normalizedKey);
            dedupedWorks.push(work);
        }
    }

    return dedupedWorks;
}

/**
 * Calculate string similarity using Jaccard coefficient
 */
function calculateSimilarity(str1, str2) {
    const set1 = new Set(str1.toLowerCase().split(/\s+/));
    const set2 = new Set(str2.toLowerCase().split(/\s+/));

    const intersection = new Set([...set1].filter(x => set2.has(x)));
    const union = new Set([...set1, ...set2]);

    return intersection.size / union.size;
}

/**
 * Filter Google Books API items to remove collections and non-primary works
 */
function filterGoogleBooksItems(items, searchQuery = '') {
    if (!items || !Array.isArray(items)) return [];

    // Extract potential author name from search query for validation
    const queryLower = searchQuery.toLowerCase();
    const isAuthorSearch = queryLower.includes(' ') && !queryLower.includes('the ') && !queryLower.includes('a ');
    const potentialAuthor = isAuthorSearch ? queryLower : null;

    const excludePatterns = [
        // Collections and box sets - more aggressive
        /collection/i,
        /set\b/i,
        /boxed/i,
        /box set/i,
        /\d+-book/i,
        /bundle/i,
        /\bbinge\b/i,                    // "Binge Reads"
        /compilation/i,
        /omnibus/i,

        // Study materials and guides - enhanced
        /study guide/i,
        /conversation starter/i,
        /conversation starters/i,        // Plural form
        /summary/i,
        /analysis/i,
        /cliff.*notes/i,
        /sparknotes/i,
        /discussion/i,
        /questions/i,
        /workbook/i,
        /study.*notes/i,

        // Meta books about the author/work
        /about\s+\w+/i,
        /guide to/i,
        /understanding/i,
        /introduction to/i,
        /companion/i,

        // Publisher-specific exclusions for study materials
        /by.*daily.*books/i,
        /\|.*conversation/i,            // "Title | Conversation Starters"
        /\|.*summary/i,                 // "Title | Summary"
        /\|.*study/i,                   // "Title | Study Guide"
    ];

    return items.filter(item => {
        const volumeInfo = item.volumeInfo || {};
        const title = volumeInfo.title || '';
        const subtitle = volumeInfo.subtitle || '';
        const fullTitle = `${title} ${subtitle}`.toLowerCase();

        // Exclude if matches any exclude pattern
        for (const pattern of excludePatterns) {
            if (pattern.test(fullTitle)) {
                return false;
            }
        }

        // Prefer books with actual content (page count > 10)
        const pageCount = volumeInfo.pageCount || 0;
        if (pageCount > 0 && pageCount < 10) {
            return false;
        }

        // Author validation for author searches
        if (potentialAuthor && volumeInfo.authors) {
            const authors = volumeInfo.authors || [];
            const authorsText = authors.join(' ').toLowerCase();

            // Check if any of the search terms appear in the author names
            const searchTerms = potentialAuthor.split(' ').filter(term => term.length > 2);
            const hasMatchingAuthor = searchTerms.some(term => authorsText.includes(term));

            // If this appears to be an author search but no author matches, filter out
            // Exception: keep obvious study materials that might be legitimately about the author
            if (!hasMatchingAuthor && !fullTitle.includes('about') && !fullTitle.includes('guide')) {
                return false;
            }
        }

        return true;
    });
}

/**
 * Deduplicate Google Books items by title and author
 */
function deduplicateGoogleBooksItems(items) {
    if (!items || items.length <= 1) return items;

    const dedupedItems = [];
    const seenKeys = new Set();

    for (const item of items) {
        const volumeInfo = item.volumeInfo || {};
        const title = (volumeInfo.title || '').toLowerCase()
            .replace(/[^\w\s]/g, '') // Remove punctuation
            .replace(/\s+/g, ' ')     // Normalize whitespace
            .trim();

        const authors = (volumeInfo.authors || [])
            .map(a => a.toLowerCase())
            .join(',');

        const normalizedKey = `${authors}:${title}`;

        // Check for near-duplicates (85% similarity for Google Books items)
        let isDuplicate = false;
        for (const existingKey of seenKeys) {
            if (calculateSimilarity(normalizedKey, existingKey) > 0.85) {
                isDuplicate = true;
                break;
            }
        }

        if (!isDuplicate) {
            seenKeys.add(normalizedKey);
            dedupedItems.push(item);
        }
    }

    return dedupedItems;
}

/**
 * Detect if a search query is likely an author search vs a book title search
 */
function isLikelyAuthorQuery(query) {
    const cleanQuery = query.toLowerCase().trim();

    // Strong indicators of author search
    const authorIndicators = [
        // Common author name patterns (First Last, Last First)
        /^[a-z]+\s+[a-z]+$/,                    // "andy weir", "stephen king"
        /^[a-z]+\s+[a-z]\.\s+[a-z]+$/,         // "j. k. rowling", "ray bradbury"
        /^[a-z]+,\s+[a-z]+$/,                  // "king, stephen"
        /^[a-z]+\s+[a-z]+\s+[a-z]+$/,         // "ursula k leguin"
    ];

    // Strong indicators this is NOT an author search (likely book title)
    const titleIndicators = [
        /^the\s+/,              // "the martian", "the great gatsby"
        /^a\s+/,                // "a song of ice and fire"
        /^an\s+/,               // "an american tragedy"
        /\d/,                   // Any numbers likely indicate titles
        /:/,                    // Colons often in book titles
        /series$/,              // "harry potter series"
        /book$/,                // "the jungle book"
        /novel$/,               // "dune novel"
    ];

    // Check for title indicators first (these override author patterns)
    for (const pattern of titleIndicators) {
        if (pattern.test(cleanQuery)) {
            return false;
        }
    }

    // Check for author indicators
    for (const pattern of authorIndicators) {
        if (pattern.test(cleanQuery)) {
            return true;
        }
    }

    // Fallback: if it's 2 words with no special characters, probably an author
    const words = cleanQuery.split(/\s+/);
    if (words.length === 2 && words.every(word => /^[a-z]+$/.test(word))) {
        return true;
    }

    // Default to title search
    return false;
}

