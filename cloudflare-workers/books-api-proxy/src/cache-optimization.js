/**
 * ADVANCED CACHE OPTIMIZATION MODULE
 *
 * Addresses the 30-40% cache hit rate issue with:
 * - Intelligent cache key normalization
 * - Multi-tier caching strategy optimization
 * - Cache miss pattern analysis and correction
 * - Automatic cache warming for popular content
 * - Performance analytics and hit rate tracking
 *
 * Target: >85% cache hit rate for repeat queries
 */

// ============================================================================
// CACHE KEY OPTIMIZATION
// ============================================================================

/**
 * ENHANCED: Intelligent cache key creation with normalization
 * Addresses cache miss issues by standardizing query variations
 */
export function createOptimizedCacheKey(type, query, params = {}) {
    // Normalize query for better cache hits
    const normalizedQuery = normalizeQueryForCaching(query);

    // Create stable parameter hash
    const stableParams = createStableParamHash(params);

    // Include search type in key for better specificity
    const searchType = classifyQueryForCaching(normalizedQuery);

    // Generate optimized cache key
    const keyComponents = [
        type,
        searchType,
        normalizedQuery,
        stableParams
    ].filter(Boolean);

    const cacheKey = keyComponents.join(':');

    // Hash long keys to prevent key length issues
    if (cacheKey.length > 200) {
        const hashInput = keyComponents.join('|');
        const hash = simpleHash(hashInput);
        return `${type}:${searchType}:${hash}`;
    }

    return cacheKey;
}

/**
 * Normalize query strings for consistent caching
 */
function normalizeQueryForCaching(query) {
    if (!query || typeof query !== 'string') return '';

    return query
        .toLowerCase()
        .trim()
        // Remove extra whitespace
        .replace(/\s+/g, ' ')
        // Remove common punctuation that doesn't affect search
        .replace(/[.,!?;:'"]/g, '')
        // Remove parenthetical content that might vary
        .replace(/\([^)]*\)/g, '')
        // Remove leading/trailing articles
        .replace(/^(the|a|an)\s+/i, '')
        .replace(/\s+(the|a|an)$/i, '')
        // Standardize apostrophes
        .replace(/['`']/g, "'")
        // Remove multiple spaces again
        .replace(/\s+/g, ' ')
        .trim();
}

/**
 * Create stable parameter hash for consistent caching
 */
function createStableParamHash(params) {
    if (!params || typeof params !== 'object') return '';

    // Extract only cache-relevant parameters
    const relevantParams = {
        maxResults: params.maxResults || 20,
        sortBy: params.sortBy || 'relevance',
        searchType: params.searchType || 'mixed',
        showAllEditions: params.showAllEditions || false
    };

    // Sort keys for consistency
    const sortedKeys = Object.keys(relevantParams).sort();
    const paramString = sortedKeys
        .map(key => `${key}=${relevantParams[key]}`)
        .join('&');

    return paramString;
}

/**
 * Enhanced query classification for cache key optimization
 */
function classifyQueryForCaching(query) {
    // ISBN detection
    const cleaned = query.replace(/[-\s]/g, '');
    if (/^\d{9}[\dX]$/.test(cleaned) || /^(978|979)\d{10}$/.test(cleaned)) {
        return 'isbn';
    }

    // Enhanced author detection
    const words = query.split(/\s+/);
    if (words.length === 2 && words.every(word => !/\d/.test(word) && word.length > 1)) {
        return 'author';
    }

    // Known author patterns
    const authorPatterns = /^(andy|stephen|george|harper|anne|anthony|paula|john|jane|michael|sarah|david|mary|james|robert|margaret)\s+\w+$/i;
    if (authorPatterns.test(query)) {
        return 'author';
    }

    // Title indicators
    if (query.length > 10 && words.length > 2) {
        return 'title';
    }

    return 'mixed';
}

/**
 * Simple hash function for cache keys
 */
function simpleHash(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash).toString(36);
}

// ============================================================================
// CACHE MISS ANALYSIS AND DEBUGGING
// ============================================================================

/**
 * Analyze cache miss patterns to identify optimization opportunities
 */
