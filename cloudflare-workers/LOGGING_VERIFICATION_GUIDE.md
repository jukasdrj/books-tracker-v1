# Logging Infrastructure Verification Guide

**Phase A + B Complete - Verification Checklist**

Use this guide to verify your logging infrastructure is working correctly.

---

## ✅ Verification Checklist

### 1. Worker Health Check (30 seconds)

Verify all workers are responding:

```bash
# Test all worker endpoints
echo "Testing books-api-proxy..."
curl -s "https://books-api-proxy.jukasdrj.workers.dev/health"
# Expected: {"status":"healthy","worker":"books-api-proxy"}

echo -e "\nTesting bookshelf-ai-worker..."
curl -s "https://bookshelf-ai-worker.jukasdrj.workers.dev/" | head -5
# Expected: HTML content (scanner UI)

echo -e "\nTesting cache-warmer..."
curl -s "https://personal-library-cache-warmer.jukasdrj.workers.dev/status"
# Expected: JSON with status and author count

echo -e "\nTesting websocket DO..."
curl -s "https://progress-websocket-durable-object.jukasdrj.workers.dev/"
# Expected: Some response (200 or 404)

echo -e "\n✅ All workers responding!"
```

---

### 2. Real-Time Structured Logs (2 minutes)

Open **separate terminal windows** for each worker:

**Terminal 1 - Main API:**
```bash
wrangler tail books-api-proxy --format pretty
```

**Terminal 2 - AI Worker:**
```bash
wrangler tail bookshelf-ai-worker --format pretty
```

**Terminal 3 - External APIs:**
```bash
wrangler tail external-apis-worker --format pretty
```

**What to look for:**

**DEBUG Logs (Phase A):**
- Console.log statements with detailed variable states
- Method entry/exit messages
- Decision point logging

**Structured Logs (Phase B) - Look for emojis:**
- 🚀 `PERF [worker-name] operation: 123ms {...}` - Performance timing
- 📊 `CACHE [worker-name] ✅ HIT get key (12ms, 4096b)` - Cache operations
- 🌐 `PROVIDER [worker-name] ✅ SUCCESS provider/operation: 456ms` - API health

**Trigger some traffic:**

```bash
# In a NEW terminal:

# Test 1: Health check (should show in books-api-proxy logs)
curl "https://books-api-proxy.jukasdrj.workers.dev/health"

# Test 2: Search (should trigger performance logging)
curl "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=stephen%20king&maxResults=10"
```

**Expected in books-api-proxy logs:**
```
🚀 PERF [books-api-proxy] rpc_searchByAuthor: 234ms { authorName: 'stephen king', resultsCount: 25 }
📊 CACHE [books-api-proxy] ✅ HIT get author:stephen_king:10:0 (12ms, 4096b)
```

**Expected in external-apis-worker logs (if cache miss):**
```
🚀 PERF [external-apis-worker] rpc_searchGoogleBooks: 456ms { query: 'stephen king', resultsCount: 20 }
🌐 PROVIDER [external-apis-worker] ✅ SUCCESS google_books/search: 445ms
```

---

### 3. Analytics Engine Data Flow (10 minutes)

**Wait 5-10 minutes** after triggering traffic, then check Analytics Engine.

**Navigate to:**
1. https://dash.cloudflare.com
2. Your account → **Analytics & Logs**
3. **Analytics Engine**

**Run Test Query 1: Worker Performance**
```sql
SELECT
  blob2 as worker,
  blob1 as operation,
  COUNT(*) as total_operations,
  ROUND(AVG(double1), 2) as avg_duration_ms
FROM books_api_performance
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY worker, operation
ORDER BY avg_duration_ms DESC
LIMIT 10;
```

**Expected results:**
| worker | operation | total_operations | avg_duration_ms |
|--------|-----------|------------------|-----------------|
| books-api-proxy | rpc_searchByAuthor | 5 | 234.50 |
| external-apis-worker | rpc_searchGoogleBooks | 3 | 456.20 |
| bookshelf-ai-worker | scanBookshelf | 1 | 28456.00 |

**Run Test Query 2: Provider Health**
```sql
SELECT
  blob1 as provider,
  blob2 as operation,
  COUNT(*) as total_calls,
  SUM(double1) as success_count,
  ROUND(100.0 * SUM(double1) / COUNT(*), 2) as success_rate_percent,
  ROUND(AVG(double2), 2) as avg_response_time_ms
FROM books_api_provider_performance
WHERE timestamp > NOW() - INTERVAL '1' HOUR
GROUP BY provider, operation;
```

**Expected results:**
| provider | operation | total_calls | success_count | success_rate_percent | avg_response_time_ms |
|----------|-----------|-------------|---------------|---------------------|---------------------|
| google_books | search | 10 | 10 | 100.00 | 456.50 |
| gemini | vision_analysis | 2 | 2 | 100.00 | 27834.25 |

**Run Test Query 3: Cache Effectiveness**
```sql
SELECT
  blob3 as worker,
  blob1 as operation,
  COUNT(*) as total_operations,
  SUM(CASE WHEN double1 = 1 THEN 1 ELSE 0 END) as hits,
  SUM(CASE WHEN double1 = 0 THEN 1 ELSE 0 END) as misses,
  ROUND(100.0 * SUM(double1) / COUNT(*), 2) as hit_rate_percent
FROM books_api_cache_metrics
WHERE timestamp > NOW() - INTERVAL '1' HOUR
  AND blob1 = 'get'
GROUP BY worker, operation
ORDER BY hit_rate_percent DESC;
```

**Expected results:**
| worker | operation | total_operations | hits | misses | hit_rate_percent |
|--------|-----------|------------------|------|--------|------------------|
| books-api-proxy | get | 15 | 12 | 3 | 80.00 |

