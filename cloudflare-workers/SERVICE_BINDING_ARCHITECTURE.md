# Cloudflare Workers Service Binding Architecture

**Last Updated:** October 23, 2025

## Overview

BooksTrack uses Cloudflare Workers RPC service bindings for efficient worker-to-worker communication. This document describes the current architecture after the circular dependency fix.

## Worker Dependency Graph

```
                           ┌─────────────────────┐
                           │  iOS App (Client)   │
                           └──────────┬──────────┘
                                      │
                                      │ HTTPS/WebSocket
                                      ▼
                           ┌──────────────────────┐
                           │  books-api-proxy     │
                           │  (Main Orchestrator) │
                           └──┬────────┬──────┬───┘
                              │        │      │
            ┌─────────────────┘        │      └────────────────────┐
            │                          │                           │
            │ RPC                      │ RPC                       │ DO
            ▼                          ▼                           ▼
┌───────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ enrichment-worker     │  │ external-apis-worker │  │ progress-websocket-  │
│                       │  │                      │  │ durable-object       │
└───────┬───────────────┘  └──────────────────────┘  └──────────────────────┘
        │                           ▲
        │ RPC                       │
        └───────────────────────────┘
                (no circular dependency!)
```

## Service Bindings

### books-api-proxy

**Binds To:**
- `ENRICHMENT_WORKER` → `enrichment-worker` (RPC)
- `EXTERNAL_APIS_WORKER` → `external-apis-worker` (RPC)
- `PROGRESS_WEBSOCKET_DO` → `progress-websocket-durable-object` (Durable Object)

**Exposes:** `BooksAPIProxyWorker` entrypoint with RPC methods:
- `searchBooks(query, options)` - General search
- `searchByAuthor(authorName, options)` - Author bibliography
- `searchByISBN(isbn, options)` - ISBN lookup
- `advancedSearch(criteria, options)` - Multi-criteria search
- `startBatchEnrichment(jobId, workIds, options)` - Batch enrichment with WebSocket progress

### enrichment-worker

**Binds To:**
- `EXTERNAL_APIS_WORKER` → `external-apis-worker` (RPC)

**Exposes:** `EnrichmentWorker` entrypoint with RPC methods:
- `enrichBatch(jobId, workIds, progressCallback, options)` - Batch enrichment with callback

**Critical Design:** Does NOT bind back to `books-api-proxy`. Uses callback pattern for progress updates.

### external-apis-worker

**Binds To:** None (leaf node in dependency tree)

**Exposes:** `ExternalAPIsWorker` entrypoint with RPC methods:
- `searchBooks(query, options)` - Query Google Books + OpenLibrary + ISBNdb
- `searchByISBN(isbn, options)` - ISBN-specific search
- `searchByAuthor(authorName, options)` - Author-specific search

## Progress Update Flow (Fixed Architecture)

### Before (Circular Dependency - BROKEN):
```
Client → books-api-proxy → enrichment-worker → books-api-proxy (❌ CIRCULAR!)
                                                     ↓
                                          progress-websocket-DO
```

### After (Callback Pattern - FIXED):
```
Client → books-api-proxy (EnrichmentCoordinator)
              ├─→ enrichment-worker.enrichBatch(jobId, workIds, callback, options)
              │       └─→ calls callback(progressData) for each work
              │
              └─→ callback pushes to progress-websocket-DO
```

**Key Innovation:** The `books-api-proxy` creates a progress callback function that captures the Durable Object stub. The enrichment worker calls this callback without knowing about WebSocket implementation.

## RPC Method Signatures

### books-api-proxy.startBatchEnrichment

```javascript
/**
 * Start batch enrichment with WebSocket progress
 * @param {string} jobId - Unique job identifier for WebSocket tracking
 * @param {string[]} workIds - Array of ISBNs or "title|author" strings
 * @param {Object} options - { maxRetries: 3, timeout: 30000 }
 * @returns {Promise<Object>} { success, processedCount, totalCount, enrichedWorks }
 */
async startBatchEnrichment(jobId, workIds, options)
```

### enrichment-worker.enrichBatch

```javascript
/**
 * Enrich batch of works with progress callback
 * @param {string} jobId - Job identifier
 * @param {string[]} workIds - Work identifiers (ISBN or title|author)
 * @param {Function} progressCallback - async (progressData) => void
 * @param {Object} options - Enrichment configuration
 * @returns {Promise<Object>} { success, processedCount, totalCount, enrichedWorks }
 */
async enrichBatch(jobId, workIds, progressCallback, options)
```

### external-apis-worker.searchBooks

```javascript
/**
 * Search multiple providers (Google Books + OpenLibrary + ISBNdb)
 * @param {string} query - Search query
 * @param {Object} options - { maxResults: 20, page: 0, includeMetadata: true }
 * @returns {Promise<Object>} { items: [...], totalResults, provider, orchestrated }
 */
async searchBooks(query, options)
```

## Deployment Order

When deploying workers with service bindings, deploy in dependency order:

```bash
# 1. Deploy leaf workers first (no dependencies)
cd cloudflare-workers/external-apis-worker
npm run deploy

cd ../progress-websocket-durable-object
npm run deploy

# 2. Deploy workers that depend on leaf workers
cd ../enrichment-worker
npm run deploy

# 3. Deploy root orchestrator last
cd ../books-api-proxy
npm run deploy
```

## Testing Service Bindings

### Test External APIs Worker

```bash
curl "https://external-apis-worker.jukasdrj.workers.dev/search?q=Harry%20Potter"
```

### Test Enrichment via Proxy (RPC)

```javascript
// From books-api-proxy context
const result = await env.ENRICHMENT_WORKER.enrichBatch(
  'test-job-123',
  ['9780439708180', '9780439064873'],
  async (progress) => console.log('Progress:', progress),
  {}
);
```

### Test Full WebSocket Flow

1. Connect to WebSocket: `wss://books-api-proxy.jukasdrj.workers.dev/ws/progress?jobId=test-123`
2. Call RPC: `env.BOOKS_API_PROXY.startBatchEnrichment('test-123', [...])`
3. Observe real-time progress messages in WebSocket

## Debugging

### Check Service Binding Health

```bash
# Verify bindings are configured
wrangler tail books-api-proxy --format pretty | grep "ENRICHMENT_WORKER"
wrangler tail enrichment-worker --format pretty | grep "EXTERNAL_APIS_WORKER"

# Test RPC calls
wrangler tail books-api-proxy --format pretty | grep "rpc_"
```

### Common Issues

**Error: "BOOKS_API_PROXY is not defined"**
- Cause: Circular dependency still exists
- Fix: Verify `enrichment-worker/wrangler.toml` has NO `BOOKS_API_PROXY` binding

**Error: "Service binding not found"**
- Cause: Workers deployed out of order
- Fix: Redeploy in dependency order (external-apis → enrichment → books-api-proxy)

**Error: "RPC method not found"**
- Cause: Entrypoint class missing or method not exported
- Fix: Verify `export class WorkerName` and method is public

## Architecture Principles

1. **No Circular Dependencies:** Workers form a directed acyclic graph (DAG)
2. **Callback for Progress:** Use function callbacks, not reverse RPC calls
3. **Leaf Workers Are Pure:** external-apis-worker has zero dependencies
4. **Orchestrator Manages State:** books-api-proxy owns WebSocket and coordination
5. **RPC Over HTTP:** Internal communication uses service bindings, not fetch()
