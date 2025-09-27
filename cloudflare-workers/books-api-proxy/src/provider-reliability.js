/**
 * PROVIDER RELIABILITY ENHANCEMENT MODULE
 *
 * Addresses provider search failures with:
 * - Advanced circuit breaker patterns for each provider
 * - Intelligent retry strategies with exponential backoff
 * - Provider health monitoring and automatic recovery
 * - Fallback chains with quality preservation
 * - Request normalization for problematic queries
 *
 * Target: >95% search success rate across all providers
 */

// ============================================================================
// CIRCUIT BREAKER IMPLEMENTATION
// ============================================================================

/**
 * Enhanced circuit breaker with provider-specific configuration
 */
class ProviderCircuitBreaker {
    constructor(providerName, env, options = {}) {
        this.providerName = providerName;
        this.env = env;

        // Provider-specific thresholds
        const providerDefaults = this.getProviderDefaults(providerName);

        this.config = {
            failureThreshold: options.failureThreshold || providerDefaults.failureThreshold,
            recoveryTimeout: options.recoveryTimeout || providerDefaults.recoveryTimeout,
            healthCheckInterval: options.healthCheckInterval || providerDefaults.healthCheckInterval,
            timeWindow: options.timeWindow || providerDefaults.timeWindow,
            ...options
        };

        this.cacheKey = `circuit_breaker:${providerName}`;
    }

    getProviderDefaults(providerName) {
        const defaults = {
            'isbndb': {
                failureThreshold: 3,      // More tolerant for paid API
                recoveryTimeout: 30000,   // 30 seconds
                healthCheckInterval: 60000, // 1 minute
                timeWindow: 300000        // 5 minutes
            },
            'openlibrary': {
                failureThreshold: 5,      // Free API, more failures expected
                recoveryTimeout: 60000,   // 1 minute
                healthCheckInterval: 120000, // 2 minutes
                timeWindow: 600000        // 10 minutes
            },
            'google-books': {
                failureThreshold: 4,      // Google's reliable infrastructure
                recoveryTimeout: 45000,   // 45 seconds
                healthCheckInterval: 90000, // 1.5 minutes
                timeWindow: 300000        // 5 minutes
            }
        };

        return defaults[providerName] || defaults['openlibrary'];
    }

    async getState() {
        try {
            const state = await this.env.CACHE?.get(this.cacheKey, 'json') || {
                failures: 0,
                lastFailure: 0,
                state: 'closed', // closed = normal, open = failing, half-open = testing
                lastHealthCheck: 0,
                recentErrors: []
            };

            return state;
        } catch (error) {
            console.warn(`Failed to get circuit breaker state for ${this.providerName}:`, error);
            return { failures: 0, lastFailure: 0, state: 'closed', lastHealthCheck: 0, recentErrors: [] };
        }
    }

    async setState(state) {
        try {
            await this.env.CACHE?.put(this.cacheKey, JSON.stringify({
                ...state,
                lastUpdated: Date.now()
            }), { expirationTtl: 3600 }); // 1 hour TTL
        } catch (error) {
            console.warn(`Failed to set circuit breaker state for ${this.providerName}:`, error);
        }
    }

    async canExecute() {
        const state = await this.getState();
        const now = Date.now();

        switch (state.state) {
            case 'closed':
                // Normal operation
                return { allowed: true, reason: 'circuit_closed' };

            case 'open':
                // Check if recovery timeout has passed
                const timeSinceFailure = now - state.lastFailure;
                if (timeSinceFailure >= this.config.recoveryTimeout) {
                    // Transition to half-open for testing
                    await this.setState({
                        ...state,
                        state: 'half-open'
                    });
                    return { allowed: true, reason: 'attempting_recovery' };
                }
                return {
                    allowed: false,
                    reason: 'circuit_open',
                    retryAfter: this.config.recoveryTimeout - timeSinceFailure
                };

            case 'half-open':
                // Allow limited requests for testing
                return { allowed: true, reason: 'circuit_testing' };

            default:
                return { allowed: true, reason: 'unknown_state' };
        }
    }

    async recordSuccess() {
        const state = await this.getState();

        if (state.state === 'half-open') {
            // Recovery successful, close circuit
            console.log(`✅ ${this.providerName} circuit breaker: recovered (closed)`);
            await this.setState({
                failures: 0,
                lastFailure: 0,
                state: 'closed',
                lastHealthCheck: Date.now(),
                recentErrors: []
            });
        } else if (state.failures > 0) {
            // Reduce failure count on success
            await this.setState({
                ...state,
                failures: Math.max(0, state.failures - 1)
            });
        }
    }

