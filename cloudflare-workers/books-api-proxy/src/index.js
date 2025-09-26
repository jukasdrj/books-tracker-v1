/**
 * Books API Proxy - CloudFlare Worker
 *
 * Multi-provider book search API with intelligent fallbacks:
 * 1. Google Books API (primary) - comprehensive data
 * 2. ISBNdb API (via service binding) - superior author bibliographies
 * 3. Open Library API (fallback) - free, extensive catalog
 *
 * Features:
 * - Rate limiting per IP
 * - Hybrid R2 + KV caching (hot/cold cache tiers)
 * - Intelligent query classification and provider selection
 * - CORS support for web/mobile applications
 */

// ============================================================================
// Main Fetch Handler & Router
// ============================================================================

export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return handleCORS();
    }

    try {
      const url = new URL(request.url);
      const path = url.pathname;

      // Primary API Routes
      if (path === '/search/auto') {
        return await handleAutoSearch(request, env, ctx);
      }
      if (path.startsWith('/author/enhanced/')) {
        return await handleEnhancedAuthorBibliography(request, env, ctx);
      }
      if (path.startsWith('/completeness/')) {
        return await handleCompletenessCheck(request, env, ctx);
      }
      if (path.startsWith('/author/')) {
        return await handleAuthorBibliography(request, env, ctx);
      }
      if (path === '/health') {
        return new Response(JSON.stringify({
          status: 'healthy',
          timestamp: new Date().toISOString(),
          providers: ['google-books', 'isbndb-worker', 'openlibrary-worker'],
          enhancedMode: {
            available: !!env.OPENLIBRARY_WORKER,
            endpoint: '/author/enhanced/{name}',
            description: 'OpenLibrary → ISBNdb enhancement pipeline'
          },
          completenessGraph: {
            available: !!env.CACHE,
            endpoint: '/completeness/{name}',
            description: 'Bibliography completeness metadata and quality scoring'
          },
          cache: {
            system: env.API_CACHE_COLD ? 'R2+KV-Hybrid' : 'KV-Only',
            kv: env.CACHE ? 'available' : 'missing',
            r2: env.API_CACHE_COLD ? 'available' : 'missing'
          },
          serviceBindings: {
            isbndb: !!env.ISBNDB_WORKER,
            openlibrary: !!env.OPENLIBRARY_WORKER
          }
        }), {
          headers: getCORSHeaders('application/json')
        });
      }

      // Fallback for other potential routes if needed in the future
      return new Response(JSON.stringify({ error: 'Endpoint not found' }), {
        status: 404,
        headers: getCORSHeaders('application/json')
      });

    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({
        error: 'Internal server error',
        message: error.message
      }), {
        status: 500,
        headers: getCORSHeaders('application/json')
      });
    }
  }
};


// ============================================================================
// Core Search & Routing Logic
// ============================================================================

/**
 * Intelligent Auto-Search Handler
 * Classifies query and routes to the optimal provider. This is the main entry point.
 */
async function handleAutoSearch(request, env, ctx) {
    const url = new URL(request.url);
    const { query, maxResults, sortBy, includeTranslations, langRestrict, showAllEditions } = validateSearchParams(url).sanitized;

    const queryAnalysis = classifyQuery(query);
    const searchType = queryAnalysis.type;

    const cacheKey = createCacheKey('auto-search', query, { maxResults, sortBy, searchType, showAllEditions });

    const forceRefresh = url.searchParams.get('force') === 'true';
    if (!forceRefresh) {
        const cached = await getCachedData(cacheKey, env, ctx);
        if (cached) {
            return new Response(JSON.stringify({
                ...cached.data,
                cached: true,
                cacheSource: cached.source,
                hitCount: cached.hitCount || 0
            }), {
                headers: {
                    ...getCORSHeaders(),
                    'X-Cache': `HIT-${cached.source}`,
                    'X-Cache-Hits': (cached.hitCount || 0).toString()
                }
            });
        }
    }

    const providers = selectOptimalProviders(searchType, query);
    let result = null;
    let usedProvider = 'none';

    for (const providerConfig of providers) {
        try {
            console.log(`Attempting provider: ${providerConfig.name} for search type: ${searchType}`);
            switch (providerConfig.name) {
                case 'isbndb':
                    result = await searchISBNdbWithWorker(query, maxResults, searchType, env);
                    break;
                case 'google-books':
                    result = await searchGoogleBooks(query, maxResults, sortBy, includeTranslations, env);
                    break;
                case 'open-library':
                    result = await searchOpenLibrary(query, maxResults, env);
                    break;
            }
            if (result && result.items?.length > 0) {
                usedProvider = providerConfig.name;
                break;
            }
        } catch (error) {
            console.error(`${providerConfig.name} provider failed:`, error.message);
        }
    }

    if (!result || result.items?.length === 0) {
        return new Response(JSON.stringify({ error: 'No results found from any provider', items: [] }), {
            status: 404, headers: getCORSHeaders()
        });
    }

    result.provider = usedProvider;
    result.cached = false;
    result.queryAnalysis = queryAnalysis;

    // Add API identifiers for SwiftData model synchronization
    if (usedProvider === 'google-books' && result.items) {
        result.items = result.items.map(item => ({
            ...item,
            volumeInfo: {
                ...item.volumeInfo,
                googleBooksVolumeID: item.id || null
            }
        }));
    }

    // INTELLIGENT CACHING: ISBNdb results get high priority due to API cost
    const priority = usedProvider === 'isbndb' ? 'high' : 'normal';
    const cacheTtl = usedProvider === 'isbndb' ? 86400 * 7 : 86400; // 7 days for ISBNdb, 1 day for others
    setCachedData(cacheKey, result, cacheTtl, env, ctx, priority);

    return new Response(JSON.stringify(result), {
        headers: { ...getCORSHeaders(), 'X-Cache': 'MISS', 'X-Provider': usedProvider }
    });
}

