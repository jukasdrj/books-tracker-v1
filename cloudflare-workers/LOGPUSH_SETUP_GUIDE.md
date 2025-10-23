# Logpush to R2 Setup Guide

**Goal:** Archive all worker logs to R2 bucket for unlimited retention

**Time:** 5-10 minutes (one-time setup per worker)

**Cost:** FREE (R2 storage charges apply: ~$1-2/month)

---

## Step 1: Navigate to Logpush

1. Open https://dash.cloudflare.com
2. Select your account
3. Click **Analytics & Logs** in left sidebar
4. Click **Logs** → **Logpush**
5. Click **Create Logpush job** button

---

## Step 2: Create Logpush Jobs (One Per Worker)

Create **6 separate jobs** using these settings:

### Job 1: books-api-proxy

**Basic Settings:**
- **Dataset:** Workers Trace Events
- **Worker name:** `books-api-proxy`

**Destination:**
- **Type:** Cloudflare R2
- **Bucket:** `personal-library-data` (already exists)
- **Path prefix:** `logs/books-api-proxy/`
- **Organized by:** Date (YYYY/MM/DD format recommended)

**Advanced Settings:**
- **Frequency:** Every 5 minutes (maximum freshness)
- **Fields:** Select all available fields (recommended)
- **Compression:** Gzip (recommended, saves storage costs)

Click **Create**.

---

### Job 2: bookshelf-ai-worker

**Same settings as Job 1, except:**
- **Worker name:** `bookshelf-ai-worker`
- **Path prefix:** `logs/bookshelf-ai-worker/`

---

### Job 3: enrichment-worker

**Same settings as Job 1, except:**
- **Worker name:** `enrichment-worker`
- **Path prefix:** `logs/enrichment-worker/`

---

### Job 4: external-apis-worker

**Same settings as Job 1, except:**
- **Worker name:** `external-apis-worker`
- **Path prefix:** `logs/external-apis-worker/`

---

### Job 5: personal-library-cache-warmer

**Same settings as Job 1, except:**
- **Worker name:** `personal-library-cache-warmer`
- **Path prefix:** `logs/cache-warmer/`

---

### Job 6: progress-websocket-durable-object

**Same settings as Job 1, except:**
- **Worker name:** `progress-websocket-durable-object`
- **Path prefix:** `logs/websocket-do/`

---

## Step 3: Verify Logpush is Working

**Wait 10 minutes** after creating jobs, then check for log files:

```bash
# List all logs
wrangler r2 object list personal-library-data --prefix logs/

# Expected output:
# logs/books-api-proxy/2025/10/23/20251023T140000Z-20251023T140500Z.log.gz
# logs/bookshelf-ai-worker/2025/10/23/20251023T140000Z-20251023T140500Z.log.gz
# ... (more files)

# Check specific worker logs
wrangler r2 object list personal-library-data --prefix logs/books-api-proxy/

# View a specific log file
wrangler r2 object get personal-library-data logs/books-api-proxy/2025/10/23/20251023T140000Z-20251023T140500Z.log.gz --file recent-logs.gz
gunzip recent-logs.gz
cat recent-logs | jq '.' | head -50
```

---

## Step 4: Query Historical Logs

**After Logpush is active, you can analyze historical data:**

```bash
# Download last 24 hours of logs from books-api-proxy
wrangler r2 object list personal-library-data --prefix logs/books-api-proxy/$(date +%Y/%m/%d)/ | \
  while read file; do
    wrangler r2 object get personal-library-data "$file" --file "${file##*/}"
  done

# Combine and analyze
gunzip *.log.gz
cat *.log | jq 'select(.outcome == "exception")' | jq .
# Shows all exceptions across the day
```

---

## Expected Log Structure

Each log entry contains:

```json
{
  "timestamp": "2025-10-23T14:05:23.456Z",
  "event": {
    "request": {
      "url": "https://books-api-proxy.jukasdrj.workers.dev/search/author",
      "method": "POST",
      "headers": {...}
    },
    "response": {
      "status": 200
    }
  },
  "outcome": "ok",
  "scriptName": "books-api-proxy",
  "logs": [
    {
      "message": "🚀 PERF [books-api-proxy] rpc_searchByAuthor: 234ms",
      "level": "log",
      "timestamp": "2025-10-23T14:05:23.678Z"
    },
    {
      "message": "📊 CACHE [books-api-proxy] ✅ HIT get author:stephen_king:20:0 (12ms, 4096b)",
      "level": "log",
      "timestamp": "2025-10-23T14:05:23.690Z"
    }
  ],
  "exceptions": [],
  "cpuTime": 234,
  "wallTime": 456
}
```

---

## Storage Estimates

**Compression:** Gzip reduces log size by ~80-90%

**Estimated sizes (per worker, per day):**
- `books-api-proxy`: 50-100 MB (main traffic)
- `bookshelf-ai-worker`: 10-20 MB (AI scans)
- `enrichment-worker`: 5-10 MB (batch enrichment)
- `external-apis-worker`: 20-40 MB (provider calls)
- `cache-warmer`: 1-2 MB (cron jobs)
- `websocket-do`: 5-10 MB (WebSocket events)

**Total per day:** ~100-200 MB compressed
**Total per month:** ~3-6 GB
**Monthly cost:** $0.045 - $0.09 (at $0.015/GB)

**Retention strategy:**
- Keep last 30 days: ~$0.09/month
- Keep last 90 days: ~$0.27/month
- Keep forever: Scales linearly

---

## Troubleshooting

**No logs appearing after 15 minutes:**

1. Check Logpush job status in dashboard
2. Verify R2 bucket permissions
3. Check worker is receiving traffic:
   ```bash
   wrangler tail books-api-proxy --format pretty
   # Trigger some requests, verify you see output
   ```

**Logs are huge / too expensive:**

1. Reduce frequency from 5 min to 30 min
2. Filter fields (select only essential fields)
3. Implement log rotation (delete logs older than 30 days)

**Can't find specific error:**

Use `jq` to filter:
```bash
# Find all errors
cat logs/*.log | jq 'select(.outcome == "exception")'

# Find slow requests (>5 seconds)
cat logs/*.log | jq 'select(.wallTime > 5000)'

# Find specific worker
cat logs/*.log | jq 'select(.scriptName == "books-api-proxy")'
```

---

## Next Steps

After Logpush is configured:

1. ✅ Wait 10 minutes and verify logs are flowing
2. ✅ Set up automated log rotation (delete old logs)
3. ✅ Create alerts for exception spikes
4. ✅ Build custom log analysis scripts

**You now have permanent, queryable log history!** 🎉
