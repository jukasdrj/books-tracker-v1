/**
 * 🚀 Cloudflare Workers Structured Logging Infrastructure
 * Comprehensive logging system for performance monitoring, cache analysis, and debugging
 */

// === LOGGING LEVELS ===
const LOG_LEVELS = {
  ERROR: 0,
  WARN: 1,
  INFO: 2,
  DEBUG: 3
};

// === STRUCTURED LOGGER CLASS ===
class StructuredLogger {
  constructor(workerName, env) {
    this.workerName = workerName;
    this.env = env;
    this.logLevel = this.getLogLevel();
    this.enabledFeatures = this.getEnabledFeatures();
  }

  getLogLevel() {
    const level = this.env.LOG_LEVEL || 'INFO';
    return LOG_LEVELS[level] || LOG_LEVELS.INFO;
  }

  getEnabledFeatures() {
    return {
      performance: this.env.ENABLE_PERFORMANCE_LOGGING === 'true',
      cache: this.env.ENABLE_CACHE_ANALYTICS === 'true',
      provider: this.env.ENABLE_PROVIDER_METRICS === 'true',
      structured: this.env.STRUCTURED_LOGGING === 'true',
      rateLimit: this.env.ENABLE_RATE_LIMIT_TRACKING === 'true'
    };
  }

  // === PERFORMANCE LOGGING ===
  async logPerformance(operation, duration, metadata = {}) {
    if (!this.enabledFeatures.performance) return;

    const performanceLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'performance',
      operation,
      duration_ms: duration,
      metadata
    };

    // Log to console for real-time monitoring
    console.log(`🚀 PERF [${this.workerName}] ${operation}: ${duration}ms`, metadata);

    // Send to Analytics Engine if available
    if (this.env.PERFORMANCE_ANALYTICS) {
      try {
        await this.env.PERFORMANCE_ANALYTICS.writeDataPoint({
          blobs: [operation, this.workerName],
          doubles: [duration],
          indexes: [performanceLog.timestamp]
        });
      } catch (error) {
        console.error('Failed to write performance analytics:', error);
      }
    }