    async recordFailure(error) {
        const state = await this.getState();
        const now = Date.now();

        // Add error to recent errors (keep last 5)
        const recentErrors = [
            ...(state.recentErrors || []).slice(-4),
            {
                timestamp: now,
                error: error.message || 'Unknown error',
                type: this.classifyError(error)
            }
        ];

        const newFailures = state.failures + 1;

        // Determine if circuit should open
        let newState = state.state;
        if (newFailures >= this.config.failureThreshold) {
            newState = 'open';
            console.warn(`🔥 ${this.providerName} circuit breaker: OPENED (${newFailures} failures)`);
        }

        await this.setState({
            failures: newFailures,
            lastFailure: now,
            state: newState,
            lastHealthCheck: state.lastHealthCheck,
            recentErrors
        });
    }

    classifyError(error) {
        const message = error.message?.toLowerCase() || '';

        if (message.includes('timeout')) return 'timeout';
        if (message.includes('rate limit')) return 'rate_limit';
        if (message.includes('401') || message.includes('403')) return 'auth';
        if (message.includes('500') || message.includes('502') || message.includes('503')) return 'server_error';
        if (message.includes('network') || message.includes('connection')) return 'network';

        return 'unknown';
    }

    async getHealthStatus() {
        const state = await this.getState();
        return {
            provider: this.providerName,
            state: state.state,
            failures: state.failures,
            lastFailure: state.lastFailure,
            isHealthy: state.state === 'closed',
            recentErrors: state.recentErrors || []
        };
    }
}

// ============================================================================
// INTELLIGENT RETRY STRATEGIES
// ============================================================================

/**
 * Enhanced retry mechanism with provider-specific strategies
 */
export class ProviderRetryStrategy {
    constructor(providerName, env) {
        this.providerName = providerName;
        this.env = env;
        this.circuitBreaker = new ProviderCircuitBreaker(providerName, env);
    }