/**
 * Handles direct calls to /author/{authorName} by routing to the ISBNdb worker.
 */
async function handleAuthorBibliography(request, env, ctx) {
  try {
    const url = new URL(request.url);
    const path = url.pathname;
    const pathParts = path.split('/');
    if (pathParts.length < 3 || !pathParts[2]) {
      return new Response(JSON.stringify({ error: 'Author name is required' }), {
        status: 400,
        headers: getCORSHeaders()
      });
    }
    const authorName = decodeURIComponent(pathParts[2]);

    // ✅ CRITICAL FIX: Use the full, absolute URL when calling the service binding
    const workerUrl = `https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/${encodeURIComponent(authorName)}?${url.searchParams}`;
    
    const workerRequest = new Request(workerUrl, {
        method: request.method,
        headers: request.headers,
    });

    const response = await env.ISBNDB_WORKER.fetch(workerRequest);
    if (!response.ok) {
        throw new Error(`ISBNdb worker returned status ${response.status}`);
    }
    const result = await response.json();

    // Add metadata for debugging
    result.source = 'isbndb-worker';
    result.cached_via = 'service-binding';

    return new Response(JSON.stringify(result), {
      status: response.status,
      headers: getCORSHeaders(),
    });

  } catch (error) {
    console.error('Author bibliography error:', error);
    return new Response(JSON.stringify({ error: 'Author bibliography failed', message: error.message }), {
      status: 500,
      headers: getCORSHeaders(),
    });
  }
}

// ============================================================================
// API Provider Functions
// ============================================================================

/**
 * Search ISBNdb by calling the dedicated worker via service binding.
 */
async function searchISBNdbWithWorker(query, maxResults, searchType, env) {
    let endpoint = '';
    if (searchType === 'author') {
        endpoint = `author/${encodeURIComponent(query)}?pageSize=${maxResults}`;
    } else if (searchType === 'isbn') {
        endpoint = `book/${encodeURIComponent(query)}`;
    } else { // title or mixed
        endpoint = `search/books?text=${encodeURIComponent(query)}&pageSize=${maxResults}`;
    }
    
    // ✅ CRITICAL FIX: Use the full, absolute URL when calling the service binding
    const workerUrl = `https://isbndb-biography-worker-production.jukasdrj.workers.dev/${endpoint}`;

    const workerRequest = new Request(workerUrl);
    const response = await env.ISBNDB_WORKER.fetch(workerRequest);

    if (!response.ok) {
        throw new Error(`ISBNdb worker returned status ${response.status}`);
    }

    const data = await response.json();
    return transformISBNdbToStandardFormat(data, 'isbndb-worker');
}

async function searchGoogleBooks(query, maxResults, sortBy, includeTranslations, env) {
    const apiKey = await env.GOOGLE_BOOKS_API_KEY.get();
    if (!apiKey) throw new Error('Google Books API key not configured');

    const params = new URLSearchParams({
        q: query,
        maxResults: maxResults.toString(),
        printType: 'books',
        orderBy: sortBy,
        key: apiKey
    });
    if (!includeTranslations) {
        params.append('langRestrict', 'en');
    }

    const response = await fetch(`https://www.googleapis.com/books/v1/volumes?${params}`);
    if (!response.ok) {
        throw new Error(`Google Books API error: ${response.status}`);
    }
    return await response.json();
}

async function searchOpenLibrary(query, maxResults, env) {
    const params = new URLSearchParams({ q: query, limit: maxResults.toString() });
    const response = await fetch(`https://openlibrary.org/search.json?${params}`);
    if (!response.ok) {
        throw new Error(`Open Library API error: ${response.status}`);
    }
    const data = await response.json();
    return transformOpenLibraryToStandardFormat(data);
}


// ============================================================================
// Data Transformation & Helpers
// ============================================================================

function transformISBNdbToStandardFormat(isbndbData, provider) {
    // Only handle enhanced Work/Edition format
    if (isbndbData.format === 'enhanced_work_edition_v1' && isbndbData.works) {
        return transformWorksToStandardFormat(isbndbData, provider);
    }

    // No results for non-normalized format
    return { kind: "books#volumes", totalItems: 0, items: [] };
}

/**
 * Apply intelligent book quality filters to remove duplicates, sets, and unwanted editions
 */
function applyBookQualityFilters(books) {
    // Step 1: Filter out obvious junk
    let filtered = books.filter(book => {
        const title = book.title?.toLowerCase() || '';
        const publisher = book.publisher?.toLowerCase() || '';

        // ❌ Filter out: Collections, sets, bundles
        if (title.match(/\b(collection|set|bundle|box.*set|books.*set)\b/i)) {
            return false;
        }

        // ❌ Filter out: SIGNED/AUTOGRAPHED editions (prefer standard)
        if (title.match(/\b(signed|autographed|limited.*edition|special.*edition)\b/i)) {
            return false;
        }

        // ❌ Filter out: Audio-only editions when we want books
        if (publisher.match(/\b(audio|brilliance.*audio|audible)\b/i) &&
            !title.match(/\b(ebook|kindle|digital)\b/i)) {
            return false;
        }

        // ❌ Filter out: Extremely long promotional titles
        if (title.length > 100) {
            return false;
        }

        return true;
    });

    // Step 2: Remove duplicates, keeping the best edition of each title
    const titleMap = new Map();

    filtered.forEach(book => {
        const normalizedTitle = normalizeTitle(book.title);
        const existing = titleMap.get(normalizedTitle);

        if (!existing || isPreferredEdition(book, existing)) {
            titleMap.set(normalizedTitle, book);
        }
    });

    // Step 3: Sort by publication date (newest first) and relevance
    return Array.from(titleMap.values()).sort((a, b) => {
        const dateA = new Date(a.date_published || '1900');
        const dateB = new Date(b.date_published || '1900');
        return dateB - dateA;
    });
}