    return performanceLog;
  }

  // === CACHE ANALYTICS ===
  async logCacheOperation(operation, key, hit, responseTime, size = 0) {
    if (!this.enabledFeatures.cache) return;

    const cacheLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'cache',
      operation, // 'get', 'set', 'delete', 'miss'
      key,
      hit: hit ? 1 : 0,
      response_time_ms: responseTime,
      size_bytes: size
    };

    // Structured console logging
    const status = hit ? '✅ HIT' : '❌ MISS';
    console.log(`📊 CACHE [${this.workerName}] ${status} ${operation} ${key} (${responseTime}ms, ${size}b)`);

    // Send to Analytics Engine
    if (this.env.CACHE_ANALYTICS) {
      try {
        await this.env.CACHE_ANALYTICS.writeDataPoint({
          blobs: [operation, key, this.workerName],
          doubles: [hit ? 1 : 0, responseTime, size],
          indexes: [cacheLog.timestamp]
        });
      } catch (error) {
        console.error('Failed to write cache analytics:', error);
      }
    }

    return cacheLog;
  }

  // === PROVIDER PERFORMANCE ===
  async logProviderPerformance(provider, operation, success, responseTime, errorCode = null) {
    if (!this.enabledFeatures.provider) return;

    const providerLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'provider',
      provider, // 'isbndb', 'openlibrary', 'googlebooks'
      operation,
      success: success ? 1 : 0,
      response_time_ms: responseTime,
      error_code: errorCode
    };

    const status = success ? '✅ SUCCESS' : '❌ FAILED';
    const errorInfo = errorCode ? ` (${errorCode})` : '';
    console.log(`🌐 PROVIDER [${this.workerName}] ${status} ${provider}/${operation}: ${responseTime}ms${errorInfo}`);

    // Send to Analytics Engine
    if (this.env.PROVIDER_ANALYTICS) {
      try {
        await this.env.PROVIDER_ANALYTICS.writeDataPoint({
          blobs: [provider, operation, this.workerName, errorCode || 'none'],
          doubles: [success ? 1 : 0, responseTime],
          indexes: [providerLog.timestamp]
        });
      } catch (error) {
        console.error('Failed to write provider analytics:', error);
      }
    }

    return providerLog;
  }

  // === CACHE MISS ANALYSIS ===
  async logCacheMiss(query, reason, expectedLocation, actualLocation = null) {
    const cacheMissLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'cache_miss_analysis',
      query,
      reason, // 'not_found', 'expired', 'corrupted', 'author_not_cached'
      expected_location: expectedLocation,
      actual_location: actualLocation
    };

    console.log(`🔍 CACHE MISS ANALYSIS [${this.workerName}]`, {
      query,
      reason,
      expectedLocation,
      actualLocation
    });

    // This is critical for debugging - always send to analytics
    if (this.env.CACHE_ANALYTICS) {
      try {
        await this.env.CACHE_ANALYTICS.writeDataPoint({
          blobs: [query, reason, expectedLocation, actualLocation || 'none'],
          doubles: [1], // count
          indexes: [cacheMissLog.timestamp]
        });
      } catch (error) {
        console.error('Failed to write cache miss analytics:', error);
      }
    }

    return cacheMissLog;
  }

  // === ERROR LOGGING ===
  logError(operation, error, context = {}) {
    const errorLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'error',
      operation,
      error: error.message,
      stack: error.stack,
      context
    };

    console.error(`❌ ERROR [${this.workerName}] ${operation}:`, error, context);
    return errorLog;
  }

  // === RATE LIMIT TRACKING ===
  async logRateLimit(provider, remaining, reset, used) {
    if (!this.enabledFeatures.rateLimit) return;

    const rateLimitLog = {
      timestamp: new Date().toISOString(),
      worker: this.workerName,
      type: 'rate_limit',
      provider,
      remaining,
      reset,
      used
    };

    console.log(`⚡ RATE LIMIT [${this.workerName}] ${provider}: ${remaining} remaining (${used} used)`);

    // Store in KV for cross-worker rate limit awareness
    if (this.env.CACHE) {
      try {
        await this.env.CACHE.put(`rate_limit_${provider}`, JSON.stringify(rateLimitLog), {
          expirationTtl: reset
        });
      } catch (error) {
        console.error('Failed to store rate limit data:', error);
      }
    }

    return rateLimitLog;
  }

  // === STEPHEN KING CACHE INVESTIGATION ===
  async investigateStephenKingCache() {
    console.log('🔍 STEPHEN KING CACHE INVESTIGATION STARTING...');

    const searchQueries = [
      'stephen king',
      'Stephen King',
      'STEPHEN KING',
      'king stephen',
      'King Stephen'
    ];

    const results = [];

    for (const query of searchQueries) {
      const investigation = {
        query,
        timestamp: new Date().toISOString(),
        cacheResults: {}
      };

      // Check KV cache
      if (this.env.CACHE) {
        try {
          const kvResult = await this.env.CACHE.get(`author_biography_${query.toLowerCase().replace(/\s+/g, '_')}`);
          investigation.cacheResults.kv = kvResult ? 'FOUND' : 'NOT_FOUND';
        } catch (error) {
          investigation.cacheResults.kv = `ERROR: ${error.message}`;
        }
      }

      // Check R2 cold storage
      if (this.env.LIBRARY_DATA) {
        try {
          const r2Result = await this.env.LIBRARY_DATA.get(`author_${query.toLowerCase().replace(/\s+/g, '_')}.json`);
          investigation.cacheResults.r2 = r2Result ? 'FOUND' : 'NOT_FOUND';
        } catch (error) {
          investigation.cacheResults.r2 = `ERROR: ${error.message}`;
        }
      }

      results.push(investigation);
      console.log(`🔍 Stephen King Query: "${query}"`, investigation.cacheResults);
    }

    // Log comprehensive investigation results
    console.log('🔍 STEPHEN KING CACHE INVESTIGATION COMPLETE:', results);
    return results;
  }
}

// === PERFORMANCE TIMER UTILITY ===
class PerformanceTimer {
  constructor(logger, operation) {
    this.logger = logger;
    this.operation = operation;
    this.startTime = Date.now();
  }

