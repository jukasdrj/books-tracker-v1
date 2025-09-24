# CloudFlare Workers $5/mo Paid Plan - Advanced Monitoring Commands

## 🚀 Deployment Commands

### Deploy Optimized Configurations
```bash
# Deploy cache warmer with optimized config
cd cloudflare-workers/personal-library-cache-warmer
cp wrangler-optimized.toml wrangler.toml
wrangler deploy --compatibility-date 2024-09-17

# Deploy books API proxy with enhanced features
cd ../books-api-proxy
cp wrangler-optimized.toml wrangler.toml
wrangler deploy --compatibility-date 2024-09-17

# Deploy ISBNdb worker to production
cd ../isbndb-biography-worker
cp wrangler-optimized.toml wrangler.toml
wrangler deploy --env production --compatibility-date 2024-09-17
```

## 📊 Real-Time Monitoring

### Live Tail Logging (Paid Plan Feature)
```bash
# Enhanced cache warmer monitoring
wrangler tail --name personal-library-cache-warmer \
  --format pretty \
  --status error,ok \
  --search "cache" \
  --ip-address

# Books API proxy monitoring with filtering
wrangler tail --name books-api-proxy \
  --format json \
  --status error \
  --header "X-Custom-Debug" \
  --output logs/books-api-$(date +%Y%m%d).log

# ISBNdb worker monitoring
wrangler tail --name isbndb-biography-worker-production \
  --format pretty \
  --search "author" \
  --sampling-rate 0.1
```

### Performance Analytics Queries
```bash
# Cache warming performance metrics
wrangler analytics query \
  --dataset cache_warming_metrics \
  --start-date $(date -d '1 day ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --dimensions timestamp \
  --metrics count,sum

# API usage analytics
wrangler analytics query \
  --dataset api_usage_tracking \
  --start-date $(date -d '7 days ago' +%Y-%m-%d) \
  --filters "index=performance_metrics" \
  --order timestamp desc \
  --limit 100
```

## 🗄️ KV Storage Monitoring

### Cache Status and Health
```bash
# Count cached authors (should grow over time)
wrangler kv key list --binding WARMING_CACHE --remote | grep "author_bibliography_" | wc -l

# Check cache warming progress
wrangler kv key get --binding WARMING_CACHE --remote "cache_index"

# Monitor bulk operations cache
wrangler kv key list --binding BULK_OPERATIONS_CACHE --remote --limit 10

# Check search-optimized cache performance
wrangler kv key list --binding SEARCH_CACHE --remote | head -20

# Rate limiting status
wrangler kv key get --binding RATE_LIMIT_CACHE --remote "api_quota_status"
```

### KV Performance Analysis
```bash
# Storage utilization
wrangler kv namespace info --binding WARMING_CACHE

# Most recently accessed keys
wrangler kv key list --binding WARMING_CACHE --remote --order modified_on desc --limit 10

# Cache entry details with metadata
wrangler kv key get --binding WARMING_CACHE --remote "author_bibliography_andy_weir" --metadata
```

## 💾 R2 Storage Monitoring

### Storage Analytics
```bash
# Library data bucket status
wrangler r2 object list personal-library-data --limit 20

# Cache analytics storage
wrangler r2 object list cache-warming-analytics --prefix "reports/" --limit 10

# Bulk operations storage
wrangler r2 object list books-bulk-operations --limit 5

# Author bibliographies archive
wrangler r2 object list author-bibliographies --prefix "bibliographies/" --limit 10
```

### R2 Performance Metrics
```bash
# Storage usage summary
wrangler r2 bucket info personal-library-data

# Recent upload activity
wrangler r2 object list personal-library-data --order last-modified desc --limit 5

# Download latest warming report
wrangler r2 object get cache-warming-analytics reports/warming_$(date +%Y%m%d).json
```

## 🔥 Cache Operations

### Force Cache Refresh (Bypasses All Layers)
```bash
# Full library cache refresh
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" \
  -H "Content-Type: application/json" \
  -d '{
    "strategy": "hybrid",
    "maxAuthors": 50,
    "force": true,
    "batchSize": 20
  }'

# Targeted author refresh
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" \
  -H "Content-Type: application/json" \
  -d '{
    "strategy": "targeted",
    "authors": ["Andy Weir", "Martha Wells", "Kim Stanley Robinson"],
    "force": true
  }'
```

### Cache Health Checks
```bash
# System health status
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/health"

# Live warming status with detailed metrics
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/live-status"

# Cache efficiency report
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/stats"

# API proxy health
curl "https://books.ooheynerds.com/health"
```

## 🔍 Service Binding Diagnostics

### Test Service Communication
```bash
# Test ISBNdb worker direct access
curl "https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/andy%20weir"

# Test books API proxy with cache validation
curl "https://books.ooheynerds.com/search?q=Andy%20Weir&maxResults=10&force=true"

# Test service binding chain
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/test-bindings"
```