/**
 * Normalize book titles for duplicate detection
 */
function normalizeTitle(title) {
    if (!title) return '';
    return title
        .toLowerCase()
        .replace(/[:\-\(\)\[\]]/g, '')  // Remove punctuation
        .replace(/\b(the|a|an)\s+/g, '') // Remove articles
        .replace(/\s+/g, ' ')            // Normalize whitespace
        .trim();
}

/**
 * Determine if book A is preferred over book B for the same title
 */
function isPreferredEdition(bookA, bookB) {
    const titleA = bookA.title?.toLowerCase() || '';
    const titleB = bookB.title?.toLowerCase() || '';
    const pubA = bookA.publisher?.toLowerCase() || '';
    const pubB = bookB.publisher?.toLowerCase() || '';

    // Prefer books with cleaner, shorter titles
    if (Math.abs(titleA.length - titleB.length) > 20) {
        return titleA.length < titleB.length;
    }

    // Prefer major publishers
    const majorPublishers = ['random house', 'crown', 'del rey', 'penguin', 'harpercollins'];
    const isAMajor = majorPublishers.some(pub => pubA.includes(pub));
    const isBMajor = majorPublishers.some(pub => pubB.includes(pub));

    if (isAMajor && !isBMajor) return true;
    if (!isAMajor && isBMajor) return false;

    // Prefer newer editions
    const dateA = new Date(bookA.date_published || '1900');
    const dateB = new Date(bookB.date_published || '1900');

    return dateA > dateB;
}


function transformOpenLibraryToStandardFormat(data) {
    return {
        kind: 'books#volumes',
        totalItems: data.numFound,
        items: data.docs.map(doc => ({
            kind: 'books#volume',
            id: doc.key?.replace('/works/', ''),
            volumeInfo: {
                title: doc.title,
                authors: doc.author_name,
                publishedDate: doc.first_publish_year?.toString(),
                publisher: doc.publisher?.[0],
                industryIdentifiers: doc.isbn?.map(isbn => ({
                    type: isbn.length === 13 ? 'ISBN_13' : 'ISBN_10',
                    identifier: isbn
                })),
                pageCount: doc.number_of_pages_median,
                categories: doc.subject?.slice(0, 3),
                imageLinks: doc.cover_i ? {
                    thumbnail: `https://covers.openlibrary.org/b/id/${doc.cover_i}-M.jpg`
                } : undefined,
                // API identifiers for SwiftData model synchronization
                openLibraryID: doc.key || null
            }
        }))
    };
}


// ============================================================================
// Caching, Validation, and Utility Functions
// ============================================================================

function createCacheKey(type, query, params = {}) {
    const normalizedQuery = query.toLowerCase().trim().replace(/\s+/g, ' ');
    const sortedParams = Object.keys(params).sort().map(key => `${key}=${params[key]}`).join('&');
    const hashInput = `${type}:${normalizedQuery}:${sortedParams}`;
    // Using a simple btoa for hashing; for production, a more robust hash might be better
    return `${type}:${btoa(hashInput).replace(/[/+=]/g, '')}`;
}

/**
 * INTELLIGENT CACHE RETRIEVAL with automatic promotion and hit tracking
 * Implements hot/cold tier architecture with usage-based promotion
 */
async function getCachedData(cacheKey, env, ctx) {
    const kvData = await env.CACHE?.get(cacheKey, 'json');
    if (kvData) {
        // Track cache hit for analytics
        await trackCacheHit(cacheKey, 'KV-HOT', env, ctx);
        return { data: kvData, source: 'KV-HOT' };
    }

    const r2Object = await env.API_CACHE_COLD?.get(cacheKey);
    if (r2Object) {
        const jsonData = await r2Object.json();
        const metadata = r2Object.customMetadata || {};
        const hitCount = parseInt(metadata.hitCount || '0') + 1;

        // INTELLIGENT PROMOTION: Promote frequently accessed data to KV hot cache
        const shouldPromote = hitCount >= 3 || metadata.priority === 'high';
        const kvTtl = shouldPromote ? 7200 : 3600; // 2 hours for promoted, 1 hour for regular

        if (ctx) {
            ctx.waitUntil(Promise.all([
                // Promote to KV with longer TTL for popular content
                env.CACHE?.put(cacheKey, JSON.stringify(jsonData), { expirationTtl: kvTtl }),
                // Update R2 metadata with hit count
                env.API_CACHE_COLD?.put(cacheKey, JSON.stringify(jsonData), {
                    customMetadata: { ...metadata, hitCount: hitCount.toString(), lastAccessed: Date.now().toString() }
                }),
                // Track cache promotion analytics
                trackCacheHit(cacheKey, shouldPromote ? 'R2-PROMOTED' : 'R2-COLD', env, ctx)
            ]));
        }

        return { data: jsonData, source: shouldPromote ? 'R2-PROMOTED' : 'R2-COLD', hitCount };
    }
    return null;
}

/**
 * INTELLIGENT CACHE STORAGE with tiered TTL and priority classification
 */
