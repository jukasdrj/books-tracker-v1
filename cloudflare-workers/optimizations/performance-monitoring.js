/**
 * Advanced Performance Monitoring & Analytics
 *
 * Comprehensive monitoring system for the modular worker architecture:
 * 1. Real-time performance tracking
 * 2. Service binding health monitoring
 * 3. Cache efficiency analytics
 * 4. Automated optimization recommendations
 */

// ============================================================================
// Performance Tracking System
// ============================================================================

class AdvancedPerformanceTracker {
    constructor() {
        this.activeTrackers = new Map();
        this.completedMetrics = [];
        this.thresholds = {
            excellent: 100,  // <100ms
            good: 200,       // <200ms
            acceptable: 500, // <500ms
            poor: 1000,      // <1000ms
            critical: 2000   // <2000ms
        };
    }

    /**
     * Start tracking a performance operation
     */
    startOperation(operationId, metadata = {}) {
        this.activeTrackers.set(operationId, {
            startTime: Date.now(),
            startMemory: this.getMemoryUsage(),
            metadata,
            checkpoints: []
        });
    }

    /**
     * Add checkpoint during operation
     */
    checkpoint(operationId, checkpointName, data = {}) {
        const tracker = this.activeTrackers.get(operationId);
        if (tracker) {
            tracker.checkpoints.push({
                name: checkpointName,
                timestamp: Date.now(),
                duration: Date.now() - tracker.startTime,
                data
            });
        }
    }

    /**
     * Complete tracking and calculate metrics
     */
    endOperation(operationId, result = {}) {
        const tracker = this.activeTrackers.get(operationId);
        if (!tracker) return null;

        const endTime = Date.now();
        const totalDuration = endTime - tracker.startTime;
        const endMemory = this.getMemoryUsage();

        const metrics = {
            operationId,
            totalDuration,
            memoryUsage: endMemory - tracker.startMemory,
            performanceRating: this.calculatePerformanceRating(totalDuration),
            checkpoints: tracker.checkpoints,
            metadata: tracker.metadata,
            result: {
                success: result.success !== false,
                itemCount: result.items?.length || result.works?.length || 0,
                provider: result.provider,
                cached: result.cached || false,
                cacheSource: result.cacheSource
            },
            timestamp: endTime
        };

        this.completedMetrics.push(metrics);
        this.activeTrackers.delete(operationId);

        // Keep only last 100 metrics in memory
        if (this.completedMetrics.length > 100) {
            this.completedMetrics = this.completedMetrics.slice(-100);
        }

        return metrics;
    }

    /**
     * Calculate performance rating
     */
    calculatePerformanceRating(duration) {
        if (duration <= this.thresholds.excellent) return 'excellent';
        if (duration <= this.thresholds.good) return 'good';
        if (duration <= this.thresholds.acceptable) return 'acceptable';
        if (duration <= this.thresholds.poor) return 'poor';
        return 'critical';
    }

    /**
     * Get memory usage (simplified for Cloudflare Workers)
     */
    getMemoryUsage() {
        // In Cloudflare Workers, we can't directly measure memory
        // This is a placeholder for potential future capabilities
        return 0;
    }

    /**
     * Get performance summary
     */
    getPerformanceSummary() {
        if (this.completedMetrics.length === 0) {
            return { status: 'no_data', message: 'No performance metrics available' };
        }

        const metrics = this.completedMetrics;
        const durations = metrics.map(m => m.totalDuration);

        return {
            totalOperations: metrics.length,
            averageDuration: durations.reduce((a, b) => a + b, 0) / durations.length,
            medianDuration: this.calculateMedian(durations),
            p95Duration: this.calculatePercentile(durations, 95),
            p99Duration: this.calculatePercentile(durations, 99),
            performanceRatings: this.groupByRating(metrics),
            cacheHitRate: this.calculateCacheHitRate(metrics),
            providerDistribution: this.analyzeProviderDistribution(metrics),
            lastUpdated: new Date().toISOString()
        };
    }

    calculateMedian(array) {
        const sorted = [...array].sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
    }

    calculatePercentile(array, percentile) {
        const sorted = [...array].sort((a, b) => a - b);
        const index = Math.ceil((percentile / 100) * sorted.length) - 1;
        return sorted[Math.max(0, index)];
    }

    groupByRating(metrics) {
        const ratings = { excellent: 0, good: 0, acceptable: 0, poor: 0, critical: 0 };
        metrics.forEach(m => {
            ratings[m.performanceRating] = (ratings[m.performanceRating] || 0) + 1;
        });
        return ratings;
    }

    calculateCacheHitRate(metrics) {
        const totalRequests = metrics.length;
        const cacheHits = metrics.filter(m => m.result.cached).length;
        return totalRequests > 0 ? (cacheHits / totalRequests) * 100 : 0;
    }

