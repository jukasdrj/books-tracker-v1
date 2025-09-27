-- 📊 Cloudflare Analytics Engine Queries
-- Performance monitoring and optimization templates for books tracker infrastructure

-- === CACHE HIT RATE ANALYSIS ===

-- Overall cache performance
SELECT
    timestamp,
    SUM(CASE WHEN blob1 = 'get' AND double1 = 1 THEN 1 ELSE 0 END) as cache_hits,
    SUM(CASE WHEN blob1 = 'get' AND double1 = 0 THEN 1 ELSE 0 END) as cache_misses,
    ROUND(
        SUM(CASE WHEN blob1 = 'get' AND double1 = 1 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(*), 0), 2
    ) as hit_rate_percent
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '24 hours'
    AND blob1 = 'get'
GROUP BY timestamp
ORDER BY timestamp DESC
LIMIT 100;

-- Cache performance by hour
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    COUNT(*) as total_operations,
    SUM(double1) as hits,
    COUNT(*) - SUM(double1) as misses,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as hit_rate_percent,
    ROUND(AVG(double2), 2) as avg_response_time_ms
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND blob1 = 'get'
GROUP BY hour
ORDER BY hour DESC;

-- === PROVIDER PERFORMANCE ANALYSIS ===

-- Provider success rates and response times
SELECT
    blob1 as provider,
    blob2 as operation,
    COUNT(*) as total_calls,
    SUM(double1) as successful_calls,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as success_rate_percent,
    ROUND(AVG(double2), 2) as avg_response_time_ms,
    ROUND(MIN(double2), 2) as min_response_time_ms,
    ROUND(MAX(double2), 2) as max_response_time_ms
FROM books_api_provider_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY provider, operation
ORDER BY provider, avg_response_time_ms DESC;

-- Provider failure analysis
SELECT
    blob1 as provider,
    blob4 as error_code,
    COUNT(*) as error_count,
    ROUND(AVG(double2), 2) as avg_response_time_ms
FROM books_api_provider_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
    AND double1 = 0  -- failures only
    AND blob4 != 'none'
GROUP BY provider, error_code
ORDER BY error_count DESC;

-- === STEPHEN KING CACHE MISS INVESTIGATION ===

-- Cache miss reasons analysis
SELECT
    blob2 as reason,
    blob3 as expected_location,
    blob4 as actual_location,
    COUNT(*) as miss_count
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND blob1 LIKE '%stephen%king%' OR blob1 LIKE '%king%stephen%'
GROUP BY reason, expected_location, actual_location
ORDER BY miss_count DESC;

-- Stephen King search patterns
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    blob1 as query,
    COUNT(*) as search_count,
    SUM(double1) as cache_hits,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as hit_rate_percent
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '3 days'
    AND (LOWER(blob1) LIKE '%stephen%king%' OR LOWER(blob1) LIKE '%king%stephen%')
GROUP BY hour, query
ORDER BY hour DESC, search_count DESC;

-- === PERFORMANCE TRENDING ===

-- Response time trends by worker
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    blob2 as worker,
    blob1 as operation,
    COUNT(*) as operation_count,
    ROUND(AVG(double1), 2) as avg_duration_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY double1), 2) as p95_duration_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY double1), 2) as p99_duration_ms
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY hour, worker, operation
ORDER BY hour DESC, avg_duration_ms DESC;

-- Slowest operations in the last 24 hours
SELECT
    timestamp,
    blob2 as worker,
    blob1 as operation,
    double1 as duration_ms,
    index1 as request_id
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
    AND double1 > 5000  -- Operations taking more than 5 seconds
ORDER BY double1 DESC
LIMIT 50;

-- === CACHE WARMING EFFECTIVENESS ===