function setCachedData(cacheKey, data, ttlSeconds, env, ctx, priority = 'normal') {
    const jsonData = JSON.stringify(data);
    const isHighPriority = priority === 'high' || (data.provider === 'isbndb' && data.items?.length > 0);

    // TIERED TTL STRATEGY
    const kvTtl = isHighPriority ? 7200 : Math.min(ttlSeconds, 3600); // 2 hours for high priority
    const r2Ttl = isHighPriority ? ttlSeconds * 2 : ttlSeconds; // Extended R2 storage for important data

    const cacheOperations = [
        // KV Hot Cache - shorter TTL but faster access
        env.CACHE?.put(cacheKey, jsonData, { expirationTtl: kvTtl }),
        // R2 Cold Cache - longer TTL with metadata
        env.API_CACHE_COLD?.put(cacheKey, jsonData, {
            customMetadata: {
                ttl: r2Ttl.toString(),
                priority,
                created: Date.now().toString(),
                provider: data.provider || 'unknown',
                itemCount: (data.items?.length || 0).toString()
            }
        })
    ];

    if (ctx) {
        ctx.waitUntil(Promise.all(cacheOperations.filter(Boolean)));
    }
}

/**
 * Track cache hit analytics for optimization insights
 */
async function trackCacheHit(cacheKey, source, env, ctx) {
    if (!ctx) return;

    const analyticsData = {
        timestamp: Date.now(),
        cacheKey: cacheKey.substring(0, 50), // Truncate for privacy
        source,
        date: new Date().toISOString().split('T')[0]
    };

    // Store in KV with daily aggregation
    const dailyKey = `cache_analytics_${analyticsData.date}`;
    ctx.waitUntil(
        env.CACHE?.get(dailyKey, 'json')
            .then(existing => {
                const stats = existing || { date: analyticsData.date, hits: {} };
                stats.hits[source] = (stats.hits[source] || 0) + 1;
                return env.CACHE?.put(dailyKey, JSON.stringify(stats), { expirationTtl: 86400 * 7 });
            })
            .catch(err => console.error('Analytics tracking failed:', err))
    );
}

function validateSearchParams(url) {
    return {
        sanitized: {
            query: url.searchParams.get('q') || url.searchParams.get('query') || '',
            maxResults: Math.min(parseInt(url.searchParams.get('maxResults') || '20'), 40),
            sortBy: url.searchParams.get('orderBy') || 'relevance',
            includeTranslations: url.searchParams.get('includeTranslations') === 'true',
            langRestrict: url.searchParams.get('langRestrict'),
            showAllEditions: url.searchParams.get('showAllEditions') === 'true',
        }
    };
}

function classifyQuery(query) {
    const cleaned = query.replace(/[-\s]/g, '');
    if (/^\d{9}[\dX]$/.test(cleaned) || /^(978|979)\d{10}$/.test(cleaned)) {
        return { type: 'isbn' };
    }

    // Enhanced author detection for better ISBNdb routing
    const queryLower = query.toLowerCase().trim();
    const words = queryLower.split(/\s+/);

    // Detect author patterns: "firstname lastname" (2 words, no numbers)
    if (words.length === 2 && words.every(word => !/\d/.test(word) && word.length > 1)) {
        return { type: 'author', confidence: 0.8 };
    }

    // Known author patterns: common first names + surname
    const authorPatterns = /^(andy|stephen|george|harper|anne|anthony|paula|john|jane|michael|sarah|david|mary|james|robert)\s+\w+$/i;
    if (authorPatterns.test(queryLower)) {
        return { type: 'author', confidence: 0.9 };
    }

    return { type: 'mixed', confidence: 0.5 };
}

/**
 * Transform enhanced Work/Edition format to standard API format
 */
function transformWorksToStandardFormat(worksData, provider) {
    if (!worksData.works || !Array.isArray(worksData.works)) {
        return { kind: "books#volumes", totalItems: 0, items: [] };
    }

    const items = [];

    worksData.works.forEach(work => {
        work.editions.forEach(edition => {
            items.push({
                kind: "books#volume",
                id: edition.isbn || edition.identifiers?.isbndbID || `work-${Math.random().toString(36).substr(2, 9)}`,
                volumeInfo: {
                    title: work.title,
                    authors: work.authors.map(author => author.name),
                    publishedDate: edition.publicationDate || '',
                    publisher: edition.publisher || '',
                    description: edition.isbndb_metadata?.synopsis || '',
                    industryIdentifiers: edition.isbns?.map(isbn => ({
                        type: isbn.length === 13 ? "ISBN_13" : "ISBN_10",
                        identifier: isbn
                    })) || [],
                    pageCount: edition.pageCount || 0,
                    categories: edition.isbndb_metadata?.subjects || [],
                    imageLinks: edition.coverImageURL ? {
                        thumbnail: edition.coverImageURL,
                        smallThumbnail: edition.coverImageURL
                    } : undefined,
                    language: work.originalLanguage || 'en',
                    // Enhanced API identifiers for SwiftData synchronization
                    isbndbID: edition.identifiers?.isbndbID || work.identifiers?.isbndbID,
                    openLibraryID: edition.identifiers?.openLibraryID || work.identifiers?.openLibraryID,
                    googleBooksVolumeID: edition.identifiers?.googleBooksVolumeID || work.identifiers?.googleBooksVolumeID
                }
            });
        });
    });

    return {
        kind: "books#volumes",
        totalItems: items.length,
        items,
        provider,
        format: 'enhanced_work_edition_v1'
    };
}

function selectOptimalProviders(searchType, query) {
    // ISBNdb PRIORITY: Always try ISBNdb first for all search types
    // This ensures maximum cache hit rates from warming system
    return [{ name: 'isbndb' }];

    // DISABLED: Google Books and Open Library fallbacks
    // Uncomment below if fallback providers are needed:
    // if (searchType === 'isbn') {
    //     return [{ name: 'isbndb' }, { name: 'google-books' }, { name: 'open-library' }];
    // }
    // if (searchType === 'author') {
    //     return [{ name: 'isbndb' }, { name: 'google-books' }, { name: 'open-library' }];
    // }
    // // Default for title/mixed
    // return [{ name: 'isbndb' }, { name: 'google-books' }, { name: 'open-library' }];
}