**If NO data appears:**
1. Wait another 5 minutes (ingestion delay)
2. Verify you triggered traffic (see step 2)
3. Check worker logs are showing 🚀 emoji (means structured logging is active)

---

### 4. iOS App Integration Test (5 minutes)

**From iOS app**, perform these operations:

**Test 1: Search**
1. Open BooksTrack app
2. Go to Search tab
3. Search for "Stephen King"
4. Watch logs in Terminal 1 (books-api-proxy)

**Expected logs:**
```
🚀 PERF [books-api-proxy] rpc_searchBooks: 189ms { query: 'Stephen King', resultsCount: 25 }
📊 CACHE [books-api-proxy] ✅ HIT get title:stephen_king:40:0 (8ms, 12048b)
```

**Test 2: Bookshelf Scan**
1. Go to Settings → Scan Bookshelf
2. Upload a bookshelf image
3. Watch logs in Terminal 2 (bookshelf-ai-worker)

**Expected logs:**
```
🚀 PERF [bookshelf-ai-worker] scanBookshelf: 28456ms { detectedCount: 12, readableCount: 10, provider: 'gemini' }
🌐 PROVIDER [bookshelf-ai-worker] ✅ SUCCESS gemini/vision_analysis: 27834ms
```

**Test 3: CSV Import with Enrichment**
1. Import a small CSV (5-10 books)
2. Watch logs in all terminals

**Expected flow:**
```
Terminal 1 (books-api-proxy):
🚀 PERF [books-api-proxy] rpc_startBatchEnrichment: 45678ms { jobId: 'abc123', workIdsCount: 10, success: true }

Terminal 3 (external-apis-worker):
🌐 PROVIDER [external-apis-worker] ✅ SUCCESS google_books/search: 456ms
🌐 PROVIDER [external-apis-worker] ✅ SUCCESS google_books/search: 389ms
... (repeats for each book)
```

---

### 5. Logpush Verification (15 minutes after setup)

**If you configured Logpush** (see LOGPUSH_SETUP_GUIDE.md):

```bash
# Check if logs are flowing to R2
wrangler r2 object list personal-library-data --prefix logs/

# Expected output:
# logs/books-api-proxy/2025/10/23/20251023T200000Z-20251023T200500Z.log.gz
# logs/bookshelf-ai-worker/2025/10/23/20251023T200000Z-20251023T200500Z.log.gz
# ... more files

# Download and inspect a log file
wrangler r2 object get personal-library-data \
  logs/books-api-proxy/2025/10/23/20251023T200000Z-20251023T200500Z.log.gz \
  --file recent-logs.gz

# Decompress and view
gunzip recent-logs.gz
cat recent-logs | jq '.' | head -20

# Look for structured logs
cat recent-logs | jq '.logs[] | select(.message | contains("🚀"))'
```

---

## Troubleshooting

### No Emoji Logs (🚀, 📊, 🌐)

**Issue:** Only seeing plain console.log messages, no structured logging

**Fix:**
```bash
# Verify worker versions are latest
wrangler deployments list --name books-api-proxy | head -5
# Should show deployment from today (Oct 23, 2025)

# Redeploy if needed
cd cloudflare-workers/books-api-proxy
wrangler deploy
```

### Analytics Engine Shows No Data

**Issue:** Queries return empty results after 15+ minutes

**Possible causes:**
1. **No traffic triggered** - Run tests from step 2
2. **Ingestion delay** - Wait up to 10 minutes
3. **Dataset names wrong** - Verify dataset names in query match wrangler.toml

**Verify datasets exist:**
```bash
# Check wrangler.toml has correct bindings
grep -A 2 "analytics_engine_datasets" cloudflare-workers/books-api-proxy/wrangler.toml

# Should show:
# [[analytics_engine_datasets]]
# binding = "PERFORMANCE_ANALYTICS"
# dataset = "books_api_performance"
```

### Cache Logs Not Appearing

**Issue:** No 📊 CACHE logs despite search requests

**Cause:** Only `handleAuthorSearch` has cache tracking currently

**Fix:** Search by author specifically:
```bash
curl "https://books-api-proxy.jukasdrj.workers.dev/search/author?q=stephen%20king"
```

### Wrangler Tail Times Out

**Issue:** `wrangler tail` shows no output

**Fix:**
```bash
# Verify wrangler is authenticated
wrangler whoami

# Try with explicit timeout
wrangler tail books-api-proxy --format pretty &
# Let it run in background, trigger traffic, then check output
```

---

## Success Criteria

✅ **Phase A Success:**
- [ ] All 6 workers show DEBUG-level console.log output
- [ ] wrangler tail shows detailed method entry/exit logs
- [ ] Can trace request flow through multiple workers

✅ **Phase B Success:**
- [ ] See 🚀 PERF logs with timing data
- [ ] See 🌐 PROVIDER logs with success/failure
- [ ] See 📊 CACHE logs with hit/miss (author searches)
- [ ] Analytics Engine queries return data after 10 minutes
- [ ] All 3 datasets have data (performance, provider, cache)

✅ **Logpush Success (if configured):**
- [ ] R2 bucket has logs/ directory with subdirectories per worker
- [ ] New log files appear every 5 minutes
- [ ] Can download and decompress logs with wrangler r2

---

## Next Steps After Verification

1. **Set up alerts** for provider failure rates > 5%
2. **Create custom dashboards** using Analytics Engine API
3. **Implement log rotation** (delete logs older than 30 days)
4. **Add cache tracking** to other search handlers (title, ISBN)
5. **Monitor costs** in R2 billing (should be < $2/month)

**Logging infrastructure is production-ready!** 🎉📊