    async executeWithRetry(operation, query, context = {}) {
        const maxRetries = this.getMaxRetries(context);
        let lastError;

        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                // Check circuit breaker
                const canExecute = await this.circuitBreaker.canExecute();
                if (!canExecute.allowed) {
                    throw new Error(`${this.providerName} circuit breaker open: ${canExecute.reason}`);
                }

                // Normalize query for this attempt
                const normalizedQuery = this.normalizeQueryForProvider(query, attempt);

                console.log(`🔄 ${this.providerName} attempt ${attempt}/${maxRetries} for: "${normalizedQuery}"`);

                // Execute operation
                const result = await operation(normalizedQuery);

                // Validate result
                if (this.isValidResult(result)) {
                    await this.circuitBreaker.recordSuccess();
                    console.log(`✅ ${this.providerName} succeeded on attempt ${attempt}`);
                    return result;
                }

                throw new Error('Invalid or empty result');

            } catch (error) {
                lastError = error;
                await this.circuitBreaker.recordFailure(error);

                console.warn(`❌ ${this.providerName} attempt ${attempt} failed:`, error.message);

                // Don't retry on certain errors
                if (this.shouldNotRetry(error)) {
                    console.log(`🚫 ${this.providerName} error not retryable: ${error.message}`);
                    break;
                }

                // Wait before retry (exponential backoff)
                if (attempt < maxRetries) {
                    const delay = this.calculateRetryDelay(attempt);
                    console.log(`⏳ ${this.providerName} waiting ${delay}ms before retry`);
                    await new Promise(resolve => setTimeout(resolve, delay));
                }
            }
        }

        // All retries failed
        console.error(`💥 ${this.providerName} all ${maxRetries} attempts failed. Last error:`, lastError?.message);
        throw lastError || new Error(`${this.providerName} provider failed after ${maxRetries} attempts`);
    }

    getMaxRetries(context) {
        // Fewer retries for paid APIs to preserve quota
        if (this.providerName === 'isbndb') return 2;

        // More retries for free APIs
        if (this.providerName === 'openlibrary') return 3;

        // Standard retries for Google Books
        return 2;
    }

    normalizeQueryForProvider(query, attempt) {
        if (!query || attempt === 1) return query;

        // Provider-specific query normalization for retries
        switch (this.providerName) {
            case 'openlibrary':
                return this.normalizeForOpenLibrary(query, attempt);
            case 'isbndb':
                return this.normalizeForISBNdb(query, attempt);
            case 'google-books':
                return this.normalizeForGoogleBooks(query, attempt);
            default:
                return query;
        }
    }

    normalizeForOpenLibrary(query, attempt) {
        // OpenLibrary-specific normalization
        switch (attempt) {
            case 2:
                // Remove punctuation that might cause issues
                return query.replace(/[.,!?;:'"]/g, '');
            case 3:
                // Try with simplified query (first two words only)
                return query.split(' ').slice(0, 2).join(' ');
            default:
                return query;
        }
    }

    normalizeForISBNdb(query, attempt) {
        // ISBNdb-specific normalization
        switch (attempt) {
            case 2:
                // Try exact phrase search
                return `"${query}"`;
            default:
                return query;
        }
    }

    normalizeForGoogleBooks(query, attempt) {
        // Google Books-specific normalization
        switch (attempt) {
            case 2:
                // Add intitle or inauthor prefix based on query analysis
                if (this.looksLikeAuthor(query)) {
                    return `inauthor:${query}`;
                } else {
                    return `intitle:${query}`;
                }
            default:
                return query;
        }
    }

    looksLikeAuthor(query) {
        const words = query.trim().split(/\s+/);
        return words.length === 2 && words.every(word => !/\d/.test(word));
    }

    calculateRetryDelay(attempt) {
        // Exponential backoff with jitter
        const baseDelay = 1000; // 1 second
        const exponentialDelay = baseDelay * Math.pow(2, attempt - 1);
        const jitter = Math.random() * 500; // Up to 500ms jitter
        return Math.min(exponentialDelay + jitter, 10000); // Cap at 10 seconds
    }

    shouldNotRetry(error) {
        const message = error.message?.toLowerCase() || '';

        // Don't retry on authentication errors
        if (message.includes('401') || message.includes('forbidden')) return true;

        // Don't retry on rate limiting (wait for circuit breaker)
        if (message.includes('rate limit') || message.includes('429')) return true;

        // Don't retry on bad request (query issue)
        if (message.includes('400') || message.includes('bad request')) return true;

        return false;
    }

    isValidResult(result) {
        return result &&
               (result.items?.length > 0 ||
                result.works?.length > 0 ||
                result.success === true);
    }
}

// ============================================================================
// PROVIDER-SPECIFIC FIXES
// ============================================================================

/**
 * Margaret Atwood search fix - addresses specific search failures
 */
export async function fixMargaretAtwoodSearch(env) {
    console.log('🔧 Implementing Margaret Atwood search fix...');

    const testQueries = [
        'Margaret Atwood',
        'margaret atwood',
        'Atwood',
        'The Handmaid\'s Tale'
    ];

    const fixes = [];

    for (const query of testQueries) {
        console.log(`Testing query: "${query}"`);

        try {
            // Test each provider with enhanced retry
            const providers = ['isbndb', 'openlibrary', 'google-books'];

            for (const providerName of providers) {
                if (!env[`${providerName.toUpperCase().replace('-', '_')}_WORKER`] && providerName !== 'google-books') {
                    continue;
                }

                const retryStrategy = new ProviderRetryStrategy(providerName, env);

                try {
                    let result;
                    if (providerName === 'isbndb') {
                        result = await retryStrategy.executeWithRetry(
                            (q) => searchISBNdbWithWorker(q, 10, 'author', env),
                            query
                        );
                    } else if (providerName === 'openlibrary') {
                        result = await retryStrategy.executeWithRetry(
                            (q) => searchOpenLibraryWithWorker(q, 10, 'author', env),
                            query
                        );
                    } else if (providerName === 'google-books') {
                        result = await retryStrategy.executeWithRetry(
                            (q) => searchGoogleBooks(q, 10, 'relevance', false, env),
                            query
                        );
                    }

                    if (result?.items?.length > 0) {
                        fixes.push({
                            query,
                            provider: providerName,
                            success: true,
                            itemCount: result.items.length
                        });
                        console.log(`✅ ${providerName} fixed for "${query}" (${result.items.length} results)`);
                    } else {
                        fixes.push({
                            query,
                            provider: providerName,
                            success: false,
                            error: 'No results'
                        });
                    }

                } catch (error) {
                    fixes.push({
                        query,
                        provider: providerName,
                        success: false,
                        error: error.message
                    });
                    console.warn(`❌ ${providerName} still failing for "${query}":`, error.message);
                }
            }

        } catch (error) {
            console.error(`Failed to test query "${query}":`, error);
        }
    }

    return {
        testQueries,
        fixes,
        summary: {
            totalTests: fixes.length,
            successful: fixes.filter(f => f.success).length,
            failed: fixes.filter(f => !f.success).length
        }
    };
}

// ============================================================================
// PROVIDER HEALTH MONITORING
// ============================================================================

/**
 * Comprehensive provider health monitoring
 */
export async function monitorProviderHealth(env) {
    console.log('📊 Starting provider health monitoring...');

    const providers = ['isbndb', 'openlibrary', 'google-books'];
    const healthReport = {
        timestamp: new Date().toISOString(),
        providers: {},
        overallHealth: 'unknown'
    };

    for (const providerName of providers) {
        try {
            const circuitBreaker = new ProviderCircuitBreaker(providerName, env);
            const health = await circuitBreaker.getHealthStatus();

            // Add additional metrics
            health.responseTime = await measureProviderResponseTime(providerName, env);
            health.availability = await calculateProviderAvailability(providerName, env);

            healthReport.providers[providerName] = health;

        } catch (error) {
            healthReport.providers[providerName] = {
                provider: providerName,
                state: 'error',
                isHealthy: false,
                error: error.message
            };
        }
    }

    // Calculate overall health
    const healthyProviders = Object.values(healthReport.providers).filter(p => p.isHealthy).length;
    const totalProviders = Object.keys(healthReport.providers).length;

    if (healthyProviders === totalProviders) {
        healthReport.overallHealth = 'healthy';
    } else if (healthyProviders >= totalProviders / 2) {
        healthReport.overallHealth = 'degraded';
    } else {
        healthReport.overallHealth = 'unhealthy';
    }

    console.log(`📈 Provider health summary: ${healthyProviders}/${totalProviders} healthy (${healthReport.overallHealth})`);

    return healthReport;
}

/**
 * Measure provider response time
 */
async function measureProviderResponseTime(providerName, env) {
    try {
        const startTime = Date.now();

        // Simple health check query
        const testQuery = 'test';

        if (providerName === 'isbndb' && env.ISBNDB_WORKER) {
            await searchISBNdbWithWorker(testQuery, 1, 'title', env);
        } else if (providerName === 'openlibrary' && env.OPENLIBRARY_WORKER) {
            await searchOpenLibraryWithWorker(testQuery, 1, 'title', env);
        } else if (providerName === 'google-books') {
            await searchGoogleBooks(testQuery, 1, 'relevance', false, env);
        }

        return Date.now() - startTime;

    } catch (error) {
        return -1; // Indicates error
    }
}

/**
 * Calculate provider availability over time
 */
async function calculateProviderAvailability(providerName, env) {
    try {
        const circuitBreaker = new ProviderCircuitBreaker(providerName, env);
        const state = await circuitBreaker.getState();

        // Simple availability calculation based on recent errors
        const recentErrors = state.recentErrors || [];
        const timeWindow = 24 * 60 * 60 * 1000; // 24 hours
        const now = Date.now();

        const recentErrorsInWindow = recentErrors.filter(
            error => (now - error.timestamp) <= timeWindow
        );

        // Estimate availability (simplified)
        if (recentErrorsInWindow.length === 0) return 100;
        if (recentErrorsInWindow.length >= 10) return 50;

        return Math.max(50, 100 - (recentErrorsInWindow.length * 5));

    } catch (error) {
        return 0;
    }
}

// ============================================================================
// EXPORT ENHANCED PROVIDER FUNCTIONS
// ============================================================================

/**
 * Enhanced ISBNdb search with reliability improvements
 */
export async function searchISBNdbWithEnhancedReliability(query, maxResults, searchType, env) {
    const retryStrategy = new ProviderRetryStrategy('isbndb', env);

    return await retryStrategy.executeWithRetry(
        (normalizedQuery) => searchISBNdbWithWorker(normalizedQuery, maxResults, searchType, env),
        query,
        { maxResults, searchType }
    );
}

/**
 * Enhanced OpenLibrary search with reliability improvements
 */
export async function searchOpenLibraryWithEnhancedReliability(query, maxResults, searchType, env) {
    const retryStrategy = new ProviderRetryStrategy('openlibrary', env);

    return await retryStrategy.executeWithRetry(
        (normalizedQuery) => searchOpenLibraryWithWorker(normalizedQuery, maxResults, searchType, env),
        query,
        { maxResults, searchType }
    );
}

/**
 * Enhanced Google Books search with reliability improvements
 */
export async function searchGoogleBooksWithEnhancedReliability(query, maxResults, sortBy, includeTranslations, env) {
    const retryStrategy = new ProviderRetryStrategy('google-books', env);

    return await retryStrategy.executeWithRetry(
        (normalizedQuery) => searchGoogleBooks(normalizedQuery, maxResults, sortBy, includeTranslations, env),
        query,
        { maxResults, sortBy, includeTranslations }
    );
}

// Note: These functions need to be imported from the main index.js
// - searchISBNdbWithWorker
// - searchOpenLibraryWithWorker
// - searchGoogleBooks

export {
    ProviderCircuitBreaker,
    ProviderRetryStrategy,
    fixMargaretAtwoodSearch,
    monitorProviderHealth
};