function handleCORS() {
    return new Response(null, { status: 204, headers: getCORSHeaders() });
}

function getCORSHeaders(contentType = 'application/json') {
    return {
        'Content-Type': contentType,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
}

// ============================================================================
// ENHANCED MULTI-WORKER ORCHESTRATION
// ============================================================================

/**
 * ENHANCED: Multi-worker author bibliography with OpenLibrary → ISBNdb handoff
 * NEW ENDPOINT: /author/enhanced/{authorName}
 */
async function handleEnhancedAuthorBibliography(request, env, ctx) {
  try {
    const url = new URL(request.url);
    const path = url.pathname;
    const pathParts = path.split('/');
    if (pathParts.length < 4 || !pathParts[3]) {
      return new Response(JSON.stringify({ error: 'Author name is required for enhanced endpoint' }), {
        status: 400,
        headers: getCORSHeaders()
      });
    }

    const authorName = decodeURIComponent(pathParts[3]);
    console.log(`📚 Enhanced author bibliography request: ${authorName}`);

    // Step 1: Check enhanced cache with completeness validation
    const cachedResult = await checkEnhancedCache(authorName, env);

    if (cachedResult) {
      console.log(`✅ Enhanced cache HIT for author: ${authorName}`);

      return new Response(JSON.stringify({
        ...cachedResult,
        cached: true,
        cacheSource: 'ENHANCED-COMPLETE',
        timestamp: new Date().toISOString()
      }), {
        status: 200,
        headers: {
          ...getCORSHeaders(),
          'X-Cache': 'HIT-COMPLETE',
          'X-Provider': 'multi-worker-complete',
          'X-Completeness-Score': cachedResult.completenessMetadata?.completenessScore?.toString() || 'unknown',
          'X-Confidence': cachedResult.completenessMetadata?.confidence?.toString() || 'unknown'
        }
      });
    }

    // Step 2: OpenLibrary → ISBNdb Pipeline
    if (!env.OPENLIBRARY_WORKER) {
      throw new Error('OpenLibrary worker not available');
    }

    const enhancedResult = await performEnhancedAuthorLookup(authorName, env);

    // Step 3: Cache the enhanced result
    if (env.CACHE && enhancedResult) {
      try {
        await env.CACHE.put(cacheKey, JSON.stringify(enhancedResult), {
          expirationTtl: 86400 // 24 hours for complete enhanced works
        });
        console.log(`💾 Cached enhanced author: ${authorName}`);
      } catch (error) {
        console.warn('Enhanced cache write error:', error);
      }
    }

    return new Response(JSON.stringify({
      ...enhancedResult,
      cached: false,
      cacheSource: 'FRESH-ENHANCED',
      timestamp: new Date().toISOString()
    }), {
      status: 200,
      headers: {
        ...getCORSHeaders(),
        'X-Cache': 'MISS-ENHANCED',
        'X-Provider': 'openlibrary+isbndb',
        'X-Works-Count': enhancedResult.works?.length?.toString() || '0'
      }
    });

  } catch (error) {
    console.error('Enhanced author bibliography error:', error);
    return new Response(JSON.stringify({
      error: error.message,
      authorName: pathParts[3] || 'unknown',
      fallbackSuggestion: 'Try /author/{name} for ISBNdb-only results'
    }), {
      status: 500,
      headers: getCORSHeaders()
    });
  }
}

/**
 * ENHANCED: Perform OpenLibrary → ISBNdb enhancement pipeline
 */
async function performEnhancedAuthorLookup(authorName, env) {
  console.log(`🔍 Starting enhanced lookup pipeline for: ${authorName}`);

  // Step 1: Get authoritative works list from OpenLibrary
  const openLibraryUrl = `https://openlibrary-search-worker-production.jukasdrj.workers.dev/author/${encodeURIComponent(authorName)}?includeEditions=false&limit=20`;

  const olRequest = new Request(openLibraryUrl);
  const olResponse = await env.OPENLIBRARY_WORKER.fetch(olRequest);

  if (!olResponse.ok) {
    throw new Error(`OpenLibrary worker error: ${olResponse.status}`);
  }

  const olData = await olResponse.json();
  console.log(`📖 OpenLibrary found ${olData.works?.length || 0} works for ${authorName}`);

  if (!olData.success || !olData.works || olData.works.length === 0) {
    throw new Error('No works found in OpenLibrary');
  }

  // Step 2: Enhance all works with ISBNdb edition data using RPC method
  let enhancedWorks = [];
  let isbndbEnhancements = 0;

  try {
    if (env.ISBNDB_WORKER) {
      console.log(`🔧 Using ISBNdb RPC enhancement for ${olData.works.length} works`);

      // Call the enhancement endpoint via service binding
      const enhancementUrl = 'https://isbndb-biography-worker-production.jukasdrj.workers.dev/enhance/works';
      const enhancementRequest = new Request(enhancementUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          works: olData.works,
          authorName: authorName
        })
      });

      const enhancementResponse = await env.ISBNDB_WORKER.fetch(enhancementRequest);
      const enhancementResult = await enhancementResponse.json();

      if (enhancementResult.success) {
        enhancedWorks = enhancementResult.works;
        isbndbEnhancements = enhancementResult.enhancementStats.enhanced;
        console.log(`✅ ISBNdb RPC enhanced ${isbndbEnhancements}/${olData.works.length} works`);
      } else {
        console.warn('ISBNdb RPC enhancement failed, using OpenLibrary-only data');
        enhancedWorks = olData.works.map(work => ({
          ...work,
          isbndbEnhanced: false,
          dataSources: ['openlibrary']
        }));
      }
    } else {
      console.warn('ISBNdb worker not available, using OpenLibrary-only data');
      enhancedWorks = olData.works.map(work => ({
        ...work,
        isbndbEnhanced: false,
        dataSources: ['openlibrary']
      }));
    }
  } catch (error) {
    console.error('ISBNdb RPC enhancement error:', error);
    // Fallback to OpenLibrary-only data
    enhancedWorks = olData.works.map(work => ({
      ...work,
      isbndbEnhanced: false,
      dataSources: ['openlibrary']
    }));
  }

  // Step 3: Construct enhanced response
  const enhancedResult = {
    success: true,
    provider: 'openlibrary+isbndb',
    authorInfo: olData.authorInfo,
    works: enhancedWorks,
    authors: olData.authors,
    processingMetadata: {
      ...olData.processingMetadata,
      enhancementStage: 'completed',
      worksProcessed: enhancedWorks.length,
      totalWorksFound: olData.works.length,
      isbndbEnhancements: enhancedWorks.filter(w => w.isbndbEnhanced).length,
      openLibraryOnly: enhancedWorks.filter(w => !w.isbndbEnhanced).length
    },
    metadata: {
      ...olData.metadata,
      enhancedAt: new Date().toISOString(),
      pipeline: 'openlibrary->isbndb',
      processingTimeMs: Date.now() - new Date(olData.metadata?.timestamp || Date.now()).getTime()
    }
  };

  console.log(`🎯 Enhanced lookup complete: ${enhancedWorks.length} works, ${enhancedResult.processingMetadata.isbndbEnhancements} enhanced`);
  // Step 4: Update completeness metadata
  await updateAuthorCompletenessGraph(authorName, enhancedResult, env);

  return enhancedResult;
}

