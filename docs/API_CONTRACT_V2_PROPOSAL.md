# BooksTrack API Contract v2.0 - Migration Proposal

**Status:** PROPOSAL
**Date:** 2025-01-22
**Authors:** Development Team
**Target Implementation:** Q1 2025

---

## Executive Summary

This proposal outlines a migration from WebSocket-based communication to a modern, hybrid HTTP/SSE approach optimized for Cloudflare Workers infrastructure. The new contract provides better reliability, simpler state management, and improved battery efficiency for mobile clients.

**Key Changes:**
- **Barcode Enrichment:** WebSocket → Synchronous HTTP
- **CSV Import:** WebSocket → Async Job Pattern with SSE streaming
- **Migration Period:** 60-day dual-support phase

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [API Contract Specification](#api-contract-specification)
3. [Cloudflare Infrastructure](#cloudflare-infrastructure)
4. [Implementation Checklist](#implementation-checklist)
5. [Migration Strategy](#migration-strategy)
6. [Testing Plan](#testing-plan)

---

## Architecture Overview

### Current State (v1.x - WebSocket-based)

```
iOS Client                    Cloudflare Worker
    |                               |
    |---- WebSocket Connect ------->|
    |                               |
    |---- barcode enrichment ------>|
    |<--- progress events ----------|
    |                               |
    |---- CSV import -------------->|
    |<--- progress events ----------|
    |                               |
    [Connection must stay alive]
    [Complex reconnection logic]
    [State management challenges]
```

**Problems:**
- Connection instability on network transitions (WiFi <-> cellular)
- Battery drain from persistent connection
- Complex state management during reconnections
- App backgrounding breaks connection
- Firewall/proxy compatibility issues

---

### Proposed State (v2.0 - Hybrid HTTP/SSE)

```
FLOW 1: Barcode Enrichment (HTTP Request-Response)
=========================================================
iOS Client                    Cloudflare Worker
    |                               |
    |---- POST /api/v2/books/enrich -->|
    |     { "barcode": "9780..." }  |
    |                               |
    |                          [Orchestrate]
    |                          [Google Books]
    |                          [OpenLibrary]
    |                               |
    |<--- 200 OK -------------------|
    |     { "title": "...", ... }   |
    |                               |
    [Stateless, reliable, cacheable]


FLOW 2: CSV Import (Async Job + SSE Streaming)
=========================================================
iOS Client          Worker (API)    Durable Object    Queue    Worker (Consumer)
    |                   |                 |             |            |
    |-- POST /imports -->|                 |             |            |
    |                   |                 |             |            |
    |                   |-- Create Job -->|             |            |
    |                   |                 |             |            |
    |                   |-- Upload CSV -----------------> R2         |
    |                   |                 |             |            |
    |                   |-- Enqueue Job -------------->|             |
    |                   |                 |             |            |
    |<-- 202 Accepted --|                 |             |            |
    |   { job_id }      |                 |             |            |
    |                   |                 |             |            |
    |-- GET /stream --->|                 |             |            |
    |<-- SSE events ----|<-- Progress ----|<-- Update --|-- Process -|
    |   progress 10%    |                 |             |    rows    |
    |   progress 50%    |                 |             |            |
    |   complete        |                 |             |            |
    |                   |                 |             |            |
    [Auto-reconnect]    [Stateless]   [Stateful]    [Background]

FALLBACK: If SSE fails after 3 retries, use polling:
    |-- GET /imports/{job_id} (every 10s)
    |<-- { "progress": 0.5, ... }
```

**Benefits:**
- **Reliability:** HTTP survives network transitions, no persistent state
- **Battery:** SSE/polling allows radio sleep between updates
- **Simplicity:** Stateless API, automatic reconnection (SSE spec)
- **Scalability:** Cloudflare edge handles load, Durable Objects scale automatically
- **Compatibility:** Works through firewalls/proxies where WebSockets fail

---

## API Contract Specification

### 1. Barcode Enrichment API

**Use Case:** User scans a barcode, app requests book metadata enrichment

#### Endpoint: `POST /api/v2/books/enrich`

**Request Headers:**
```
Content-Type: application/json
Authorization: Bearer <token>
```

**Request Body:**
```json
{
  "barcode": "9780747532743",
  "prefer_provider": "auto"  // "google" | "openlibrary" | "auto" (optional)
}
```

**Response: 200 OK**
```json
{
  "isbn": "9780747532743",
  "title": "Harry Potter and the Philosopher's Stone",
  "authors": ["J.K. Rowling"],
  "publisher": "Bloomsbury",
  "published_date": "1997-06-26",
  "page_count": 223,
  "cover_url": "https://books.google.com/books/content?id=...",
  "description": "Harry Potter has never been...",
  "categories": ["Fiction", "Fantasy"],
  "language": "en",
  "provider": "orchestrated:google+openlibrary",
  "enriched_at": "2025-01-22T10:30:00Z"
}
```

**Response: 404 Not Found**
```json
{
  "error": "book_not_found",
  "message": "No book data found for ISBN 9780747532743",
  "barcode": "9780747532743",
  "providers_checked": ["google", "openlibrary"]
}
```

**Response: 429 Too Many Requests**
```json
{
  "error": "rate_limit_exceeded",
  "message": "Rate limit of 1000 requests per hour exceeded",
  "retry_after": 3600,
  "limit": 1000,
  "remaining": 0,
  "reset_at": "2025-01-22T11:00:00Z"
}
```

**Response: 503 Service Unavailable**
```json
{
  "error": "providers_unavailable",
  "message": "All book metadata providers are currently unavailable",
  "providers": {
    "google": { "status": "timeout", "latency_ms": 5000 },
    "openlibrary": { "status": "error", "error": "500 Internal Server Error" }
  },
  "retry_after": 60
}
```

**Error Codes:**
- `400` - Invalid barcode format
- `401` - Unauthorized (missing/invalid token)
- `404` - Book not found in any provider
- `429` - Rate limit exceeded
- `503` - All providers unavailable

**Rate Limits:**
- 1000 requests per hour per user
- 100 requests per minute per user (burst)

---

### 2. CSV Import API

**Use Case:** User uploads CSV file with 50-500 books for bulk import

#### 2a. Initiate Import

**Endpoint:** `POST /api/v2/imports`

**Request Headers:**
```
Content-Type: multipart/form-data
Authorization: Bearer <token>
```

**Request Body (multipart/form-data):**
```
file: <CSV binary data>
options: {
  "auto_enrich": true,        // Auto-fetch metadata for ISBNs
  "skip_duplicates": true,    // Skip books already in library
  "batch_size": 50            // Rows per batch (optional, default: 50)
}
```

**CSV Format Expected:**
```csv
isbn,title,author,publisher,published_date,read_status
9780747532743,Harry Potter,J.K. Rowling,Bloomsbury,1997-06-26,read
9780141439518,Pride and Prejudice,Jane Austen,Penguin,2003-04-29,unread
```

**Response: 202 Accepted**
```json
{
  "job_id": "import_abc123def456",
  "status": "queued",
  "created_at": "2025-01-22T10:30:00Z",
  "sse_url": "/api/v2/imports/import_abc123def456/stream",
  "status_url": "/api/v2/imports/import_abc123def456",
  "file_size_bytes": 15234,
  "estimated_rows": 150
}
```

**Response: 400 Bad Request**
```json
{
  "error": "invalid_csv",
  "message": "CSV file is missing required column: isbn",
  "required_columns": ["isbn"],
  "found_columns": ["title", "author"]
}
```

**Response: 413 Payload Too Large**
```json
{
  "error": "file_too_large",
  "message": "CSV file exceeds maximum size of 50 MB",
  "max_size_mb": 50,
  "received_size_mb": 75
}
```

---

#### 2b. Get Import Status (Polling Fallback)

**Endpoint:** `GET /api/v2/imports/{job_id}`

**Request Headers:**
```
Authorization: Bearer <token>
```

**Response: 200 OK (Queued)**
```json
{
  "job_id": "import_abc123def456",
  "status": "queued",
  "progress": 0.0,
  "total_rows": 150,
  "processed_rows": 0,
  "successful_rows": 0,
  "failed_rows": 0,
  "created_at": "2025-01-22T10:30:00Z",
  "started_at": null,
  "completed_at": null,
  "error": null,
  "result_summary": null
}
```

**Response: 200 OK (Processing)**
```json
{
  "job_id": "import_abc123def456",
  "status": "processing",
  "progress": 0.67,
  "total_rows": 150,
  "processed_rows": 100,
  "successful_rows": 95,
  "failed_rows": 5,
  "created_at": "2025-01-22T10:30:00Z",
  "started_at": "2025-01-22T10:30:05Z",
  "completed_at": null,
  "error": null,
  "result_summary": null,
  "current_batch": {
    "batch_number": 2,
    "batch_size": 50,
    "batch_start_row": 51,
    "batch_end_row": 100
  }
}
```

**Response: 200 OK (Complete)**
```json
{
  "job_id": "import_abc123def456",
  "status": "complete",
  "progress": 1.0,
  "total_rows": 150,
  "processed_rows": 150,
  "successful_rows": 145,
  "failed_rows": 5,
  "created_at": "2025-01-22T10:30:00Z",
  "started_at": "2025-01-22T10:30:05Z",
  "completed_at": "2025-01-22T10:35:12Z",
  "error": null,
  "result_summary": {
    "books_created": 120,
    "books_updated": 25,
    "duplicates_skipped": 5,
    "enrichment_succeeded": 140,
    "enrichment_failed": 5,
    "errors": [
      {
        "row": 42,
        "isbn": "invalid",
        "error": "Invalid ISBN format"
      }
    ]
  }
}
```

**Response: 200 OK (Failed)**
```json
{
  "job_id": "import_abc123def456",
  "status": "failed",
  "progress": 0.3,
  "total_rows": 150,
  "processed_rows": 45,
  "successful_rows": 40,
  "failed_rows": 5,
  "created_at": "2025-01-22T10:30:00Z",
  "started_at": "2025-01-22T10:30:05Z",
  "completed_at": "2025-01-22T10:31:00Z",
  "error": "CSV parsing failed at row 46: unexpected end of file",
  "result_summary": null
}
```

**Response: 404 Not Found**
```json
{
  "error": "job_not_found",
  "message": "Import job import_abc123def456 not found or expired",
  "job_id": "import_abc123def456"
}
```

**Job Lifecycle:**
- `queued` → Job accepted, waiting to start
- `processing` → Actively processing rows
- `complete` → All rows processed successfully
- `failed` → Job failed due to unrecoverable error

**Job Retention:**
- Jobs expire after 24 hours
- Completed jobs remain queryable for 24 hours
- Failed jobs remain queryable for 7 days (for debugging)

---

#### 2c. Stream Import Progress (SSE)

**Endpoint:** `GET /api/v2/imports/{job_id}/stream`

**Request Headers:**
```
Accept: text/event-stream
Authorization: Bearer <token>
Cache-Control: no-cache
```

**SSE Event Stream:**

```
: connection established
retry: 5000

event: queued
data: {"status": "queued", "job_id": "import_abc123def456"}

event: started
data: {"status": "processing", "total_rows": 150, "started_at": "2025-01-22T10:30:05Z"}

event: progress
data: {"progress": 0.1, "processed_rows": 15, "successful_rows": 14, "failed_rows": 1}

event: progress
data: {"progress": 0.5, "processed_rows": 75, "successful_rows": 72, "failed_rows": 3}

event: progress
data: {"progress": 0.9, "processed_rows": 135, "successful_rows": 130, "failed_rows": 5}

event: complete
data: {"status": "complete", "progress": 1.0, "result_summary": {"books_created": 145, "books_updated": 0, "duplicates_skipped": 5, "enrichment_succeeded": 140, "enrichment_failed": 5}}

: connection closed
```

**Error Event (if job fails):**
```
event: error
data: {"status": "failed", "error": "CSV parsing failed at row 42: invalid ISBN", "processed_rows": 41}
```

**SSE Connection Lifecycle:**
1. Client connects with `Accept: text/event-stream`
2. Server sends progress events as job processes
3. Connection auto-closes on job completion/failure
4. Client auto-reconnects on disconnect (built into SSE spec)
5. After 3 failed reconnection attempts, client falls back to polling

**Reconnection Behavior:**
```
: retry: 5000

Client disconnects at progress 50%
Client reconnects with Last-Event-ID header
Server resumes from last event:

event: progress
data: {"progress": 0.5, "processed_rows": 75, ...}

event: progress
data: {"progress": 0.6, "processed_rows": 90, ...}
```

**SSE vs Polling Decision Tree:**
```
Client initiates import
    |
    v
Try SSE connection
    |
    +-- Success? --> Use SSE (real-time progress)
    |
    +-- Fail? --> Retry SSE (up to 3 attempts)
                    |
                    +-- Still failing? --> Fall back to polling
                                            (GET /imports/{job_id} every 10s)
```

---

### 3. Capability Discovery API

**Use Case:** Client detects server capabilities and API version

#### Endpoint: `GET /api/v2/capabilities`

**Request Headers:**
```
Authorization: Bearer <token> (optional)
```

**Response: 200 OK**
```json
{
  "api_version": "2.0",
  "server_time": "2025-01-22T10:30:00Z",
  "features": {
    "barcode_enrichment": {
      "supported": true,
      "endpoint": "/api/v2/books/enrich",
      "providers": ["google", "openlibrary"],
      "rate_limit": {
        "requests_per_hour": 1000,
        "burst": 100
      }
    },
    "csv_import": {
      "supported": true,
      "endpoint": "/api/v2/imports",
      "sse_support": true,
      "max_file_size_mb": 50,
      "max_rows": 10000,
      "supported_columns": ["isbn", "title", "author", "publisher", "published_date", "read_status"]
    },
    "websocket": {
      "supported": true,
      "deprecated": true,
      "sunset_date": "2025-03-22",
      "migration_guide_url": "https://docs.bookstrack.app/api/v2-migration"
    }
  },
  "region": "auto",
  "cloudflare_ray_id": "abc123def456"
}
```

**Client Usage:**
```swift
// Client checks capabilities on app launch
let capabilities = await api.getCapabilities()

if capabilities.features.csvImport.sseSupport {
    // Use SSE for real-time progress
    useSSEForImport()
} else {
    // Fall back to polling
    usePollingForImport()
}

if capabilities.features.websocket.deprecated {
    // Show migration banner to user
    showDeprecationNotice(sunsetDate: capabilities.features.websocket.sunsetDate)
}
```

---

## Cloudflare Infrastructure

### Architecture Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     Cloudflare Edge Network                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │  Worker (API)    │────────>│ Durable Object   │             │
│  │  - HTTP Routes   │         │ - Job State      │             │
│  │  - Auth          │         │ - Progress Track │             │
│  │  - Validation    │         │ - SSE Broadcast  │             │
│  └──────────────────┘         └──────────────────┘             │
│         │                               │                        │
│         v                               v                        │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │  R2 Storage      │         │  Queue           │             │
│  │  - CSV Files     │         │  - Job Queue     │             │
│  │  - Temp Data     │         │  - Batch Process │             │
│  └──────────────────┘         └──────────────────┘             │
│                                        │                         │
│                                        v                         │
│                               ┌──────────────────┐              │
│                               │ Worker (Consumer)│              │
│                               │ - CSV Parser     │              │
│                               │ - Enrichment     │              │
│                               │ - Progress Update│              │
│                               └──────────────────┘              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Component Details

#### 1. Worker (API Gateway)

**Responsibilities:**
- Handle HTTP requests (barcode enrichment, CSV upload)
- Validate authentication tokens
- Route requests to appropriate handlers
- Create Durable Object instances for import jobs
- Upload CSV files to R2
- Enqueue import jobs to Queue

**Implementation:**
```javascript
// wrangler.toml
name = "bookstrack-api"
main = "src/index.js"
compatibility_date = "2025-01-22"

[durable_objects]
bindings = [
  { name = "IMPORT_JOB", class_name = "ImportJob" }
]

[[r2_buckets]]
binding = "CSV_BUCKET"
bucket_name = "bookstrack-csv-imports"

[[queues.producers]]
queue = "import-jobs"
binding = "IMPORT_QUEUE"

[[queues.consumers]]
queue = "import-jobs"
max_batch_size = 10
max_batch_timeout = 30
```

```javascript
// src/index.js
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Route: POST /api/v2/books/enrich
    if (url.pathname === '/api/v2/books/enrich' && request.method === 'POST') {
      return handleBarcodeEnrich(request, env);
    }

    // Route: POST /api/v2/imports
    if (url.pathname === '/api/v2/imports' && request.method === 'POST') {
      return handleImportUpload(request, env);
    }

    // Route: GET /api/v2/imports/{job_id}
    if (url.pathname.startsWith('/api/v2/imports/') && request.method === 'GET') {
      const jobId = url.pathname.split('/').pop();
      return handleImportStatus(jobId, env);
    }

    // Route: GET /api/v2/imports/{job_id}/stream
    if (url.pathname.endsWith('/stream') && request.method === 'GET') {
      const jobId = url.pathname.split('/')[4];
      return handleImportStream(jobId, env);
    }

    return new Response('Not Found', { status: 404 });
  }
};

async function handleBarcodeEnrich(request, env) {
  const { barcode, prefer_provider } = await request.json();

  // Orchestrate Google Books + OpenLibrary
  const [googleResult, openLibResult] = await Promise.allSettled([
    fetchGoogleBooks(barcode),
    fetchOpenLibrary(barcode)
  ]);

  // Merge results (prioritize Google Books)
  const enrichedData = mergeResults(googleResult, openLibResult);

  if (!enrichedData) {
    return Response.json({ error: 'book_not_found' }, { status: 404 });
  }

  return Response.json({
    ...enrichedData,
    provider: 'orchestrated:google+openlibrary',
    enriched_at: new Date().toISOString()
  });
}

async function handleImportUpload(request, env) {
  const formData = await request.formData();
  const file = formData.get('file');
  const options = JSON.parse(formData.get('options') || '{}');

  // Generate job ID
  const jobId = `import_${crypto.randomUUID()}`;

  // Upload CSV to R2
  await env.CSV_BUCKET.put(`${jobId}/input.csv`, file);

  // Create Durable Object for job state
  const jobStub = env.IMPORT_JOB.get(env.IMPORT_JOB.idFromName(jobId));
  await jobStub.fetch('http://internal/create', {
    method: 'POST',
    body: JSON.stringify({ jobId, options, fileSize: file.size })
  });

  // Enqueue job for processing
  await env.IMPORT_QUEUE.send({ jobId, options });

  return Response.json({
    job_id: jobId,
    status: 'queued',
    created_at: new Date().toISOString(),
    sse_url: `/api/v2/imports/${jobId}/stream`,
    status_url: `/api/v2/imports/${jobId}`
  }, { status: 202 });
}

async function handleImportStatus(jobId, env) {
  const jobStub = env.IMPORT_JOB.get(env.IMPORT_JOB.idFromName(jobId));
  const response = await jobStub.fetch('http://internal/status');
  return response;
}

async function handleImportStream(jobId, env) {
  const jobStub = env.IMPORT_JOB.get(env.IMPORT_JOB.idFromName(jobId));

  // Create SSE stream
  const { readable, writable } = new TransformStream();
  const writer = writable.getWriter();

  // Subscribe to job progress
  jobStub.fetch('http://internal/subscribe', {
    method: 'POST',
    body: JSON.stringify({ writer })
  });

  return new Response(readable, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    }
  });
}
```

---

#### 2. Durable Object (Import Job State)

**Responsibilities:**
- Store job metadata (status, progress, errors)
- Track progress updates from Queue consumer
- Broadcast progress to SSE subscribers
- Provide consistent job state across edge locations

**Implementation:**
```javascript
// src/import-job.js
export class ImportJob {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.subscribers = new Set();
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === '/create' && request.method === 'POST') {
      return this.create(request);
    }

    if (url.pathname === '/status') {
      return this.getStatus();
    }

    if (url.pathname === '/progress' && request.method === 'POST') {
      return this.updateProgress(request);
    }

    if (url.pathname === '/subscribe' && request.method === 'POST') {
      return this.subscribe(request);
    }

    return new Response('Not Found', { status: 404 });
  }

  async create(request) {
    const { jobId, options, fileSize } = await request.json();

    await this.state.storage.put('job', {
      jobId,
      status: 'queued',
      progress: 0.0,
      totalRows: 0,
      processedRows: 0,
      successfulRows: 0,
      failedRows: 0,
      createdAt: new Date().toISOString(),
      startedAt: null,
      completedAt: null,
      error: null,
      resultSummary: null,
      options
    });

    return Response.json({ success: true });
  }

  async getStatus() {
    const job = await this.state.storage.get('job');
    return Response.json(job);
  }

  async updateProgress(request) {
    const update = await request.json();
    const job = await this.state.storage.get('job');

    // Update job state
    const updatedJob = { ...job, ...update };
    await this.state.storage.put('job', updatedJob);

    // Broadcast to SSE subscribers
    this.broadcast({
      event: update.status === 'complete' ? 'complete' : 'progress',
      data: JSON.stringify(update)
    });

    return Response.json({ success: true });
  }

  async subscribe(request) {
    const { writer } = await request.json();
    this.subscribers.add(writer);

    // Send initial state
    const job = await this.state.storage.get('job');
    await writer.write(`event: ${job.status}\ndata: ${JSON.stringify(job)}\n\n`);

    return Response.json({ success: true });
  }

  broadcast(message) {
    const event = `event: ${message.event}\ndata: ${message.data}\n\n`;

    for (const writer of this.subscribers) {
      try {
        writer.write(event);
      } catch (err) {
        // Remove dead subscribers
        this.subscribers.delete(writer);
      }
    }
  }
}
```

---

#### 3. Queue Consumer (CSV Processing)

**Responsibilities:**
- Fetch CSV from R2
- Parse CSV in batches (50 rows per batch)
- Enrich each book with metadata
- Update Durable Object progress after each batch
- Handle errors and retries

**Implementation:**
```javascript
// src/queue-consumer.js
export default {
  async queue(batch, env) {
    for (const message of batch.messages) {
      const { jobId, options } = message.body;

      try {
        await processImportJob(jobId, options, env);
        message.ack();
      } catch (err) {
        console.error(`Job ${jobId} failed:`, err);
        message.retry();
      }
    }
  }
};

async function processImportJob(jobId, options, env) {
  // Fetch CSV from R2
  const csvData = await env.CSV_BUCKET.get(`${jobId}/input.csv`);
  const csvText = await csvData.text();

  // Parse CSV
  const rows = parseCSV(csvText);
  const totalRows = rows.length;

  // Get Durable Object
  const jobStub = env.IMPORT_JOB.get(env.IMPORT_JOB.idFromName(jobId));

  // Update: Started
  await jobStub.fetch('http://internal/progress', {
    method: 'POST',
    body: JSON.stringify({
      status: 'processing',
      totalRows,
      startedAt: new Date().toISOString()
    })
  });

  // Process in batches of 50
  const batchSize = options.batch_size || 50;
  let processedRows = 0;
  let successfulRows = 0;
  let failedRows = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);

    for (const row of batch) {
      try {
        // Enrich book metadata if auto_enrich enabled
        if (options.auto_enrich && row.isbn) {
          const enriched = await enrichBook(row.isbn);
          Object.assign(row, enriched);
        }

        // Save to database (via API call)
        await saveBook(row);
        successfulRows++;
      } catch (err) {
        failedRows++;
        errors.push({
          row: i + batch.indexOf(row) + 1,
          isbn: row.isbn,
          error: err.message
        });
      }

      processedRows++;
    }

    // Update progress after each batch
    await jobStub.fetch('http://internal/progress', {
      method: 'POST',
      body: JSON.stringify({
        progress: processedRows / totalRows,
        processedRows,
        successfulRows,
        failedRows
      })
    });
  }

  // Update: Complete
  await jobStub.fetch('http://internal/progress', {
    method: 'POST',
    body: JSON.stringify({
      status: 'complete',
      progress: 1.0,
      completedAt: new Date().toISOString(),
      resultSummary: {
        books_created: successfulRows,
        books_updated: 0,
        duplicates_skipped: failedRows,
        errors: errors.slice(0, 100) // Limit to first 100 errors
      }
    })
  });
}

function parseCSV(csvText) {
  // Simple CSV parser (use library in production)
  const lines = csvText.split('\n');
  const headers = lines[0].split(',');

  return lines.slice(1).map(line => {
    const values = line.split(',');
    return headers.reduce((obj, header, i) => {
      obj[header.trim()] = values[i]?.trim();
      return obj;
    }, {});
  });
}

async function enrichBook(isbn) {
  // Call barcode enrichment endpoint
  const response = await fetch('http://internal/api/v2/books/enrich', {
    method: 'POST',
    body: JSON.stringify({ barcode: isbn })
  });

  if (response.ok) {
    return await response.json();
  }

  throw new Error('Enrichment failed');
}

async function saveBook(book) {
  // Save to database (placeholder)
  console.log('Saving book:', book);
}
```

---

## Implementation Checklist

### Backend (Cloudflare Workers)

#### Phase 1: Core Infrastructure (Week 1)
- [ ] Set up Cloudflare Workers project with wrangler.toml
- [ ] Configure Durable Objects binding for ImportJob
- [ ] Configure R2 bucket for CSV storage
- [ ] Configure Queue for job processing
- [ ] Deploy initial Worker skeleton with routing

#### Phase 2: Barcode Enrichment (Week 1)
- [ ] Implement `POST /api/v2/books/enrich` endpoint
- [ ] Implement Google Books API orchestration
- [ ] Implement OpenLibrary API orchestration
- [ ] Implement result merging logic
- [ ] Add rate limiting (1000 req/hour per user)
- [ ] Add error handling for provider failures
- [ ] Add logging/monitoring with Cloudflare Analytics

#### Phase 3: CSV Import - Upload (Week 2)
- [ ] Implement `POST /api/v2/imports` endpoint
- [ ] Implement multipart/form-data CSV upload
- [ ] Validate CSV format and columns
- [ ] Upload CSV to R2 with job_id prefix
- [ ] Create Durable Object instance for job
- [ ] Enqueue job to Queue
- [ ] Return 202 Accepted with job_id and URLs

#### Phase 4: CSV Import - Processing (Week 2)
- [ ] Implement Queue consumer Worker
- [ ] Implement CSV parsing (batch size: 50)
- [ ] Implement batch processing with progress updates
- [ ] Update Durable Object progress after each batch
- [ ] Handle errors and failed rows
- [ ] Implement retry logic for transient failures
- [ ] Store result summary in Durable Object

#### Phase 5: CSV Import - Status/SSE (Week 2)
- [ ] Implement `GET /api/v2/imports/{job_id}` status endpoint
- [ ] Implement `GET /api/v2/imports/{job_id}/stream` SSE endpoint
- [ ] Implement SSE broadcasting in Durable Object
- [ ] Handle SSE reconnections with Last-Event-ID
- [ ] Implement SSE auto-close on job completion
- [ ] Add SSE connection lifecycle logging

#### Phase 6: Capabilities & Deprecation (Week 3)
- [ ] Implement `GET /api/v2/capabilities` endpoint
- [ ] Add deprecation headers to WebSocket endpoints
- [ ] Document WebSocket sunset date (60 days from deploy)
- [ ] Create migration guide documentation
- [ ] Set up monitoring for dual API usage

#### Phase 7: Testing & Monitoring (Week 3)
- [ ] Unit tests for enrichment orchestration
- [ ] Integration tests for CSV import flow
- [ ] Load testing with 1000+ row CSVs
- [ ] SSE connection stability testing
- [ ] Monitor Durable Object performance
- [ ] Monitor Queue processing latency
- [ ] Set up alerting for error rates

---

### Frontend (iOS Swift)

#### Phase 1: API Client Infrastructure (Week 3)
- [ ] Create `APIClientV2` class with URLSession
- [ ] Implement authentication token management
- [ ] Add request/response logging
- [ ] Implement retry logic with exponential backoff
- [ ] Add network reachability monitoring
- [ ] Create Codable models for all API responses

#### Phase 2: Barcode Enrichment Service (Week 3)
- [ ] Create `EnrichmentService` actor
- [ ] Implement `POST /api/v2/books/enrich` request
- [ ] Handle 200 OK (success) response
- [ ] Handle 404 Not Found (book not found)
- [ ] Handle 429 Rate Limit with retry-after
- [ ] Handle 503 Provider Unavailable with fallback
- [ ] Update UI with enriched book data
- [ ] Add loading indicator (5-30s wait)

#### Phase 3: CSV Import Upload (Week 4)
- [ ] Create `ImportJobService` actor
- [ ] Implement CSV file picker UI
- [ ] Validate CSV format before upload
- [ ] Implement `POST /api/v2/imports` multipart upload
- [ ] Show upload progress (URLSession uploadTask)
- [ ] Handle 202 Accepted response
- [ ] Store job_id for progress tracking
- [ ] Navigate to import progress view

#### Phase 4: SSE Client (Week 4)
- [ ] Add SwiftEventSource dependency (SPM)
- [ ] Create `SSEClient` class wrapping EventSource
- [ ] Implement `GET /api/v2/imports/{job_id}/stream`
- [ ] Parse SSE events: queued, started, progress, complete, error
- [ ] Update UI progress bar in real-time
- [ ] Handle SSE reconnections automatically
- [ ] Implement 3-retry limit before fallback

#### Phase 5: Polling Fallback (Week 4)
- [ ] Create `PollingClient` class with Timer
- [ ] Implement `GET /api/v2/imports/{job_id}` polling (10s interval)
- [ ] Parse status response and update UI
- [ ] Stop polling on completion/failure
- [ ] Switch from SSE to polling after 3 failed reconnects
- [ ] Add manual refresh button

#### Phase 6: Import Progress UI (Week 5)
- [ ] Create `ImportProgressView` SwiftUI view
- [ ] Show linear progress bar (0.0 to 1.0)
- [ ] Display processed_rows / total_rows
- [ ] Display successful_rows / failed_rows
- [ ] Show real-time batch updates
- [ ] Display errors in expandable list
- [ ] Handle job completion with success banner
- [ ] Handle job failure with error alert

#### Phase 7: Push Notifications (Week 5)
- [ ] Register for remote notifications
- [ ] Request notification permissions
- [ ] Send device token to backend
- [ ] Handle notification when import completes
- [ ] Deep link to import result summary
- [ ] Show local notification if app backgrounded

#### Phase 8: Capabilities Detection (Week 5)
- [ ] Implement `GET /api/v2/capabilities` on app launch
- [ ] Cache capabilities response
- [ ] Check `sse_support` flag before using SSE
- [ ] Check `websocket.deprecated` flag
- [ ] Show deprecation banner if WebSocket sunset < 30 days
- [ ] Store API version for compatibility checks

#### Phase 9: Feature Flag & Migration (Week 6)
- [ ] Add feature flag: `useAPIv2` (default: true)
- [ ] Implement dual-support mode (try v2, fallback to WebSocket)
- [ ] Add settings toggle to switch between v1/v2
- [ ] Log v1 vs v2 usage to analytics
- [ ] Remove WebSocket code after 60-day sunset period

#### Phase 10: Testing & Polish (Week 6)
- [ ] Unit tests for EnrichmentService
- [ ] Unit tests for ImportJobService
- [ ] Unit tests for SSE/polling fallback logic
- [ ] Integration tests with mock server
- [ ] Test network transition (WiFi → cellular)
- [ ] Test app backgrounding during import
- [ ] Test push notification deep linking
- [ ] Real device testing (iOS 18+)

---

## Migration Strategy

### Timeline

```
Week 1-2: Backend Development
Week 3-4: Frontend Development
Week 5-6: Dual-Support Testing
Week 7-10: Monitoring & Migration
Week 11+: WebSocket Deprecation
```

### Detailed Migration Plan

#### Phase 1: Backend Deployment (Week 1-2)

**Goals:**
- Deploy v2 API endpoints to production
- Maintain 100% backward compatibility with WebSocket

**Steps:**
1. Deploy barcode enrichment endpoint (no breaking changes)
2. Deploy CSV import endpoints (new functionality)
3. Deploy capabilities endpoint
4. Add deprecation headers to WebSocket responses:
   ```
   X-Deprecated-Endpoint: true
   X-Sunset-Date: 2025-03-22
   X-Migration-Guide: https://docs.bookstrack.app/api/v2-migration
   ```

**Rollback Plan:**
- WebSocket remains fully functional
- No client changes required
- Can disable v2 endpoints via feature flag

---

#### Phase 2: Frontend Development (Week 3-4)

**Goals:**
- Implement v2 API client in iOS app
- Test in development/staging environments

**Steps:**
1. Implement v2 API client (parallel to v1)
2. Add feature flag: `useAPIv2` (default: false)
3. Test with staging backend
4. Submit TestFlight build for beta testing

**Testing:**
- Unit tests for new services
- Integration tests with staging backend
- Manual testing on real devices
- Beta tester feedback

---

#### Phase 3: Gradual Rollout (Week 5-6)

**Goals:**
- Enable v2 API for small percentage of users
- Monitor error rates and performance

**Steps:**
1. **Week 5:** Enable v2 for 10% of users (via remote config)
   - Monitor: Success rate, error rate, latency
   - Compare: v1 vs v2 performance metrics

2. **Week 6:** Increase to 50% of users
   - Monitor: SSE connection stability
   - Monitor: Polling fallback rate
   - Monitor: CSV import completion rate

**Metrics to Track:**
- Barcode enrichment success rate (v1 vs v2)
- CSV import completion rate (v1 vs v2)
- SSE connection success rate
- Polling fallback rate
- Average import duration
- Error rate by error type
- User satisfaction (in-app feedback)

**Rollback Triggers:**
- Error rate > 5% higher than v1
- Success rate < 90%
- Critical bug affecting data integrity

---

#### Phase 4: Full Migration (Week 7-10)

**Goals:**
- Enable v2 for 100% of users
- Monitor WebSocket usage decline

**Steps:**
1. **Week 7:** Enable v2 for 100% of users
2. **Week 8-9:** Monitor WebSocket usage (should be near 0%)
3. **Week 10:** Prepare WebSocket deprecation notice

**WebSocket Usage Tracking:**
```javascript
// Backend logs WebSocket connections
console.log('WebSocket connection from client', {
  clientVersion: req.headers['X-App-Version'],
  platform: req.headers['X-Platform'],
  timestamp: new Date().toISOString()
});

// Weekly report: WebSocket connections by client version
// Expected: Decline to 0 as users update to latest app
```

---

#### Phase 5: WebSocket Deprecation (Week 11+)

**Goals:**
- Gracefully deprecate WebSocket
- Ensure 100% migration to v2

**60-Day Sunset Timeline:**

**Day 0 (Deploy Date):**
- v2 API deployed
- Deprecation headers added to WebSocket
- Migration guide published

**Day 30:**
- App update required (minimum version with v2 support)
- In-app banner: "WebSocket support ends in 30 days"
- Email to active users with old app versions

**Day 45:**
- In-app banner: "WebSocket support ends in 15 days"
- Push notification to users still on old versions

**Day 60 (Sunset Date: 2025-03-22):**
- WebSocket endpoints return 410 Gone
- All users must be on v2 API

**Day 60+ Response:**
```json
{
  "error": "endpoint_sunset",
  "message": "WebSocket API was deprecated on 2025-01-22 and sunset on 2025-03-22. Please update to the latest app version.",
  "migration_guide": "https://docs.bookstrack.app/api/v2-migration",
  "min_app_version": "3.8.0"
}
```

---

### Dual-Support Window

During weeks 1-10, both APIs operate simultaneously:

```
Client Request Flow (with fallback):

1. Check capabilities endpoint
   GET /api/v2/capabilities

2. If v2 supported:
   Try v2 endpoints

3. If v2 fails:
   Fall back to WebSocket (v1)

4. Log fallback event for monitoring
```

**Fallback Triggers:**
- v2 endpoint returns 5xx error
- SSE connection fails 3 times
- Network timeout (>30s)

**Monitoring:**
```javascript
// Track fallback events
analytics.track('api_fallback', {
  from: 'v2_sse',
  to: 'v1_websocket',
  reason: 'sse_connection_failed',
  attempt: 3
});
```

---

## Testing Plan

### Backend Testing

#### Unit Tests
```javascript
// tests/enrichment.test.js
describe('Barcode Enrichment', () => {
  test('should merge Google Books and OpenLibrary results', async () => {
    const result = await enrichBook('9780747532743');
    expect(result.provider).toBe('orchestrated:google+openlibrary');
    expect(result.title).toBeDefined();
    expect(result.authors).toBeArray();
  });

  test('should return 404 when book not found', async () => {
    const response = await fetch('/api/v2/books/enrich', {
      method: 'POST',
      body: JSON.stringify({ barcode: 'invalid' })
    });
    expect(response.status).toBe(404);
  });
});

// tests/import.test.js
describe('CSV Import', () => {
  test('should accept valid CSV upload', async () => {
    const formData = new FormData();
    formData.append('file', csvBlob);
    formData.append('options', JSON.stringify({ auto_enrich: true }));

    const response = await fetch('/api/v2/imports', {
      method: 'POST',
      body: formData
    });

    expect(response.status).toBe(202);
    const data = await response.json();
    expect(data.job_id).toMatch(/^import_/);
  });

  test('should process 150-row CSV in under 2 minutes', async () => {
    const jobId = await uploadCSV('fixtures/150-books.csv');

    await waitForJobComplete(jobId, { timeout: 120000 });

    const status = await getJobStatus(jobId);
    expect(status.status).toBe('complete');
    expect(status.successful_rows).toBeGreaterThan(140);
  }, 120000);
});
```

#### Integration Tests
- Test Durable Object state persistence
- Test Queue consumer processing
- Test SSE event broadcasting
- Test R2 CSV storage/retrieval

#### Load Tests
```bash
# Simulate 100 concurrent barcode enrichments
artillery run tests/load/enrichment.yml

# Simulate 10 concurrent CSV imports (1000 rows each)
artillery run tests/load/import.yml

# Expected results:
# - Enrichment: p95 latency < 5s
# - CSV Import: p95 completion < 3 minutes (1000 rows)
# - Error rate < 1%
```

---

### Frontend Testing

#### Unit Tests
```swift
// Tests/EnrichmentServiceTests.swift
@Test func testBarcodeEnrichment() async throws {
    let service = EnrichmentService(apiClient: mockClient)

    let result = try await service.enrichBook(barcode: "9780747532743")

    #expect(result.title == "Harry Potter and the Philosopher's Stone")
    #expect(result.provider.contains("orchestrated"))
}

@Test func testRateLimitHandling() async throws {
    mockClient.nextResponse = .rateLimited(retryAfter: 60)

    let service = EnrichmentService(apiClient: mockClient)

    await #expect(throws: EnrichmentError.rateLimited) {
        try await service.enrichBook(barcode: "9780747532743")
    }
}

// Tests/ImportJobServiceTests.swift
@Test func testCSVUpload() async throws {
    let service = ImportJobService(apiClient: mockClient)

    let job = try await service.uploadCSV(file: csvData, options: .default)

    #expect(job.jobId.starts(with: "import_"))
    #expect(job.status == .queued)
}

@Test func testSSEProgressUpdates() async throws {
    let service = ImportJobService(apiClient: mockClient)
    mockClient.sseEvents = [
        .progress(0.1, processedRows: 15),
        .progress(0.5, processedRows: 75),
        .complete(summary: .mock)
    ]

    var progressUpdates: [Double] = []

    for await progress in service.streamProgress(jobId: "test_123") {
        progressUpdates.append(progress.progress)
    }

    #expect(progressUpdates == [0.1, 0.5, 1.0])
}

@Test func testPollingFallback() async throws {
    let service = ImportJobService(apiClient: mockClient)
    mockClient.sseFailureCount = 3 // Trigger fallback

    let status = try await service.getJobStatus(jobId: "test_123")

    #expect(mockClient.pollingCalls > 0)
    #expect(status.status == .complete)
}
```

#### Integration Tests
- Test with staging backend
- Test network transitions (WiFi → cellular)
- Test app backgrounding during import
- Test push notification handling

#### Real Device Testing
- Test on iPhone 15 Pro (iOS 18)
- Test on iPad Air (iOS 18)
- Test on poor network conditions (2G simulation)
- Test with large CSV files (1000+ rows)

---

### Manual Testing Checklist

#### Barcode Enrichment
- [ ] Scan valid ISBN-13 barcode
- [ ] Scan valid ISBN-10 barcode
- [ ] Scan invalid barcode (should show error)
- [ ] Test with no internet (should show offline error)
- [ ] Test with slow network (should show loading for 5-30s)
- [ ] Test rate limit (scan 100+ books rapidly)

#### CSV Import
- [ ] Upload valid 10-row CSV
- [ ] Upload valid 150-row CSV
- [ ] Upload valid 1000-row CSV
- [ ] Upload CSV with invalid ISBNs (some rows should fail)
- [ ] Upload CSV with missing columns (should reject)
- [ ] Upload oversized CSV (>50MB, should reject)
- [ ] Monitor SSE progress in real-time
- [ ] Test SSE reconnection (toggle airplane mode during import)
- [ ] Test polling fallback (disable SSE on backend)
- [ ] Test push notification on completion (background app)

#### Migration & Compatibility
- [ ] Install old app version (with WebSocket)
- [ ] See deprecation banner
- [ ] Update to new app version (with v2 API)
- [ ] Verify WebSocket no longer used
- [ ] Test capabilities detection
- [ ] Test feature flag toggle (v1 ↔ v2)

---

## Success Criteria

### Performance Metrics

**Barcode Enrichment:**
- [ ] p95 latency < 5 seconds
- [ ] Success rate > 95%
- [ ] Error rate < 5%

**CSV Import:**
- [ ] 150-row CSV completes in < 2 minutes
- [ ] 1000-row CSV completes in < 10 minutes
- [ ] Success rate > 90% (per row)
- [ ] SSE connection success rate > 80%
- [ ] Polling fallback works 100% of time

**Reliability:**
- [ ] API uptime > 99.9%
- [ ] No data loss during network transitions
- [ ] Graceful degradation (SSE → polling)

### User Experience

- [ ] Progress bar updates in real-time (SSE)
- [ ] No user-visible errors during network transitions
- [ ] Push notifications work for backgrounded imports
- [ ] Deprecation messaging is clear and actionable

### Migration Metrics

- [ ] 100% of users migrated to v2 API by Day 60
- [ ] WebSocket usage declines to 0% by Day 45
- [ ] No increase in support tickets during migration
- [ ] No data loss or corruption during migration

---

## Appendix

### Error Code Reference

| Code | Error | Description | User Action |
|------|-------|-------------|-------------|
| 400 | `invalid_csv` | CSV missing required columns | Fix CSV format |
| 400 | `invalid_barcode` | Barcode format invalid | Check barcode |
| 401 | `unauthorized` | Missing/invalid auth token | Re-login |
| 404 | `book_not_found` | Book not in any provider | Try different ISBN |
| 404 | `job_not_found` | Import job expired | Re-upload CSV |
| 413 | `file_too_large` | CSV exceeds 50MB | Split into smaller files |
| 429 | `rate_limit_exceeded` | Too many requests | Wait and retry |
| 503 | `providers_unavailable` | All providers down | Try again later |

### Rate Limits

| Endpoint | Limit | Burst | Window |
|----------|-------|-------|--------|
| `/books/enrich` | 1000 req/hour | 100 req/min | Per user |
| `/imports` | 10 uploads/hour | 3 uploads/min | Per user |
| `/imports/{id}` | 600 req/hour | 60 req/min | Per job |
| `/imports/{id}/stream` | 10 connections | 3 connections | Per job |

### SSE Event Types

| Event | Data | Triggered When |
|-------|------|----------------|
| `queued` | `{ "status": "queued", "job_id": "..." }` | Job accepted |
| `started` | `{ "status": "processing", "total_rows": 150 }` | Processing begins |
| `progress` | `{ "progress": 0.5, "processed_rows": 75 }` | After each batch |
| `complete` | `{ "status": "complete", "result_summary": {...} }` | Job completes |
| `error` | `{ "status": "failed", "error": "..." }` | Job fails |

### Cloudflare Limits

| Resource | Limit | Notes |
|----------|-------|-------|
| Worker CPU time | 50ms (free), 30s (paid) | Per request |
| Durable Object storage | 1 GB per object | Job state < 100KB typically |
| R2 storage | Unlimited | Pay per GB |
| Queue throughput | 400 msg/sec | Scales automatically |
| SSE connection duration | Unlimited | Auto-closes on completion |

---

## Questions & Answers

**Q: Why SSE instead of WebSocket for CSV import progress?**
A: SSE is simpler (one-way server→client), has automatic reconnection built into the spec, and works through proxies/firewalls where WebSockets often fail. It's perfect for progress updates where the client doesn't need to send data back.

**Q: Why not polling for everything?**
A: Polling every 10s is fine for long-running tasks (CSV import), but adds unnecessary latency for quick tasks (barcode enrichment). SSE provides real-time updates when possible, with polling as a reliable fallback.

**Q: What happens if the app is killed during an import?**
A: The job continues processing on the backend (serverless queue consumer). When the app reopens, it can reconnect to the SSE stream or poll the status endpoint using the job_id. Push notifications ensure the user is notified of completion even if the app is closed.

**Q: How do we handle network transitions (WiFi → cellular)?**
A: SSE automatically reconnects with the `Last-Event-ID` header, resuming from the last received event. The polling fallback ensures progress updates continue even if SSE fails. The stateless HTTP design means no connection state is lost.

**Q: What's the rollback plan if v2 API has critical bugs?**
A: The WebSocket v1 API remains fully functional for 60 days. We can disable the v2 feature flag remotely to revert all clients to v1 within minutes. No app update required for rollback.

---

**End of Proposal**

This contract is ready for review by both frontend (iOS) and backend (Cloudflare) teams. Please provide feedback and approval to proceed with implementation.