  async end(metadata = {}) {
    const duration = Date.now() - this.startTime;
    await this.logger.logPerformance(this.operation, duration, metadata);
    return duration;
  }
}

// === CACHE PERFORMANCE MONITOR ===
class CachePerformanceMonitor {
  constructor(logger) {
    this.logger = logger;
    this.metrics = {
      hits: 0,
      misses: 0,
      totalResponseTime: 0,
      operations: 0
    };
  }

  async recordCacheOperation(operation, key, hit, responseTime, size = 0) {
    this.metrics.operations++;
    this.metrics.totalResponseTime += responseTime;

    if (hit) {
      this.metrics.hits++;
    } else {
      this.metrics.misses++;
    }

    await this.logger.logCacheOperation(operation, key, hit, responseTime, size);
  }

  getStats() {
    const hitRate = this.metrics.operations > 0 ?
      (this.metrics.hits / this.metrics.operations * 100).toFixed(2) : 0;

    const avgResponseTime = this.metrics.operations > 0 ?
      (this.metrics.totalResponseTime / this.metrics.operations).toFixed(2) : 0;

    return {
      hitRate: `${hitRate}%`,
      avgResponseTime: `${avgResponseTime}ms`,
      totalOperations: this.metrics.operations,
      hits: this.metrics.hits,
      misses: this.metrics.misses
    };
  }
}

// === PROVIDER HEALTH MONITOR ===
class ProviderHealthMonitor {
  constructor(logger) {
    this.logger = logger;
    this.providers = new Map();
  }

  async recordProviderCall(provider, operation, success, responseTime, errorCode = null) {
    if (!this.providers.has(provider)) {
      this.providers.set(provider, {
        totalCalls: 0,
        successfulCalls: 0,
        totalResponseTime: 0,
        errors: new Map()
      });
    }

    const stats = this.providers.get(provider);
    stats.totalCalls++;
    stats.totalResponseTime += responseTime;

    if (success) {
      stats.successfulCalls++;
    } else if (errorCode) {
      stats.errors.set(errorCode, (stats.errors.get(errorCode) || 0) + 1);
    }

    await this.logger.logProviderPerformance(provider, operation, success, responseTime, errorCode);
  }

  getProviderStats(provider) {
    const stats = this.providers.get(provider);
    if (!stats) return null;

    const successRate = (stats.successfulCalls / stats.totalCalls * 100).toFixed(2);
    const avgResponseTime = (stats.totalResponseTime / stats.totalCalls).toFixed(2);

    return {
      provider,
      successRate: `${successRate}%`,
      avgResponseTime: `${avgResponseTime}ms`,
      totalCalls: stats.totalCalls,
      errors: Object.fromEntries(stats.errors)
    };
  }

  getAllProviderStats() {
    const allStats = {};
    for (const provider of this.providers.keys()) {
      allStats[provider] = this.getProviderStats(provider);
    }
    return allStats;
  }
}

// === EXPORT UTILITIES ===
export {
  StructuredLogger,
  PerformanceTimer,
  CachePerformanceMonitor,
  ProviderHealthMonitor,
  LOG_LEVELS
};

// === USAGE EXAMPLES ===
/*
// Initialize in worker
const logger = new StructuredLogger('books-api-proxy', env);
const cacheMonitor = new CachePerformanceMonitor(logger);
const providerMonitor = new ProviderHealthMonitor(logger);

// Performance timing
const timer = new PerformanceTimer(logger, 'search_operation');
// ... perform operation
await timer.end({ query: 'stephen king', results: 25 });

// Cache monitoring
await cacheMonitor.recordCacheOperation('get', 'author_stephen_king', true, 45, 2048);

// Provider monitoring
await providerMonitor.recordProviderCall('isbndb', 'author_search', true, 1200);

// Error logging
logger.logError('api_call_failed', error, { provider: 'isbndb', query: 'test' });

// Cache miss investigation
await logger.logCacheMiss('stephen king', 'author_not_cached', 'KV:author_stephen_king');

// Stephen King specific investigation
await logger.investigateStephenKingCache();
*/