export async function analyzeCacheMissPatterns(env) {
    console.log('🔍 Starting cache miss pattern analysis...');

    const analysis = {
        timestamp: new Date().toISOString(),
        cacheStats: await getCacheStatistics(env),
        missPatterns: await analyzeMissPatterns(env),
        recommendations: []
    };

    // Generate optimization recommendations
    analysis.recommendations = generateCacheOptimizationRecommendations(analysis);

    console.log('📊 Cache analysis completed:', {
        kvCacheSize: analysis.cacheStats.kvEntries,
        r2CacheSize: analysis.cacheStats.r2Objects,
        estimatedHitRate: analysis.cacheStats.estimatedHitRate,
        topMissPatterns: analysis.missPatterns.slice(0, 5)
    });

    return analysis;
}

/**
 * Get comprehensive cache statistics
 */
async function getCacheStatistics(env) {
    const stats = {
        kvEntries: 0,
        r2Objects: 0,
        estimatedHitRate: 0,
        cacheSize: {
            kvSizeEstimate: 0,
            r2SizeEstimate: 0
        },
        keyPatterns: new Map()
    };

    try {
        // KV cache analysis
        if (env.CACHE) {
            const kvKeys = await env.CACHE.list({ limit: 1000 });
            stats.kvEntries = kvKeys.keys.length;

            // Analyze key patterns
            kvKeys.keys.forEach(key => {
                const keyType = key.name.split(':')[0];
                stats.keyPatterns.set(keyType, (stats.keyPatterns.get(keyType) || 0) + 1);
            });

            console.log(`📈 Found ${stats.kvEntries} KV cache entries`);
        }

        // R2 cache analysis
        if (env.API_CACHE_COLD) {
            const r2Objects = await env.API_CACHE_COLD.list({ limit: 1000 });
            stats.r2Objects = r2Objects.objects.length;

            // Estimate total size
            stats.cacheSize.r2SizeEstimate = r2Objects.objects.reduce(
                (total, obj) => total + (obj.size || 0), 0
            );

            console.log(`🗄️ Found ${stats.r2Objects} R2 cache objects (${formatBytes(stats.cacheSize.r2SizeEstimate)})`);
        }

        // Calculate estimated hit rate from analytics
        stats.estimatedHitRate = await calculateHitRateFromAnalytics(env);

    } catch (error) {
        console.warn('Cache statistics gathering failed:', error);
    }

    return stats;
}

/**
 * Analyze common cache miss patterns
 */
async function analyzeMissPatterns(env) {
    const missPatterns = [];

    try {
        // Get recent analytics data
        const today = new Date().toISOString().split('T')[0];
        const analyticsKey = `cache_analytics_${today}`;
        const analytics = await env.CACHE?.get(analyticsKey, 'json');

        if (analytics?.hits) {
            const totalHits = Object.values(analytics.hits).reduce((sum, count) => sum + count, 0);
            const kvHits = analytics.hits['KV-HOT'] || 0;
            const r2Hits = analytics.hits['R2-COLD'] || analytics.hits['R2-PROMOTED'] || 0;

            const estimatedMisses = Math.max(0, totalHits * 2 - kvHits - r2Hits); // Rough estimate

            if (estimatedMisses > 0) {
                missPatterns.push({
                    pattern: 'query_variation',
                    description: 'Similar queries with different formatting',
                    estimatedImpact: estimatedMisses * 0.3,
                    priority: 'high'
                });

                missPatterns.push({
                    pattern: 'parameter_differences',
                    description: 'Same queries with different parameters',
                    estimatedImpact: estimatedMisses * 0.2,
                    priority: 'medium'
                });

                missPatterns.push({
                    pattern: 'case_sensitivity',
                    description: 'Case variations in author/title names',
                    estimatedImpact: estimatedMisses * 0.15,
                    priority: 'medium'
                });
            }
        }

        // Add pattern for popular authors not in cache
        const popularAuthors = getPopularAuthorsList();
        for (const author of popularAuthors.slice(0, 10)) {
            const cacheKey = createOptimizedCacheKey('auto-search', author.name, {});
            const cached = await env.CACHE?.get(cacheKey);

            if (!cached) {
                missPatterns.push({
                    pattern: 'popular_author_missing',
                    description: `Popular author "${author.name}" not cached`,
                    estimatedImpact: author.searchVolume || 100,
                    priority: 'high',
                    author: author.name
                });
            }
        }

    } catch (error) {
        console.warn('Miss pattern analysis failed:', error);
    }

    return missPatterns.sort((a, b) => b.estimatedImpact - a.estimatedImpact);
}

/**
 * Calculate hit rate from analytics data
 */
