# Cloudflare Workers Debugging Guide

**Updated:** October 16, 2025
**Version:** 3.0.0 (Build 46+)

## Quick Reference

```bash
# Monitor specific worker
wrangler tail personal-library-cache-warmer --format pretty

# Filter logs by search term
wrangler tail books-api-proxy --search "provider"
wrangler tail personal-library-cache-warmer --search "📚"

# Check KV namespace
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/debug-kv"

# Health check
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

## Worker Tail Commands

### books-api-proxy
```bash
wrangler tail books-api-proxy --format pretty
wrangler tail books-api-proxy --search "orchestrated"  # Multi-provider calls
wrangler tail books-api-proxy --search "ERROR"         # Errors only
```

### bookshelf-ai-worker
```bash
wrangler tail bookshelf-ai-worker --format pretty
wrangler tail bookshelf-ai-worker --search "Gemini"    # AI processing
wrangler tail bookshelf-ai-worker --search "enrichment" # Backend enrichment
```

### personal-library-cache-warmer
```bash
wrangler tail personal-library-cache-warmer --format pretty
wrangler tail personal-library-cache-warmer --search "cron"  # Scheduled runs
```

### isbndb-biography-worker
```bash
wrangler tail isbndb-biography-worker --format pretty
wrangler tail isbndb-biography-worker --search "biography"
```

## Debug Endpoints

### KV Namespace Inspection
```bash
# List all cache keys
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/debug-kv"

# Check specific cache entry
curl "https://books-api-proxy.jukasdrj.workers.dev/debug-cache/isbndb:9780743273565"
```

### Health Checks
```bash
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
# Response: {"status": "ok", "timestamp": "2025-10-16T..."}
```

## Log Filtering Patterns

### Search by Provider
```bash
--search "isbndb"       # ISBNdb API calls
--search "openlibrary"  # OpenLibrary calls
--search "google"       # Google Books calls
```

### Search by Operation
```bash
--search "cache hit"    # Cache hits
--search "cache miss"   # Cache misses
--search "RPC"          # Service binding calls
--search "enrichment"   # Enrichment operations
```

### Search by Error Level
```bash
--search "ERROR"        # Errors only
--search "WARN"         # Warnings
--search "📚"           # Cache warmer logs
```

## Local Development

### Start Dev Server
```bash
cd cloudflare-workers
npm run dev
# books-api-proxy: http://localhost:8787
```

### Test Endpoints Locally
```bash
curl -X POST http://localhost:8787/search/title \
  -H "Content-Type: application/json" \
  -d '{"query": "Harry Potter", "limit": 5}'
```

### Inspect Environment Variables
```bash
wrangler secret list --name books-api-proxy
```

## Common Error Patterns

### ISBNdb Quota Exceeded
```
Error: 429 Too Many Requests
Solution: Check quota at https://isbndb.com/account
```

### Cache Write Failure
```
Error: KV namespace write failed
Solution: Check namespace binding in wrangler.toml
```

### RPC Binding Not Found
```
Error: Service binding 'ISBNDB_WORKER' not found
Solution: Deploy dependent worker first, check wrangler.toml bindings
```

### Timeout on AI Processing
```
Error: 408 Request Timeout (bookshelf-ai-worker)
Solution: Image too large or complex. Increase timeout or compress image.
```

## KV Namespace Operations

### List Namespaces
```bash
wrangler kv:namespace list
```

### Get Key
```bash
wrangler kv:key get "isbndb:9780743273565" --namespace-id <NAMESPACE_ID>
```

### Put Key (for testing)
```bash
wrangler kv:key put "test:key" "value" --namespace-id <NAMESPACE_ID>
```

### Delete Key
```bash
wrangler kv:key delete "test:key" --namespace-id <NAMESPACE_ID>
```

## Deployment Debugging

### Check Deployment Status
```bash
wrangler deployments list --name books-api-proxy
```

### Rollback Deployment
```bash
wrangler rollback --name books-api-proxy
```

### View Deployment Logs
```bash
wrangler tail books-api-proxy --format json > deployment-logs.json
```

## Performance Monitoring

### Response Time Tracking
```bash
wrangler tail books-api-proxy --search "processingTime"
```

### Cache Hit Rate
```bash
wrangler tail books-api-proxy --search "cache" | grep -E "(hit|miss)"
```

## Security

### Check Secrets
```bash
wrangler secret list --name books-api-proxy
```

### Rotate Secret
```bash
wrangler secret put ISBNDB_API_KEY --name books-api-proxy
```

## Related Documentation

- CLAUDE.md: Backend Architecture section
- docs/API.md: API contracts and RPC bindings
- cloudflare-workers/README.md: Deployment guide
- cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md: RPC architecture