/**
 * Search ISBNdb for a specific work by title and author
 */
async function searchISBNdbForWork(workTitle, authorName, env) {
  try {
    // Use ISBNdb's combined search endpoint for better results
    const searchQuery = `${workTitle}`;
    const isbndbUrl = `https://isbndb-biography-worker-production.jukasdrj.workers.dev/search/books?text=${encodeURIComponent(searchQuery)}&author=${encodeURIComponent(authorName)}&pageSize=3`;

    const request = new Request(isbndbUrl);
    const response = await env.ISBNDB_WORKER.fetch(request);

    if (!response.ok) {
      console.warn(`ISBNdb search failed for "${workTitle}": ${response.status}`);
      return null;
    }

    const data = await response.json();
    return data.success ? data : null;

  } catch (error) {
    console.warn(`Error searching ISBNdb for "${workTitle}":`, error);
    return null;
  }
}

/**
 * Merge OpenLibrary work data with ISBNdb edition details
 */
function mergeWorkData(openLibraryWork, isbndbBook) {
  return {
    ...openLibraryWork,

    // Enhanced edition details from ISBNdb
    isbndbEnhanced: true,
    isbn: isbndbBook.isbn || isbndbBook.isbn13,
    publisher: isbndbBook.publisher,
    publicationDate: isbndbBook.date_published,
    pageCount: isbndbBook.pages,
    binding: isbndbBook.binding,
    coverImage: isbndbBook.image,
    dimensions: isbndbBook.dimensions,
    language: isbndbBook.language,

    // Merge identifiers
    identifiers: {
      ...openLibraryWork.identifiers,
      isbndbID: isbndbBook.id || isbndbBook.isbn13,
      isbn: isbndbBook.isbn || isbndbBook.isbn13
    },

    // Quality scores
    openLibraryQuality: openLibraryWork.openLibraryQuality || 75,
    isbndbQuality: 85, // ISBNdb typically has good metadata
    combinedQuality: Math.round(((openLibraryWork.openLibraryQuality || 75) + 85) / 2),

    // Source tracking
    dataSources: ['openlibrary', 'isbndb'],
    enhancedAt: new Date().toISOString(),

    // Best of both worlds
    description: openLibraryWork.description || isbndbBook.synopsis,
    covers: [
      ...(openLibraryWork.covers || []),
      ...(isbndbBook.image ? [isbndbBook.image] : [])
    ].filter((cover, index, arr) => arr.indexOf(cover) === index) // Deduplicate
  };
}

/**
 * DEBUG: Check completeness metadata for an author
 * ENDPOINT: /completeness/{authorName}
 */