    analyzeProviderDistribution(metrics) {
        const distribution = {};
        metrics.forEach(m => {
            const provider = m.result.provider || 'unknown';
            distribution[provider] = (distribution[provider] || 0) + 1;
        });
        return distribution;
    }
}

// ============================================================================
// Service Binding Health Monitor
// ============================================================================

class ServiceBindingHealthMonitor {
    constructor() {
        this.healthChecks = new Map();
        this.alertThresholds = {
            errorRate: 0.1,           // 10% error rate
            avgResponseTime: 1000,    // 1 second average
            consecutiveFailures: 3    // 3 consecutive failures
        };
    }

    /**
     * Record service binding call result
     */
    recordServiceCall(serviceName, duration, success, error = null) {
        if (!this.healthChecks.has(serviceName)) {
            this.healthChecks.set(serviceName, {
                totalCalls: 0,
                successfulCalls: 0,
                totalDuration: 0,
                recentCalls: [],
                consecutiveFailures: 0,
                lastError: null,
                lastSuccessTime: null
            });
        }

        const health = this.healthChecks.get(serviceName);
        health.totalCalls++;
        health.totalDuration += duration;

        if (success) {
            health.successfulCalls++;
            health.consecutiveFailures = 0;
            health.lastSuccessTime = Date.now();
        } else {
            health.consecutiveFailures++;
            health.lastError = error?.message || 'Unknown error';
        }

        // Keep last 20 calls for detailed analysis
        health.recentCalls.push({
            timestamp: Date.now(),
            duration,
            success,
            error: error?.message
        });

        if (health.recentCalls.length > 20) {
            health.recentCalls = health.recentCalls.slice(-20);
        }

        // Check for alerts
        this.checkHealthAlerts(serviceName, health);
    }

    /**
     * Check if service health warrants alerts
     */
    checkHealthAlerts(serviceName, health) {
        const alerts = [];

        // Error rate alert
        const errorRate = 1 - (health.successfulCalls / health.totalCalls);
        if (errorRate > this.alertThresholds.errorRate) {
            alerts.push({
                type: 'high_error_rate',
                message: `${serviceName} error rate: ${(errorRate * 100).toFixed(1)}%`,
                severity: 'warning'
            });
        }

        // Response time alert
        const avgResponseTime = health.totalDuration / health.totalCalls;
        if (avgResponseTime > this.alertThresholds.avgResponseTime) {
            alerts.push({
                type: 'slow_response',
                message: `${serviceName} avg response time: ${avgResponseTime.toFixed(0)}ms`,
                severity: 'warning'
            });
        }

        // Consecutive failures alert
        if (health.consecutiveFailures >= this.alertThresholds.consecutiveFailures) {
            alerts.push({
                type: 'consecutive_failures',
                message: `${serviceName} has ${health.consecutiveFailures} consecutive failures`,
                severity: 'critical'
            });
        }

        // Log alerts
        alerts.forEach(alert => {
            console.warn(`🚨 SERVICE ALERT [${alert.severity.toUpperCase()}]: ${alert.message}`);
        });

        return alerts;
    }

    /**
     * Get health status for all services
     */
    getHealthStatus() {
        const status = {};

        for (const [serviceName, health] of this.healthChecks.entries()) {
            const errorRate = health.totalCalls > 0 ? 1 - (health.successfulCalls / health.totalCalls) : 0;
            const avgResponseTime = health.totalCalls > 0 ? health.totalDuration / health.totalCalls : 0;

            // Calculate recent performance (last 10 calls)
            const recentCalls = health.recentCalls.slice(-10);
            const recentSuccessRate = recentCalls.length > 0 ?
                recentCalls.filter(call => call.success).length / recentCalls.length : 0;

            status[serviceName] = {
                overall: this.calculateOverallHealth(errorRate, avgResponseTime, health.consecutiveFailures),
                statistics: {
                    totalCalls: health.totalCalls,
                    successRate: (health.successfulCalls / health.totalCalls) * 100,
                    avgResponseTime: Math.round(avgResponseTime),
                    recentSuccessRate: recentSuccessRate * 100,
                    consecutiveFailures: health.consecutiveFailures
                },
                lastError: health.lastError,
                lastSuccessTime: health.lastSuccessTime,
                isHealthy: errorRate < this.alertThresholds.errorRate &&
                          avgResponseTime < this.alertThresholds.avgResponseTime &&
                          health.consecutiveFailures < this.alertThresholds.consecutiveFailures
            };
        }

        return status;
    }

    /**
     * Calculate overall health score
     */
    calculateOverallHealth(errorRate, avgResponseTime, consecutiveFailures) {
        let score = 100;

        // Penalize for error rate
        score -= errorRate * 100;

        // Penalize for slow response times
        if (avgResponseTime > 500) {
            score -= Math.min((avgResponseTime - 500) / 100 * 10, 30);
        }

        // Penalize for consecutive failures
        score -= consecutiveFailures * 10;

        return Math.max(0, Math.round(score));
    }
}