async function calculateHitRateFromAnalytics(env) {
    try {
        const today = new Date().toISOString().split('T')[0];
        const analyticsKey = `cache_analytics_${today}`;
        const analytics = await env.CACHE?.get(analyticsKey, 'json');

        if (analytics?.hits) {
            const totalHits = Object.values(analytics.hits).reduce((sum, count) => sum + count, 0);
            const cacheHits = (analytics.hits['KV-HOT'] || 0) + (analytics.hits['R2-COLD'] || 0) + (analytics.hits['R2-PROMOTED'] || 0);

            if (totalHits > 0) {
                return Math.round((cacheHits / totalHits) * 100);
            }
        }
    } catch (error) {
        console.warn('Hit rate calculation failed:', error);
    }

    return 0;
}

/**
 * Generate cache optimization recommendations
 */
function generateCacheOptimizationRecommendations(analysis) {
    const recommendations = [];

    // Low hit rate recommendations
    if (analysis.cacheStats.estimatedHitRate < 60) {
        recommendations.push({
            type: 'critical',
            title: 'Low Cache Hit Rate',
            description: `Current hit rate is ${analysis.cacheStats.estimatedHitRate}%. Implement query normalization and cache warming.`,
            actions: [
                'Deploy optimized cache key normalization',
                'Implement popular content pre-warming',
                'Add query variation detection'
            ],
            estimatedImprovement: '30-40% hit rate increase'
        });
    }

    // Popular content missing
    const popularMisses = analysis.missPatterns.filter(p => p.pattern === 'popular_author_missing');
    if (popularMisses.length > 5) {
        recommendations.push({
            type: 'high',
            title: 'Popular Content Not Cached',
            description: `${popularMisses.length} popular authors missing from cache`,
            actions: [
                'Run cache warming for top 100 authors',
                'Implement automatic popular content detection',
                'Set up scheduled cache refresh'
            ],
            estimatedImprovement: '15-25% hit rate increase'
        });
    }

    // Query variation issues
    const variationPatterns = analysis.missPatterns.filter(p =>
        p.pattern === 'query_variation' || p.pattern === 'case_sensitivity'
    );
    if (variationPatterns.length > 0) {
        recommendations.push({
            type: 'medium',
            title: 'Query Variation Cache Misses',
            description: 'Similar queries creating separate cache entries',
            actions: [
                'Implement enhanced query normalization',
                'Add fuzzy cache key matching',
                'Create query alias system'
            ],
            estimatedImprovement: '10-20% hit rate increase'
        });
    }

    return recommendations;
}

// ============================================================================
// CACHE WARMING STRATEGIES
// ============================================================================

/**
 * Implement intelligent cache warming for popular content
 */
export async function warmPopularContent(env, options = {}) {
    const {
        maxAuthors = 100,
        maxBooksPerAuthor = 20,
        concurrency = 3,
        dryRun = false
    } = options;

    console.log(`🔥 Starting cache warming for ${maxAuthors} popular authors (dryRun: ${dryRun})`);

    const popularAuthors = getPopularAuthorsList().slice(0, maxAuthors);
    const warmingResults = {
        attempted: 0,
        successful: 0,
        failed: 0,
        errors: [],
        cached: []
    };

    // Process authors in batches to avoid overwhelming the system
    for (let i = 0; i < popularAuthors.length; i += concurrency) {
        const batch = popularAuthors.slice(i, i + concurrency);

        const batchPromises = batch.map(async (author) => {
            try {
                warmingResults.attempted++;

                if (dryRun) {
                    console.log(`[DRY RUN] Would warm cache for: ${author.name}`);
                    return { success: true, author: author.name, cached: false };
                }

                // Check if already cached
                const cacheKey = createOptimizedCacheKey('auto-search', author.name, { maxResults: maxBooksPerAuthor });
                const existing = await env.CACHE?.get(cacheKey);

                if (existing) {
                    console.log(`✓ ${author.name} already cached`);
                    return { success: true, author: author.name, cached: true, skipped: true };
                }

                // Warm the cache by making a search request
                const result = await searchAuthorForWarming(author.name, maxBooksPerAuthor, env);

                if (result && result.items?.length > 0) {
                    // Cache the result with high priority
                    await setCachedData(cacheKey, result, 86400 * 7, env, null, 'high'); // 7 days

                    console.log(`✅ Warmed cache for ${author.name} (${result.items.length} results)`);
                    warmingResults.successful++;
                    warmingResults.cached.push({
                        author: author.name,
                        itemCount: result.items.length,
                        provider: result.provider
                    });

                    return { success: true, author: author.name, cached: true };
                } else {
                    throw new Error('No results found');
                }

            } catch (error) {
                console.warn(`❌ Failed to warm cache for ${author.name}:`, error.message);
                warmingResults.failed++;
                warmingResults.errors.push({
                    author: author.name,
                    error: error.message
                });

                return { success: false, author: author.name, error: error.message };
            }
        });

        // Wait for batch to complete
        await Promise.allSettled(batchPromises);

        // Rate limiting between batches
        if (i + concurrency < popularAuthors.length) {
            await new Promise(resolve => setTimeout(resolve, 2000)); // 2 second pause
        }
    }

    console.log(`🎯 Cache warming completed:`, {
        attempted: warmingResults.attempted,
        successful: warmingResults.successful,
        failed: warmingResults.failed,
        successRate: `${Math.round((warmingResults.successful / warmingResults.attempted) * 100)}%`
    });

    return warmingResults;
}