async function handleCompletenessCheck(request, env, ctx) {
  try {
    const url = new URL(request.url);
    const path = url.pathname;
    const pathParts = path.split('/');
    if (pathParts.length < 3 || !pathParts[2]) {
      return new Response(JSON.stringify({ error: 'Author name is required for completeness check' }), {
        status: 400,
        headers: getCORSHeaders()
      });
    }

    const authorName = decodeURIComponent(pathParts[2]);
    console.log(`🔍 Completeness check for: ${authorName}`);

    // Get completeness metadata
    const completeness = await checkAuthorCompleteness(authorName, env);

    if (!completeness) {
      return new Response(JSON.stringify({
        authorName,
        status: 'no_completeness_data',
        message: 'No completeness metadata found. Author may not have been processed yet.',
        suggestion: 'Try /author/enhanced/{name} first to generate completeness data'
      }), {
        status: 404,
        headers: getCORSHeaders()
      });
    }

    // Also check if enhanced cache exists
    const cacheKey = `author_enhanced:${authorName.toLowerCase()}`;
    let cacheExists = false;
    let cacheSize = 0;

    if (env.CACHE) {
      try {
        const cached = await env.CACHE.get(cacheKey);
        cacheExists = !!cached;
        cacheSize = cached ? cached.length : 0;
      } catch (error) {
        // Ignore cache check errors
      }
    }

    return new Response(JSON.stringify({
      authorName,
      status: 'completeness_available',
      completenessMetadata: completeness,
      cache: {
        enhancedCacheExists: cacheExists,
        cacheSize,
        cacheKey
      },
      interpretation: {
        isComplete: completeness.isComplete,
        confidence: completeness.confidence,
        qualityLevel: getQualityLevel(completeness.completenessScore),
        recommendation: getRecommendation(completeness),
        needsRefresh: shouldRefreshData(completeness)
      },
      debug: {
        cacheGeneration: completeness.cacheGeneration,
        lastValidated: completeness.lastValidated,
        lastEnhanced: completeness.lastEnhanced,
        dataSources: completeness.dataSources,
        pipeline: completeness.pipeline
      }
    }), {
      status: 200,
      headers: {
        ...getCORSHeaders(),
        'X-Completeness-Score': completeness.completenessScore.toString(),
        'X-Confidence': completeness.confidence.toString(),
        'X-Is-Complete': completeness.isComplete.toString()
      }
    });

  } catch (error) {
    console.error('Completeness check error:', error);
    return new Response(JSON.stringify({
      error: error.message,
      authorName: pathParts[2] || 'unknown'
    }), {
      status: 500,
      headers: getCORSHeaders()
    });
  }
}

/**
 * Helper functions for completeness interpretation
 */
function getQualityLevel(score) {
  if (score >= 90) return 'excellent';
  if (score >= 80) return 'good';
  if (score >= 60) return 'fair';
  if (score >= 40) return 'poor';
  return 'very_poor';
}

function getRecommendation(completeness) {
  if (completeness.isComplete && completeness.confidence >= 80) {
    return 'Data is complete and high-confidence. Use cached results.';
  }
  if (completeness.confidence < 50) {
    return 'Low confidence data. Consider refreshing from sources.';
  }
  if (!completeness.isComplete) {
    return 'Incomplete bibliography. May need additional sources or manual curation.';
  }
  return 'Moderate quality data. Usable but could be improved.';
}

function shouldRefreshData(completeness) {
  const age = Date.now() - new Date(completeness.lastValidated).getTime();
  const daysSinceValidation = age / (24 * 60 * 60 * 1000);

  return (
    daysSinceValidation > 7 ||           // Older than 7 days
    completeness.confidence < 50 ||      // Low confidence
    !completeness.isComplete             // Incomplete data
  );
}

// ============================================================================
// AUTHOR BIBLIOGRAPHY COMPLETENESS GRAPH
// ============================================================================

/**
 * Check if we have complete bibliography for an author
 */
async function checkAuthorCompleteness(authorName, env) {
  if (!env.CACHE) return null;

  try {
    const completenessKey = `completeness:${authorName.toLowerCase()}`;
    const cached = await env.CACHE.get(completenessKey);

    if (!cached) return null;

    const completenessData = JSON.parse(cached);

    // Check if completeness data is still valid (7 days)
    const age = Date.now() - new Date(completenessData.lastValidated).getTime();
    const maxAge = 7 * 24 * 60 * 60 * 1000; // 7 days

    if (age > maxAge) {
      console.log(`⏰ Completeness data expired for ${authorName}`);
      return null;
    }

    return completenessData;

  } catch (error) {
    console.warn('Error checking author completeness:', error);
    return null;
  }
}

/**
 * Update author completeness metadata after successful lookup
 */
async function updateAuthorCompletenessGraph(authorName, enhancedResult, env) {
  if (!env.CACHE) return;

  try {
    const completenessKey = `completeness:${authorName.toLowerCase()}`;

    // Calculate completeness metrics
    const metrics = calculateCompletenessMetrics(enhancedResult);

    const completenessData = {
      authorName: authorName,
      isComplete: metrics.isComplete,
      confidence: metrics.confidence,
      completenessScore: metrics.completenessScore,

      // Work inventory
      coreWorksFound: metrics.coreWorksFound,
      totalWorksProcessed: enhancedResult.works?.length || 0,
      expectedCoreWorks: metrics.expectedCoreWorks,

      // Data quality
      authoritativeSource: 'openlibrary', // OpenLibrary is our authoritative source
      enhancementCoverage: {
        isbndbEnhanced: enhancedResult.processingMetadata?.isbndbEnhancements || 0,
        openLibraryOnly: enhancedResult.processingMetadata?.openLibraryOnly || 0,
        enhancementRate: metrics.enhancementRate
      },

      // Provider coverage analysis
      providerCoverage: {
        openlibrary: {
          available: true,
          worksCount: enhancedResult.works?.length || 0,
          quality: metrics.openLibraryQuality
        },
        isbndb: {
          available: true,
          worksCount: enhancedResult.processingMetadata?.isbndbEnhancements || 0,
          quality: metrics.isbndbQuality
        }
      },

      // Timestamps and validation
      lastValidated: new Date().toISOString(),
      lastEnhanced: new Date().toISOString(),
      cacheGeneration: 1,

      // Quality indicators
      qualityIndicators: {
        hasAuthorInfo: !!enhancedResult.authorInfo,
        hasWorkDetails: enhancedResult.works?.length > 0,
        hasISBNs: metrics.worksWithISBNs,
        hasCoverImages: metrics.worksWithCovers,
        hasPublicationDates: metrics.worksWithDates
      },

      // Source tracking
      dataSources: ['openlibrary', 'isbndb'],
      pipeline: 'openlibrary->isbndb'
    };

    // Store completeness data with 7-day expiration
    await env.CACHE.put(completenessKey, JSON.stringify(completenessData), {
      expirationTtl: 7 * 24 * 60 * 60 // 7 days
    });

    console.log(`📊 Updated completeness for ${authorName}: ${metrics.completenessScore}% complete, ${metrics.confidence}% confidence`);

  } catch (error) {
    console.warn('Error updating author completeness:', error);
  }
}