### Circuit Breaker Status
```bash
# Check circuit breaker states
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/circuit-status"

# Reset circuit breakers
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/reset-circuits"
```

## 📈 Performance Optimization

### Worker Metrics
```bash
# CPU and memory usage
wrangler metrics --worker personal-library-cache-warmer --start-date $(date -d '1 day ago' +%Y-%m-%d)

# Request patterns and latency
wrangler metrics --worker books-api-proxy --start-date $(date -d '6 hours ago' +%Y-%m-%d)

# Error rates and success metrics
wrangler metrics --worker isbndb-biography-worker-production --start-date $(date -d '12 hours ago' +%Y-%m-%d)
```

### Paid Plan Utilization
```bash
# CPU time utilization (should approach 30s for paid plan)
wrangler analytics query --dataset performance_metrics --metrics "avg(cpuTime)" --start-date $(date +%Y-%m-%d)

# Memory usage patterns
wrangler analytics query --dataset performance_metrics --metrics "max(memoryUsage)" --start-date $(date +%Y-%m-%d)

# Concurrent request handling
wrangler analytics query --dataset performance_metrics --dimensions "timestamp" --start-date $(date +%Y-%m-%d)
```

## 🚨 Alert Setup

### Log-based Alerts
```bash
# Setup error rate alerting
wrangler logpush create \
  --name "high-error-rate-alert" \
  --destination "https://alerts.your-monitoring.com/cf-workers" \
  --dataset "workers_trace_events" \
  --filter '{"outcome": ["exception", "exceededMemory"], "count": ">10"}' \
  --frequency "5m"

# Setup performance degradation alerts
wrangler logpush create \
  --name "performance-alert" \
  --destination "https://alerts.your-monitoring.com/cf-performance" \
  --dataset "workers_trace_events" \
  --filter '{"cpuTime": ">25000", "outcome": "ok"}' \
  --frequency "1m"
```

## 🔧 Troubleshooting Commands

### Debug Cache Population Issues
```bash
# Verify library data upload
wrangler r2 object get personal-library-data personal-library.json | jq '.authors | length'

# Check if cache warming is actually working
BEFORE_COUNT=$(wrangler kv key list --binding WARMING_CACHE --remote | wc -l)
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" -d '{"maxAuthors": 5}'
sleep 30
AFTER_COUNT=$(wrangler kv key list --binding WARMING_CACHE --remote | wc -l)
echo "Cache entries increased by: $((AFTER_COUNT - BEFORE_COUNT))"

# Test individual author processing
curl "https://isbndb-biography-worker-production.jukasdrj.workers.dev/author/test" -v
```

### Performance Debugging
```bash
# Check for rate limiting issues
wrangler kv key get --binding RATE_LIMIT_CACHE --remote "isbndb_api_rate_limit"

# Verify service binding connectivity
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/debug" \
  -H "Content-Type: application/json" \
  -d '{"test": "service_bindings"}'

# Check memory usage patterns
wrangler tail --name personal-library-cache-warmer --search "memory" --format json
```

## 💡 Optimization Tips

### Maximize Paid Plan Value
1. **Use bulk operations**: Batch KV reads/writes for 3-5x performance improvement
2. **Leverage extended CPU time**: Process larger batches (20-50 authors vs 10)
3. **Implement intelligent caching**: Use cache freshness checks to minimize API calls
4. **Monitor analytics**: Use Analytics Engine for data-driven optimization
5. **Optimize service bindings**: Implement circuit breakers and retry logic

### Cache Population Verification
```bash
# Run this script to verify cache is actually populating:
#!/bin/bash
echo "🔍 Verifying cache population..."

# Count before
BEFORE=$(wrangler kv key list --binding WARMING_CACHE --remote | grep "author_bibliography_" | wc -l)
echo "📊 Cache entries before: $BEFORE"

# Trigger warming
echo "🚀 Triggering cache warming..."
curl -X POST "https://personal-library-cache-warmer.jukasdrj.workers.dev/warm" \
  -H "Content-Type: application/json" \
  -d '{"maxAuthors": 10, "force": false}'

# Wait for completion
echo "⏳ Waiting 60 seconds for processing..."
sleep 60

# Count after
AFTER=$(wrangler kv key list --binding WARMING_CACHE --remote | grep "author_bibliography_" | wc -l)
echo "📊 Cache entries after: $AFTER"

# Calculate improvement
IMPROVEMENT=$((AFTER - BEFORE))
echo "✅ Cache grew by: $IMPROVEMENT entries"

if [ $IMPROVEMENT -gt 0 ]; then
    echo "🎉 SUCCESS: Cache is populating correctly!"
else
    echo "❌ ISSUE: Cache not populating - check logs"
    wrangler tail --name personal-library-cache-warmer --format pretty --limit 50
fi
```