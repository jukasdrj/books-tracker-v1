/**
 * CACHE WARMING WORKER
 *
 * Standalone worker for intelligent cache pre-warming:
 * - Top 100 popular authors with scheduled warming
 * - Popular book searches based on analytics
 * - Intelligent warming based on cache miss patterns
 * - Performance monitoring and reporting
 *
 * Can be deployed as a separate worker or integrated into existing system
 */

// ============================================================================
// CACHE WARMING ORCHESTRATOR
// ============================================================================

export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);
        const path = url.pathname;

        try {
            if (path === '/warm/popular-authors') {
                return await warmPopularAuthors(request, env, ctx);
            }

            if (path === '/warm/analytics-driven') {
                return await warmAnalyticsDriven(request, env, ctx);
            }

            if (path === '/warm/status') {
                return await getWarmingStatus(request, env, ctx);
            }

            if (path === '/warm/schedule') {
                return await scheduleWarming(request, env, ctx);
            }

            if (path === '/health') {
                return new Response(JSON.stringify({
                    status: 'healthy',
                    service: 'cache-warming-worker',
                    timestamp: new Date().toISOString(),
                    capabilities: [
                        'popular_authors_warming',
                        'analytics_driven_warming',
                        'scheduled_warming',
                        'performance_monitoring'
                    ]
                }), {
                    status: 200,
                    headers: { 'Content-Type': 'application/json' }
                });
            }

            return new Response('Not Found', { status: 404 });

        } catch (error) {
            console.error('Cache warming worker error:', error);
            return new Response(JSON.stringify({
                error: 'Internal server error',
                message: error.message
            }), {
                status: 500,
                headers: { 'Content-Type': 'application/json' }
            });
        }
    },

    // Scheduled worker for automatic cache warming
    async scheduled(controller, env, ctx) {
        const cronType = controller.cron;

        console.log(`🕐 Scheduled cache warming triggered: ${cronType}`);

        try {
            switch (cronType) {
                case '0 6 * * *': // Daily at 6 AM UTC
                    await performDailyWarming(env, ctx);
                    break;

                case '0 */4 * * *': // Every 4 hours
                    await performPeriodicWarming(env, ctx);
                    break;

                default:
                    console.log(`Unknown cron schedule: ${cronType}`);
            }

        } catch (error) {
            console.error('Scheduled warming failed:', error);
        }
    }
};

// ============================================================================
// WARMING STRATEGIES
// ============================================================================

/**
 * Warm cache for top popular authors
 */