/**
 * Search author specifically for cache warming (simplified)
 */
async function searchAuthorForWarming(authorName, maxResults, env) {
    try {
        // Use ISBNdb worker for high-quality author data
        if (env.ISBNDB_WORKER) {
            return await searchISBNdbWithWorker(authorName, maxResults, 'author', env);
        }

        // Fallback to OpenLibrary
        if (env.OPENLIBRARY_WORKER) {
            return await searchOpenLibraryWithWorker(authorName, maxResults, 'author', env);
        }

        throw new Error('No workers available for cache warming');

    } catch (error) {
        console.warn(`Cache warming search failed for ${authorName}:`, error.message);
        throw error;
    }
}

/**
 * Get list of popular authors for cache warming
 */
function getPopularAuthorsList() {
    return [
        { name: 'Stephen King', searchVolume: 1000 },
        { name: 'Andy Weir', searchVolume: 800 },
        { name: 'Margaret Atwood', searchVolume: 750 },
        { name: 'George R. R. Martin', searchVolume: 900 },
        { name: 'J.K. Rowling', searchVolume: 1200 },
        { name: 'Harper Lee', searchVolume: 600 },
        { name: 'Agatha Christie', searchVolume: 700 },
        { name: 'Ernest Hemingway', searchVolume: 650 },
        { name: 'Jane Austen', searchVolume: 700 },
        { name: 'Neil Gaiman', searchVolume: 550 },
        { name: 'Gillian Flynn', searchVolume: 500 },
        { name: 'Toni Morrison', searchVolume: 450 },
        { name: 'Maya Angelou', searchVolume: 400 },
        { name: 'Chimamanda Ngozi Adichie', searchVolume: 350 },
        { name: 'Octavia Butler', searchVolume: 400 },
        { name: 'Zadie Smith', searchVolume: 300 },
        { name: 'Jhumpa Lahiri', searchVolume: 250 },
        { name: 'Arundhati Roy', searchVolume: 200 },
        { name: 'Haruki Murakami', searchVolume: 600 },
        { name: 'Paulo Coelho', searchVolume: 500 },
        // Additional popular authors for comprehensive warming
        { name: 'Dan Brown', searchVolume: 480 },
        { name: 'John Grisham', searchVolume: 460 },
        { name: 'James Patterson', searchVolume: 440 },
        { name: 'Michael Crichton', searchVolume: 420 },
        { name: 'Ken Follett', searchVolume: 400 },
        { name: 'Tom Clancy', searchVolume: 380 },
        { name: 'Dean Koontz', searchVolume: 360 },
        { name: 'Patricia Cornwell', searchVolume: 340 },
        { name: 'Sue Grafton', searchVolume: 320 },
        { name: 'Janet Evanovich', searchVolume: 300 }
    ];
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Format bytes for human-readable display
 */
function formatBytes(bytes, decimals = 2) {
    if (bytes === 0) return '0 Bytes';

    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];

    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

// Note: These functions are referenced but need to be imported from the main index.js
// - searchISBNdbWithWorker
// - searchOpenLibraryWithWorker
// - setCachedData

export {
    createOptimizedCacheKey,
    analyzeCacheMissPatterns,
    warmPopularContent,
    normalizeQueryForCaching,
    classifyQueryForCaching
};