-- Cache warming performance
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    COUNT(*) as warming_operations,
    ROUND(AVG(double1), 2) as avg_duration_ms,
    SUM(CASE WHEN double1 < 2000 THEN 1 ELSE 0 END) as fast_operations,
    ROUND(
        SUM(CASE WHEN double1 < 2000 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    ) as fast_operation_percent
FROM cache_warmer_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour DESC;

-- Cache warming author success rates
SELECT
    blob1 as operation,
    COUNT(*) as total_attempts,
    SUM(double1) as successful_attempts,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as success_rate_percent,
    ROUND(AVG(double2), 2) as avg_duration_ms
FROM cache_warmer_performance
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND blob1 IN ('author_cache', 'biography_fetch', 'bulk_warming')
GROUP BY operation
ORDER BY success_rate_percent DESC;

-- === ERROR ANALYSIS ===

-- Error patterns by worker
SELECT
    blob2 as worker,
    blob1 as operation,
    COUNT(*) as error_count,
    ROUND(AVG(double1), 2) as avg_duration_before_error
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
    AND blob1 LIKE '%error%' OR blob1 LIKE '%fail%'
GROUP BY worker, operation
ORDER BY error_count DESC;

-- === RATE LIMITING ANALYSIS ===

-- ISBNdb rate limit utilization
SELECT
    DATE_TRUNC('hour', timestamp) as hour,
    ROUND(AVG(double1), 2) as avg_remaining_quota,
    ROUND(AVG(double3), 2) as avg_used_quota,
    MIN(double1) as min_remaining_quota
FROM isbndb_worker_performance
WHERE timestamp >= NOW() - INTERVAL '24 hours'
    AND blob1 = 'rate_limit'
GROUP BY hour
ORDER BY hour DESC;

-- === OPTIMIZATION OPPORTUNITIES ===

-- Operations that could benefit from caching
SELECT
    blob1 as operation,
    blob2 as worker,
    COUNT(*) as frequency,
    ROUND(AVG(double1), 2) as avg_duration_ms,
    COUNT(*) * ROUND(AVG(double1), 2) as total_time_spent
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND double1 > 1000  -- Operations taking more than 1 second
GROUP BY operation, worker
HAVING COUNT(*) > 10  -- Operations that happen frequently
ORDER BY total_time_spent DESC
LIMIT 20;

-- Cache operations with high miss rates
SELECT
    blob2 as cache_key_pattern,
    COUNT(*) as total_operations,
    SUM(double1) as hits,
    COUNT(*) - SUM(double1) as misses,
    ROUND((COUNT(*) - SUM(double1)) * 100.0 / COUNT(*), 2) as miss_rate_percent,
    ROUND(AVG(double2), 2) as avg_response_time_ms
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND blob1 = 'get'
GROUP BY SUBSTRING(blob2, 1, 20)  -- Group by cache key prefix
HAVING COUNT(*) > 20
ORDER BY miss_rate_percent DESC;

-- === REAL-TIME ALERTS QUERIES ===

-- High error rate alert (last 5 minutes)
SELECT
    COUNT(*) as error_count,
    blob2 as worker
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '5 minutes'
    AND (blob1 LIKE '%error%' OR blob1 LIKE '%fail%')
GROUP BY worker
HAVING COUNT(*) > 5;

-- High response time alert (last 5 minutes)
SELECT
    COUNT(*) as slow_operations,
    blob2 as worker,
    ROUND(AVG(double1), 2) as avg_response_time
FROM books_api_performance
WHERE timestamp >= NOW() - INTERVAL '5 minutes'
    AND double1 > 10000  -- More than 10 seconds
GROUP BY worker
HAVING COUNT(*) > 1;

-- Low cache hit rate alert (last 15 minutes)
SELECT
    blob3 as worker,
    COUNT(*) as total_cache_ops,
    SUM(double1) as hits,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as hit_rate
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '15 minutes'
    AND blob1 = 'get'
GROUP BY worker
HAVING ROUND(SUM(double1) * 100.0 / COUNT(*), 2) < 50;  -- Less than 50% hit rate

-- === USAGE PATTERNS ===

-- Most searched authors/queries
SELECT
    blob2 as search_query,
    COUNT(*) as search_count,
    ROUND(AVG(double2), 2) as avg_response_time,
    SUM(double1) as cache_hits,
    ROUND(SUM(double1) * 100.0 / COUNT(*), 2) as hit_rate
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND blob1 = 'get'
    AND blob2 LIKE '%author%'
GROUP BY search_query
ORDER BY search_count DESC
LIMIT 20;

-- Peak usage hours
SELECT
    EXTRACT(HOUR FROM timestamp) as hour_of_day,
    COUNT(*) as total_operations,
    ROUND(AVG(double2), 2) as avg_response_time
FROM books_api_cache_metrics
WHERE timestamp >= NOW() - INTERVAL '7 days'
GROUP BY hour_of_day
ORDER BY total_operations DESC;

-- === EXPORT QUERIES FOR MONITORING SCRIPTS ===

-- Query templates for wrangler analytics command:

/*
# Cache hit rate (last 24 hours)
wrangler analytics query \
  --dataset books_api_cache_metrics \
  --start-date $(date -d '1 day ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --dimensions blob1,blob2 \
  --metrics sum,count \
  --filters 'blob1=="get"' \
  --limit 100

# Provider performance (last 24 hours)
wrangler analytics query \
  --dataset books_api_provider_performance \
  --start-date $(date -d '1 day ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --dimensions blob1,blob2 \
  --metrics avg,max,min \
  --limit 100

# Worker performance (last 6 hours)
wrangler analytics query \
  --dataset books_api_performance \
  --start-date $(date -d '6 hours ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --dimensions blob1,blob2 \
  --metrics avg,count \
  --limit 50
*/