/**
 * Calculate completeness metrics for an author's bibliography
 */
function calculateCompletenessMetrics(enhancedResult) {
  const works = enhancedResult.works || [];
  const totalWorks = works.length;

  if (totalWorks === 0) {
    return {
      isComplete: false,
      confidence: 0,
      completenessScore: 0,
      coreWorksFound: 0,
      expectedCoreWorks: 0,
      enhancementRate: 0,
      openLibraryQuality: 0,
      isbndbQuality: 0,
      worksWithISBNs: 0,
      worksWithCovers: 0,
      worksWithDates: 0
    };
  }

  // Count core works (using our filtering logic)
  const coreWorks = works.filter(work =>
    work.title &&
    !work.title.toLowerCase().includes('collection') &&
    !work.title.toLowerCase().includes('set') &&
    work.title.length < 100 // Reasonable title length
  );

  // Quality metrics
  const worksWithISBNs = works.filter(w => w.isbn || w.identifiers?.isbn).length;
  const worksWithCovers = works.filter(w =>
    (w.covers && w.covers.length > 0) ||
    w.coverImage
  ).length;
  const worksWithDates = works.filter(w =>
    w.firstPublicationYear ||
    w.publicationDate
  ).length;

  // Enhancement metrics
  const isbndbEnhanced = works.filter(w => w.isbndbEnhanced).length;
  const enhancementRate = totalWorks > 0 ? (isbndbEnhanced / totalWorks) * 100 : 0;

  // Author-specific expectations (this could be enhanced with known author data)
  const expectedCoreWorks = estimateExpectedCoreWorks(enhancedResult.authorInfo);

  // Completeness calculation
  const coreWorksRatio = expectedCoreWorks > 0 ? (coreWorks.length / expectedCoreWorks) : 1;
  const qualityRatio = totalWorks > 0 ? (worksWithISBNs + worksWithCovers + worksWithDates) / (totalWorks * 3) : 0;

  const completenessScore = Math.min(100, Math.round(
    (coreWorksRatio * 60) + // 60% weight for having core works
    (qualityRatio * 30) +   // 30% weight for data quality
    (enhancementRate * 0.1)  // 10% weight for enhancement coverage
  ));

  // Confidence based on data quality and consistency
  const confidence = Math.min(100, Math.round(
    (enhancedResult.authorInfo?.name ? 20 : 0) + // Author info available
    (totalWorks >= expectedCoreWorks ? 30 : (totalWorks / expectedCoreWorks) * 30) + // Work count
    (enhancementRate > 50 ? 25 : enhancementRate * 0.5) + // Enhancement coverage
    (qualityRatio * 25) // Data quality
  ));

  return {
    isComplete: completenessScore >= 80 && confidence >= 70,
    confidence,
    completenessScore,
    coreWorksFound: coreWorks.length,
    expectedCoreWorks,
    enhancementRate: Math.round(enhancementRate),
    openLibraryQuality: 85, // OpenLibrary typically has good work-level data
    isbndbQuality: enhancementRate > 0 ? 85 : 0,
    worksWithISBNs,
    worksWithCovers,
    worksWithDates
  };
}

/**
 * Estimate expected core works for an author based on available info
 */
function estimateExpectedCoreWorks(authorInfo) {
  if (!authorInfo) return 5; // Default assumption

  // Use author's work count if available
  if (authorInfo.workCount) {
    // Filter out likely translations and collections (rough estimate)
    const estimatedCore = Math.ceil(authorInfo.workCount * 0.3); // ~30% are likely core works
    return Math.min(estimatedCore, 20); // Cap at 20 for performance
  }

  // Default for unknown authors
  return 5;
}

/**
 * Enhanced cache check that includes completeness validation
 */
async function checkEnhancedCache(authorName, env) {
  if (!env.CACHE) return null;

  try {
    // Check both regular cache and completeness data
    const cacheKey = `author_enhanced:${authorName.toLowerCase()}`;
    const cached = await env.CACHE.get(cacheKey);

    if (!cached) return null;

    const cachedResult = JSON.parse(cached);

    // Check completeness metadata
    const completeness = await checkAuthorCompleteness(authorName, env);

    if (completeness) {
      // Add completeness info to cached result
      cachedResult.completenessMetadata = {
        isComplete: completeness.isComplete,
        confidence: completeness.confidence,
        completenessScore: completeness.completenessScore,
        lastValidated: completeness.lastValidated,
        coreWorksFound: completeness.coreWorksFound,
        expectedCoreWorks: completeness.expectedCoreWorks
      };

      // If confidence is high and data is complete, use cached result
      if (completeness.confidence >= 70 && completeness.isComplete) {
        console.log(`✅ High-confidence complete cache for ${authorName} (${completeness.confidence}% confidence, ${completeness.completenessScore}% complete)`);
        return cachedResult;
      } else {
        console.log(`⚠️ Low-confidence cache for ${authorName} (${completeness.confidence}% confidence, ${completeness.completenessScore}% complete) - considering refresh`);

        // If data is old or low confidence, we might want to refresh
        const age = Date.now() - new Date(completeness.lastValidated).getTime();
        const shouldRefresh = age > (24 * 60 * 60 * 1000) || completeness.confidence < 50; // 24 hours or low confidence

        if (!shouldRefresh) {
          return cachedResult;
        }
      }
    }

    return null; // Indicate cache miss or needs refresh

  } catch (error) {
    console.warn('Enhanced cache check error:', error);
    return null;
  }
}