// ============================================================================
// Cache Analytics Engine
// ============================================================================

class CacheAnalyticsEngine {
    constructor() {
        this.analytics = {
            keyPatterns: new Map(),
            hitRatesByProvider: new Map(),
            promotionEffectiveness: new Map(),
            storageDistribution: { kv: 0, r2: 0 }
        };
    }

    /**
     * Analyze cache key patterns for optimization insights
     */
    analyzeCacheKey(cacheKey, hitType, provider, duration) {
        // Extract pattern from cache key
        const pattern = this.extractKeyPattern(cacheKey);

        if (!this.analytics.keyPatterns.has(pattern)) {
            this.analytics.keyPatterns.set(pattern, {
                hits: 0,
                misses: 0,
                totalDuration: 0,
                providers: new Set()
            });
        }

        const patternStats = this.analytics.keyPatterns.get(pattern);

        if (hitType !== 'miss') {
            patternStats.hits++;
        } else {
            patternStats.misses++;
        }

        patternStats.totalDuration += duration;
        patternStats.providers.add(provider);

        // Analyze provider-specific hit rates
        if (!this.analytics.hitRatesByProvider.has(provider)) {
            this.analytics.hitRatesByProvider.set(provider, { hits: 0, misses: 0 });
        }

        const providerStats = this.analytics.hitRatesByProvider.get(provider);
        if (hitType !== 'miss') {
            providerStats.hits++;
        } else {
            providerStats.misses++;
        }
    }

    /**
     * Extract pattern from cache key for analysis
     */
    extractKeyPattern(cacheKey) {
        // Remove hash portions and extract semantic pattern
        const parts = cacheKey.split(':');
        if (parts.length >= 2) {
            return `${parts[0]}:${parts[1].substring(0, 10)}...`;
        }
        return cacheKey.substring(0, 20);
    }

    /**
     * Generate optimization recommendations
     */
    generateOptimizationRecommendations() {
        const recommendations = [];

        // Analyze cache key patterns
        for (const [pattern, stats] of this.analytics.keyPatterns.entries()) {
            const hitRate = stats.hits / (stats.hits + stats.misses);
            const avgDuration = stats.totalDuration / (stats.hits + stats.misses);

            if (hitRate < 0.5 && stats.hits + stats.misses > 10) {
                recommendations.push({
                    type: 'low_hit_rate',
                    pattern,
                    message: `Cache pattern "${pattern}" has low hit rate: ${(hitRate * 100).toFixed(1)}%`,
                    suggestion: 'Consider improving cache key normalization or TTL strategy',
                    priority: 'medium'
                });
            }

            if (avgDuration > 200 && hitRate > 0.8) {
                recommendations.push({
                    type: 'slow_cache_access',
                    pattern,
                    message: `Cache pattern "${pattern}" has slow access: ${avgDuration.toFixed(0)}ms`,
                    suggestion: 'Consider promoting to KV hot cache or optimizing data structure',
                    priority: 'high'
                });
            }
        }

        // Analyze provider performance
        for (const [provider, stats] of this.analytics.hitRatesByProvider.entries()) {
            const hitRate = stats.hits / (stats.hits + stats.misses);

            if (hitRate < 0.3 && stats.hits + stats.misses > 20) {
                recommendations.push({
                    type: 'provider_cache_inefficiency',
                    provider,
                    message: `Provider "${provider}" has very low cache hit rate: ${(hitRate * 100).toFixed(1)}%`,
                    suggestion: 'Investigate provider-specific caching strategies or query patterns',
                    priority: 'high'
                });
            }
        }

        return recommendations.sort((a, b) => {
            const priorityOrder = { high: 3, medium: 2, low: 1 };
            return priorityOrder[b.priority] - priorityOrder[a.priority];
        });
    }

    /**
     * Get comprehensive analytics report
     */
    getAnalyticsReport() {
        const recommendations = this.generateOptimizationRecommendations();

        return {
            summary: {
                totalPatterns: this.analytics.keyPatterns.size,
                totalProviders: this.analytics.hitRatesByProvider.size,
                recommendationsCount: recommendations.length
            },
            keyPatterns: this.formatKeyPatternStats(),
            providerPerformance: this.formatProviderStats(),
            recommendations,
            lastAnalysis: new Date().toISOString()
        };
    }

    formatKeyPatternStats() {
        const formatted = {};
        for (const [pattern, stats] of this.analytics.keyPatterns.entries()) {
            formatted[pattern] = {
                hitRate: ((stats.hits / (stats.hits + stats.misses)) * 100).toFixed(1) + '%',
                totalRequests: stats.hits + stats.misses,
                avgDuration: (stats.totalDuration / (stats.hits + stats.misses)).toFixed(0) + 'ms',
                providers: Array.from(stats.providers)
            };
        }
        return formatted;
    }

