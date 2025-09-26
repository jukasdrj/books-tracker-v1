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
      if (path.startsWith('/author/')) {
        return await handleAuthorBibliography(request, env, ctx);
      }
      if (path === '/health') {
        return new Response(JSON.stringify({
          status: 'healthy',
          timestamp: new Date().toISOString(),
          providers: ['google-books', 'isbndb-worker', 'open-library'],
          cache: {
            system: env.API_CACHE_COLD ? 'R2+KV-Hybrid' : 'KV-Only',
            kv: env.CACHE ? 'available' : 'missing',
            r2: env.API_CACHE_COLD ? 'available' : 'missing'
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
    if (!isbndbData || (!isbndbData.books && !isbndbData.book)) {
        return { kind: "books#volumes", totalItems: 0, items: [] };
    }

    const books = isbndbData.books || (isbndbData.book ? [isbndbData.book] : []);

    // ✅ SMART FILTERING: Apply quality filters before transformation
    const filteredBooks = applyBookQualityFilters(books);

    return {
        kind: "books#volumes",
        totalItems: filteredBooks.length,
        items: filteredBooks.map(book => ({
            kind: "books#volume",
            id: book.isbn13 || book.isbn || `isbndb-${Math.random().toString(36).substr(2, 9)}`,
            volumeInfo: {
                title: book.title || 'Unknown Title',
                authors: book.authors || (book.author ? [book.author] : ['Unknown Author']),
                publishedDate: book.date_published || '',
                publisher: book.publisher || '',
                description: book.synopsis || '',
                industryIdentifiers: [
                    ...(book.isbn13 ? [{ type: "ISBN_13", identifier: book.isbn13 }] : []),
                    ...(book.isbn ? [{ type: "ISBN_10", identifier: book.isbn }] : [])
                ],
                pageCount: book.pages || 0,
                categories: (book.subjects && typeof book.subjects === 'string') ? book.subjects.split(',').map(s => s.trim()) : (book.subjects || []),
                imageLinks: book.image ? { thumbnail: book.image, smallThumbnail: book.image } : undefined,
                language: book.language || 'en',
                // API identifiers for SwiftData model synchronization
                isbndbID: book.id || book.isbn13 || book.isbn || null
            }
        })),
        provider: provider
    };
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

function selectOptimalProviders(searchType, query) {
    // ✅ ISBNdb PRIORITY: Always try ISBNdb first for all search types
    // This ensures maximum cache hit rates from warming system
    return [{ name: 'isbndb' }];

    // ❌ DISABLED: Google Books and Open Library fallbacks
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