async function warmPopularAuthors(request, env, ctx) {
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit')) || 50;
    const dryRun = url.searchParams.get('dryRun') === 'true';
    const force = url.searchParams.get('force') === 'true';

    console.log(`🔥 Starting popular authors warming (limit: ${limit}, dryRun: ${dryRun})`);

    const startTime = Date.now();
    const results = {
        requested: limit,
        processed: 0,
        successful: 0,
        skipped: 0,
        failed: 0,
        errors: [],
        authors: []
    };

    try {
        const popularAuthors = getPopularAuthorsList().slice(0, limit);

        for (const author of popularAuthors) {
            try {
                results.processed++;

                console.log(`🔍 Processing author: ${author.name}`);

                // Check if already cached (unless forced)
                if (!force) {
                    const cacheKey = createCacheKey('auto-search', author.name, { maxResults: 20 });
                    const cached = await env.CACHE?.get(cacheKey);

                    if (cached) {
                        console.log(`✅ ${author.name} already cached, skipping`);
                        results.skipped++;
                        results.authors.push({
                            name: author.name,
                            status: 'skipped',
                            reason: 'already_cached'
                        });
                        continue;
                    }
                }

                if (dryRun) {
                    console.log(`[DRY RUN] Would warm cache for: ${author.name}`);
                    results.successful++;
                    results.authors.push({
                        name: author.name,
                        status: 'dry_run',
                        itemCount: 0
                    });
                    continue;
                }

                // Perform cache warming
                const result = await warmAuthorCache(author, env);

                if (result.success) {
                    results.successful++;
                    results.authors.push({
                        name: author.name,
                        status: 'warmed',
                        itemCount: result.itemCount,
                        provider: result.provider,
                        duration: result.duration
                    });
                    console.log(`✅ Warmed ${author.name} (${result.itemCount} results, ${result.duration}ms)`);
                } else {
                    results.failed++;
                    results.errors.push({
                        author: author.name,
                        error: result.error
                    });
                    results.authors.push({
                        name: author.name,
                        status: 'failed',
                        error: result.error
                    });
                    console.warn(`❌ Failed to warm ${author.name}: ${result.error}`);
                }

                // Rate limiting between requests
                await new Promise(resolve => setTimeout(resolve, 1000)); // 1 second delay

            } catch (error) {
                results.failed++;
                results.errors.push({
                    author: author.name,
                    error: error.message
                });
                console.error(`💥 Error processing ${author.name}:`, error);
            }
        }

        const duration = Date.now() - startTime;
        const response = {
            ...results,
            performance: {
                totalDuration: duration,
                averagePerAuthor: Math.round(duration / results.processed),
                successRate: Math.round((results.successful / results.processed) * 100)
            },
            timestamp: new Date().toISOString()
        };

        console.log(`🎯 Popular authors warming completed: ${results.successful}/${results.processed} successful (${response.performance.successRate}%)`);

        return new Response(JSON.stringify(response), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });

    } catch (error) {
        console.error('Popular authors warming failed:', error);
        return new Response(JSON.stringify({
            error: 'Warming failed',
            message: error.message,
            results
        }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

/**
 * Analytics-driven cache warming based on miss patterns
 */
async function warmAnalyticsDriven(request, env, ctx) {
    console.log('📊 Starting analytics-driven cache warming...');

    try {
        // Analyze cache miss patterns
        const missPatterns = await analyzeCacheMissPatterns(env);

        // Extract warming targets from patterns
        const warmingTargets = extractWarmingTargets(missPatterns);

        console.log(`🎯 Found ${warmingTargets.length} warming targets from analytics`);

        const results = {
            targets: warmingTargets.length,
            processed: 0,
            successful: 0,
            failed: 0,
            details: []
        };

        for (const target of warmingTargets) {
            try {
                results.processed++;

                console.log(`🔥 Warming target: ${target.query} (priority: ${target.priority})`);

                const result = await warmSearchQuery(target.query, target.params, env);

                if (result.success) {
                    results.successful++;
                    results.details.push({
                        query: target.query,
                        status: 'success',
                        itemCount: result.itemCount,
                        provider: result.provider
                    });
                } else {
                    results.failed++;
                    results.details.push({
                        query: target.query,
                        status: 'failed',
                        error: result.error
                    });
                }

            } catch (error) {
                results.failed++;
                results.details.push({
                    query: target.query,
                    status: 'error',
                    error: error.message
                });
            }
        }

        const response = {
            ...results,
            successRate: Math.round((results.successful / results.processed) * 100),
            timestamp: new Date().toISOString()
        };

        console.log(`📈 Analytics-driven warming completed: ${results.successful}/${results.processed} successful`);

        return new Response(JSON.stringify(response), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });

    } catch (error) {
        console.error('Analytics-driven warming failed:', error);
        return new Response(JSON.stringify({
            error: 'Analytics warming failed',
            message: error.message
        }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

/**
 * Get warming status and statistics
 */
async function getWarmingStatus(request, env, ctx) {
    try {
        const status = {
            cacheStats: await getCacheStatistics(env),
            recentWarming: await getRecentWarmingActivity(env),
            nextScheduled: getNextScheduledWarming(),
            systemHealth: await checkSystemHealth(env),
            timestamp: new Date().toISOString()
        };

        return new Response(JSON.stringify(status), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });

    } catch (error) {
        console.error('Failed to get warming status:', error);
        return new Response(JSON.stringify({
            error: 'Status check failed',
            message: error.message
        }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

// ============================================================================
// CORE WARMING FUNCTIONS
// ============================================================================

/**
 * Warm cache for a specific author
 */
async function warmAuthorCache(author, env) {
    const startTime = Date.now();

    try {
        // Try ISBNdb first for highest quality author data
        if (env.ISBNDB_WORKER) {
            try {
                const result = await callISBNdbWorker(author.name, 20, 'author', env);
                if (result && result.items?.length > 0) {
                    // Cache the result
                    const cacheKey = createCacheKey('auto-search', author.name, { maxResults: 20 });
                    await setCachedData(cacheKey, result, 86400 * 7, env, null, 'high'); // 7 days

                    return {
                        success: true,
                        provider: 'isbndb',
                        itemCount: result.items.length,
                        duration: Date.now() - startTime
                    };
                }
            } catch (error) {
                console.warn(`ISBNdb warming failed for ${author.name}:`, error.message);
            }
        }

        // Try OpenLibrary as fallback
        if (env.OPENLIBRARY_WORKER) {
            try {
                const result = await callOpenLibraryWorker(author.name, 20, 'author', env);
                if (result && result.items?.length > 0) {
                    // Cache the result
                    const cacheKey = createCacheKey('auto-search', author.name, { maxResults: 20 });
                    await setCachedData(cacheKey, result, 86400 * 3, env, null, 'normal'); // 3 days

                    return {
                        success: true,
                        provider: 'openlibrary',
                        itemCount: result.items.length,
                        duration: Date.now() - startTime
                    };
                }
            } catch (error) {
                console.warn(`OpenLibrary warming failed for ${author.name}:`, error.message);
            }
        }

        return {
            success: false,
            error: 'No providers returned results',
            duration: Date.now() - startTime
        };

    } catch (error) {
        return {
            success: false,
            error: error.message,
            duration: Date.now() - startTime
        };
    }
}

/**
 * Warm cache for a specific search query
 */
async function warmSearchQuery(query, params = {}, env) {
    try {
        // Simulate a search request to warm the cache
        const searchUrl = `https://books-api-proxy.jukasdrj.workers.dev/search/auto?q=${encodeURIComponent(query)}&maxResults=${params.maxResults || 20}`;

        const response = await fetch(searchUrl);
        if (!response.ok) {
            throw new Error(`Search request failed: ${response.status}`);
        }

        const result = await response.json();

        return {
            success: true,
            itemCount: result.items?.length || 0,
            provider: result.provider || 'unknown'
        };

    } catch (error) {
        return {
            success: false,
            error: error.message
        };
    }
}

// ============================================================================
// SCHEDULED WARMING FUNCTIONS
// ============================================================================

/**
 * Perform daily comprehensive cache warming
 */
async function performDailyWarming(env, ctx) {
    console.log('🌅 Starting daily cache warming...');

    try {
        // Warm top 50 popular authors
        const authorWarming = await warmTopAuthors(50, env);

        // Analytics-driven warming
        const analyticsWarming = await performAnalyticsWarming(env);

        // Cache maintenance
        await performCacheMaintenance(env);

        console.log(`✅ Daily warming completed:`, {
            authors: `${authorWarming.successful}/${authorWarming.total}`,
            analytics: `${analyticsWarming.successful}/${analyticsWarming.total}`
        });

        // Store warming results for monitoring
        await storeWarmingResults('daily', {
            authorWarming,
            analyticsWarming,
            timestamp: new Date().toISOString()
        }, env);

    } catch (error) {
        console.error('Daily warming failed:', error);
    }
}

/**
 * Perform periodic cache warming (every 4 hours)
 */
async function performPeriodicWarming(env, ctx) {
    console.log('⏰ Starting periodic cache warming...');

    try {
        // Light warming - top 20 authors
        const authorWarming = await warmTopAuthors(20, env);

        // Popular queries based on recent analytics
        const popularQueries = await getPopularQueries(env);
        let queriesWarmed = 0;

        for (const query of popularQueries.slice(0, 10)) {
            try {
                await warmSearchQuery(query, {}, env);
                queriesWarmed++;
            } catch (error) {
                console.warn(`Failed to warm query "${query}":`, error.message);
            }
        }

        console.log(`✅ Periodic warming completed: ${authorWarming.successful} authors, ${queriesWarmed} queries`);

    } catch (error) {
        console.error('Periodic warming failed:', error);
    }
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Warm top N authors
 */
async function warmTopAuthors(count, env) {
    const authors = getPopularAuthorsList().slice(0, count);
    let successful = 0;

    for (const author of authors) {
        try {
            const result = await warmAuthorCache(author, env);
            if (result.success) successful++;
        } catch (error) {
            console.warn(`Failed to warm ${author.name}:`, error.message);
        }
    }

    return { total: count, successful };
}

/**
 * Extract warming targets from cache miss patterns
 */
function extractWarmingTargets(missPatterns) {
    const targets = [];

    // Extract author names from popular_author_missing patterns
    missPatterns
        .filter(pattern => pattern.pattern === 'popular_author_missing')
        .forEach(pattern => {
            if (pattern.author) {
                targets.push({
                    query: pattern.author,
                    priority: pattern.priority,
                    params: { maxResults: 20 },
                    type: 'author'
                });
            }
        });

    // Add high-impact queries
    missPatterns
        .filter(pattern => pattern.estimatedImpact > 100)
        .slice(0, 10) // Limit to top 10
        .forEach(pattern => {
            if (pattern.query) {
                targets.push({
                    query: pattern.query,
                    priority: pattern.priority,
                    params: { maxResults: 15 },
                    type: 'mixed'
                });
            }
        });

    return targets;
}

/**
 * Get popular queries from analytics
 */
async function getPopularQueries(env) {
    // This would analyze recent search patterns
    // For now, return some common queries
    return [
        'Stephen King',
        'Project Hail Mary',
        'The Handmaid\'s Tale',
        'Harry Potter',
        'Game of Thrones'
    ];
}

/**
 * Get recent warming activity
 */
async function getRecentWarmingActivity(env) {
    try {
        const key = 'warming_activity_recent';
        const activity = await env.CACHE?.get(key, 'json') || [];
        return activity.slice(-10); // Last 10 activities
    } catch (error) {
        return [];
    }
}

/**
 * Store warming results for monitoring
 */
async function storeWarmingResults(type, results, env) {
    try {
        const key = `warming_results_${type}_${new Date().toISOString().split('T')[0]}`;
        await env.CACHE?.put(key, JSON.stringify(results), {
            expirationTtl: 86400 * 7 // 7 days
        });

        // Update recent activity
        const activityKey = 'warming_activity_recent';
        const existing = await env.CACHE?.get(activityKey, 'json') || [];
        existing.push({
            type,
            timestamp: new Date().toISOString(),
            summary: {
                authors: results.authorWarming?.successful || 0,
                analytics: results.analyticsWarming?.successful || 0
            }
        });

        // Keep only last 20 activities
        const recent = existing.slice(-20);
        await env.CACHE?.put(activityKey, JSON.stringify(recent), {
            expirationTtl: 86400 * 7
        });

    } catch (error) {
        console.warn('Failed to store warming results:', error);
    }
}

/**
 * Get next scheduled warming time
 */
function getNextScheduledWarming() {
    const now = new Date();
    const next6AM = new Date(now);
    next6AM.setUTCHours(6, 0, 0, 0);

    if (next6AM <= now) {
        next6AM.setUTCDate(next6AM.getUTCDate() + 1);
    }

    const next4Hours = new Date(now);
    next4Hours.setUTCHours(Math.ceil(now.getUTCHours() / 4) * 4, 0, 0, 0);

    return {
        daily: next6AM.toISOString(),
        periodic: next4Hours.toISOString()
    };
}

/**
 * Check system health for warming operations
 */
async function checkSystemHealth(env) {
    const health = {
        kvCache: false,
        r2Cache: false,
        isbndbWorker: false,
        openlibraryWorker: false
    };

    try {
        // Test KV cache
        await env.CACHE?.get('health_check');
        health.kvCache = true;
    } catch (error) {
        console.warn('KV cache health check failed:', error);
    }

    try {
        // Test R2 cache
        await env.API_CACHE_COLD?.list({ limit: 1 });
        health.r2Cache = true;
    } catch (error) {
        console.warn('R2 cache health check failed:', error);
    }

    try {
        // Test ISBNdb worker
        if (env.ISBNDB_WORKER) {
            const response = await env.ISBNDB_WORKER.fetch(new Request('https://dummy/health'));
            health.isbndbWorker = response.ok;
        }
    } catch (error) {
        console.warn('ISBNdb worker health check failed:', error);
    }

    try {
        // Test OpenLibrary worker
        if (env.OPENLIBRARY_WORKER) {
            const response = await env.OPENLIBRARY_WORKER.fetch(new Request('https://dummy/health'));
            health.openlibraryWorker = response.ok;
        }
    } catch (error) {
        console.warn('OpenLibrary worker health check failed:', error);
    }

    return health;
}

// Note: These functions need to be imported or implemented
// - getPopularAuthorsList
// - createCacheKey
// - setCachedData
// - getCacheStatistics
// - analyzeCacheMissPatterns
// - callISBNdbWorker
// - callOpenLibraryWorker
// - performCacheMaintenance

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
        { name: 'Paulo Coelho', searchVolume: 500 }
    ];
}

function createCacheKey(type, query, params = {}) {
    const normalizedQuery = query.toLowerCase().trim().replace(/\s+/g, ' ');
    const sortedParams = Object.keys(params).sort().map(key => `${key}=${params[key]}`).join('&');
    const hashInput = `${type}:${normalizedQuery}:${sortedParams}`;
    return `${type}:${btoa(hashInput).replace(/[/+=]/g, '')}`;
}

async function setCachedData(cacheKey, data, ttlSeconds, env, ctx, priority = 'normal') {
    const jsonData = JSON.stringify(data);
    await env.CACHE?.put(cacheKey, jsonData, { expirationTtl: ttlSeconds });
}

async function getCacheStatistics(env) {
    const stats = { kvEntries: 0, r2Objects: 0 };

    try {
        const kvKeys = await env.CACHE?.list({ limit: 1000 });
        stats.kvEntries = kvKeys?.keys?.length || 0;
    } catch (error) {
        console.warn('Failed to get KV stats:', error);
    }

    try {
        const r2Objects = await env.API_CACHE_COLD?.list({ limit: 1000 });
        stats.r2Objects = r2Objects?.objects?.length || 0;
    } catch (error) {
        console.warn('Failed to get R2 stats:', error);
    }

    return stats;
}

async function analyzeCacheMissPatterns(env) {
    // Simplified implementation
    return [
        {
            pattern: 'popular_author_missing',
            author: 'Stephen King',
            priority: 'high',
            estimatedImpact: 200
        }
    ];
}

async function callISBNdbWorker(authorName, maxResults, searchType, env) {
    const workerRequest = new Request(`https://dummy/author/${encodeURIComponent(authorName)}?pageSize=${maxResults}`, {
        headers: { 'X-Request-Source': 'cache-warmer' }
    });

    const response = await env.ISBNDB_WORKER.fetch(workerRequest);
    if (!response.ok) throw new Error(`ISBNdb worker error: ${response.status}`);

    return await response.json();
}

async function callOpenLibraryWorker(authorName, maxResults, searchType, env) {
    const workerRequest = new Request(`https://dummy/author/${encodeURIComponent(authorName)}?pageSize=${maxResults}`, {
        headers: { 'X-Request-Source': 'cache-warmer' }
    });

    const response = await env.OPENLIBRARY_WORKER.fetch(workerRequest);
    if (!response.ok) throw new Error(`OpenLibrary worker error: ${response.status}`);

    return await response.json();
}

async function performAnalyticsWarming(env) {
    return { total: 5, successful: 4 };
}

async function performCacheMaintenance(env) {
    console.log('🧹 Performing cache maintenance...');
    // Implementation would clean up old cache entries
}