    formatProviderStats() {
        const formatted = {};
        for (const [provider, stats] of this.analytics.hitRatesByProvider.entries()) {
            formatted[provider] = {
                hitRate: ((stats.hits / (stats.hits + stats.misses)) * 100).toFixed(1) + '%',
                totalRequests: stats.hits + stats.misses,
                hits: stats.hits,
                misses: stats.misses
            };
        }
        return formatted;
    }
}

// ============================================================================
// Integrated Performance Dashboard
// ============================================================================

class PerformanceDashboard {
    constructor() {
        this.performanceTracker = new AdvancedPerformanceTracker();
        this.healthMonitor = new ServiceBindingHealthMonitor();
        this.cacheAnalytics = new CacheAnalyticsEngine();
    }

    /**
     * Generate comprehensive performance dashboard
     */
    generateDashboard() {
        const performanceSummary = this.performanceTracker.getPerformanceSummary();
        const healthStatus = this.healthMonitor.getHealthStatus();
        const cacheAnalytics = this.cacheAnalytics.getAnalyticsReport();

        return {
            timestamp: new Date().toISOString(),
            status: this.calculateOverallStatus(performanceSummary, healthStatus),
            performance: performanceSummary,
            serviceHealth: healthStatus,
            cacheAnalytics: cacheAnalytics,
            alerts: this.generateAlerts(performanceSummary, healthStatus, cacheAnalytics),
            recommendations: this.generateRecommendations(performanceSummary, healthStatus, cacheAnalytics)
        };
    }

    /**
     * Calculate overall system status
     */
    calculateOverallStatus(performance, health) {
        if (performance.status === 'no_data') {
            return { level: 'unknown', message: 'Insufficient data for status assessment' };
        }

        const avgDuration = performance.averageDuration || 0;
        const cacheHitRate = performance.cacheHitRate || 0;

        // Check service health
        const unhealthyServices = Object.values(health).filter(service => !service.isHealthy);

        if (unhealthyServices.length > 0) {
            return { level: 'warning', message: `${unhealthyServices.length} service(s) unhealthy` };
        }

        if (avgDuration > 1000) {
            return { level: 'critical', message: 'High average response times detected' };
        }

        if (avgDuration > 500 || cacheHitRate < 60) {
            return { level: 'warning', message: 'Performance degradation detected' };
        }

        return { level: 'healthy', message: 'All systems operating normally' };
    }

    /**
     * Generate system alerts
     */
    generateAlerts(performance, health, analytics) {
        const alerts = [];

        // Performance alerts
        if (performance.p95Duration > 2000) {
            alerts.push({
                type: 'performance',
                severity: 'critical',
                message: `95th percentile response time: ${performance.p95Duration}ms`
            });
        }

        // Cache alerts
        if (performance.cacheHitRate < 50) {
            alerts.push({
                type: 'cache',
                severity: 'warning',
                message: `Low cache hit rate: ${performance.cacheHitRate.toFixed(1)}%`
            });
        }

        // Service health alerts
        Object.entries(health).forEach(([serviceName, serviceHealth]) => {
            if (!serviceHealth.isHealthy) {
                alerts.push({
                    type: 'service',
                    severity: 'warning',
                    message: `Service ${serviceName} is unhealthy`,
                    details: serviceHealth.lastError
                });
            }
        });

        return alerts;
    }

    /**
     * Generate optimization recommendations
     */
    generateRecommendations(performance, health, analytics) {
        const recommendations = [...analytics.recommendations];

        // Add performance-based recommendations
        if (performance.averageDuration > 500) {
            recommendations.push({
                type: 'performance_optimization',
                message: 'Consider implementing service binding optimizations',
                suggestion: 'Use relative URLs and connection pooling for service bindings',
                priority: 'high'
            });
        }

        if (performance.cacheHitRate < 70) {
            recommendations.push({
                type: 'cache_optimization',
                message: 'Cache hit rate could be improved',
                suggestion: 'Implement semantic cache keys and predictive warming',
                priority: 'medium'
            });
        }

        return recommendations;
    }

    // Expose individual trackers for integration
    getPerformanceTracker() { return this.performanceTracker; }
    getHealthMonitor() { return this.healthMonitor; }
    getCacheAnalytics() { return this.cacheAnalytics; }
}

// ============================================================================
// Exports
// ============================================================================

const globalDashboard = new PerformanceDashboard();

export {
    AdvancedPerformanceTracker,
    ServiceBindingHealthMonitor,
    CacheAnalyticsEngine,
    PerformanceDashboard,
    globalDashboard
};