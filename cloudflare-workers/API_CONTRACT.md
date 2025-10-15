# 📚 BooksTracker Cloudflare Workers API Contract

**Version:** 1.0.0
**Last Updated:** October 15, 2025
**Status:** Production
**Maintainer:** BooksTracker Development Team

---

## Overview

This document defines the API contract for all BooksTracker Cloudflare Workers. All endpoints, request/response formats, error codes, and breaking changes MUST be documented here.

**Breaking Change Policy:**
- Version bumps required for breaking changes
- Deprecation notices must be added 30 days before removal
- Backward compatibility maintained for 1 major version

**Workers Architecture:**
```
iOS App
    ↓
books-api-proxy (Orchestrator)
    ↓
    ├─→ external-apis-worker (Google Books, OpenLibrary, ISBNdb)
    ├─→ bookshelf-ai-worker (Gemini AI scanning)
    └─→ personal-library-cache-warmer (Proactive caching)
```

---

## 1. Books API Proxy

**Base URL:** `https://books-api-proxy.jukasdrj.workers.dev`
**Purpose:** Main orchestrator for book search and metadata retrieval
**Service Bindings:** `EXTERNAL_APIS_WORKER`
**Caching:** KV (hot) + R2 (cold storage)

### 1.1 Search Endpoints

#### `GET /search/auto`

**Purpose:** Parallel multi-provider book search

**Query Parameters:**
| Parameter | Type | Required | Description | Example |
|-----------|------|----------|-------------|---------|
| `q` | string | Yes | Search query (title, author, ISBN) | `"The Martian"` |
| `maxResults` | integer | No | Max results (default: 40) | `20` |
| `provider` | string | No | Specific provider (`google`, `openlibrary`, `isbndb`) | `"google"` |

**Request Example:**
```bash
GET /search/auto?q=Neil%20Gaiman&maxResults=20
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "results": [
    {
      "title": "American Gods",
      "authors": ["Neil Gaiman"],
      "isbn": "9780062572233",
      "publisher": "William Morrow",
      "publicationYear": 2001,
      "coverUrl": "https://covers.openlibrary.org/b/isbn/9780062572233-L.jpg",
      "description": "A novel about gods in America",
      "pageCount": 465,
      "language": "en"
    }
  ],
  "metadata": {
    "totalResults": 18,
    "provider": "orchestrated:google+openlibrary",
    "cached": false,
    "processingTime": 1847
  }
}
```

**Error Responses:**
```json
// 400 Bad Request - Missing query
{
  "success": false,
  "error": "Missing required parameter: q"
}

// 500 Internal Server Error
{
  "success": false,
  "error": "All providers failed",
  "details": {
    "google": "timeout",
    "openlibrary": "rate_limit",
    "isbndb": "api_error"
  }
}
```

**Cache Strategy:**
- KV: 1 hour TTL
- R2: 7 days TTL
- Cache key: `search:${hash(q)}:${provider}`

---

#### `GET /search/isbn/{isbn}`

**Purpose:** Direct ISBN lookup with fallback providers

**Path Parameters:**
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `isbn` | string | ISBN-10 or ISBN-13 | `9780062572233` |

**Request Example:**
```bash
GET /search/isbn/9780062572233
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "book": {
    "title": "American Gods",
    "authors": ["Neil Gaiman"],
    "isbn": "9780062572233",
    "isbn10": "0062572237",
    "publisher": "William Morrow",
    "publicationYear": 2001,
    "coverUrl": "https://covers.openlibrary.org/b/isbn/9780062572233-L.jpg",
    "pageCount": 465,
    "language": "en",
    "format": "Paperback"
  },
  "metadata": {
    "provider": "google",
    "cached": true,
    "cacheAge": 3600
  }
}
```

**Error Responses:**
```json
// 404 Not Found
{
  "success": false,
  "error": "ISBN not found",
  "isbn": "9780062572233",
  "providersChecked": ["google", "openlibrary", "isbndb"]
}

// 400 Bad Request - Invalid ISBN
{
  "success": false,
  "error": "Invalid ISBN format",
  "isbn": "invalid123"
}
```

**Cache Strategy:**
- KV: 24 hours TTL
- R2: 30 days TTL (long-term ISBN data)
- Cache key: `isbn:${isbn13}`, `isbn:${isbn10}`

---

#### `GET /author/{name}`

**Purpose:** Author bibliography with works list

**Path Parameters:**
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `name` | string | URL-encoded author name | `Neil%20Gaiman` |

**Request Example:**
```bash
GET /author/Neil%20Gaiman
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "author": {
    "name": "Neil Gaiman",
    "bio": "British author known for fantasy and graphic novels",
    "birthYear": 1960,
    "photoUrl": "https://example.com/neil-gaiman.jpg"
  },
  "works": [
    {
      "title": "American Gods",
      "publicationYear": 2001,
      "isbn": "9780062572233",
      "coverUrl": "https://covers.openlibrary.org/..."
    }
  ],
  "metadata": {
    "totalWorks": 47,
    "provider": "openlibrary",
    "cached": true
  }
}
```

**Cache Strategy:**
- KV: 24 hours TTL
- Service binding to external-apis-worker
- Cache key: `author:${name.toLowerCase()}`

---

### 1.2 Cache Management Endpoints

#### `GET /cache/warm-popular`

**Purpose:** Pre-warm cache for 29 popular authors

**Authorization:** None (rate-limited by IP)

**Request Example:**
```bash
GET /cache/warm-popular
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "message": "Cache warming initiated",
  "authors": [
    "Stephen King",
    "J.K. Rowling",
    "George R.R. Martin"
  ],
  "totalAuthors": 29,
  "estimatedTime": "3-5 minutes"
}
```

---

### 1.3 Health & Status Endpoints

#### `GET /health`

**Purpose:** System health check with analytics status

**Request Example:**
```bash
GET /health
```

**Response Format (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2025-10-15T13:30:00Z",
  "version": "1.0.0",
  "services": {
    "kv_cache": "operational",
    "r2_storage": "operational",
    "external_apis": "operational"
  },
  "analytics": {
    "cacheHitRate": 85.3,
    "avgResponseTime": 287,
    "requestsLast24h": 12847
  }
}
```

**Error Responses:**
```json
// 503 Service Unavailable
{
  "status": "degraded",
  "timestamp": "2025-10-15T13:30:00Z",
  "services": {
    "kv_cache": "operational",
    "r2_storage": "failed",
    "external_apis": "operational"
  }
}
```

---

## 2. Bookshelf AI Worker

**Base URL:** `https://bookshelf-ai-worker.jukasdrj.workers.dev`
**Purpose:** AI-powered bookshelf scanning with Gemini 2.5 Flash
**Service Bindings:** `BOOKS_API_PROXY` (for enrichment)
**Caching:** None (real-time AI processing)

### 2.1 Scanning Endpoints

#### `POST /scan`

**Purpose:** Scan bookshelf image and detect books with AI + enrichment

**Request Headers:**
```
Content-Type: image/jpeg
```

**Request Body:**
- Binary JPEG image data
- Max size: 10MB
- Recommended: 1920x1080 resolution

**Request Example:**
```bash
curl -X POST https://bookshelf-ai-worker.jukasdrj.workers.dev/scan \
  -H "Content-Type: image/jpeg" \
  --data-binary @bookshelf.jpg \
  --max-time 120
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "books": [
    {
      "title": "The Martian",
      "author": "Andy Weir",
      "boundingBox": {
        "x1": 0.15,
        "y1": 0.32,
        "x2": 0.25,
        "y2": 0.68
      },
      "confidence": 0.95,
      "enrichmentStatus": "ENRICHED",
      "isbn": "9780553418026",
      "coverUrl": "https://covers.openlibrary.org/b/isbn/9780553418026-L.jpg",
      "publisher": "Broadway Books",
      "publicationYear": 2014
    }
  ],
  "metadata": {
    "imageQuality": "excellent",
    "lighting": "good",
    "sharpness": "high",
    "readableCount": 14,
    "totalDetected": 15,
    "enrichedCount": 13,
    "processingTime": 35647,
    "aiProcessingTime": 30123,
    "enrichmentTime": 5524
  }
}
```

**Field Descriptions:**

**`books[]` Array:**
| Field | Type | Required | Description | Example |
|-------|------|----------|-------------|---------|
| `title` | string | No | Book title from spine | `"The Martian"` |
| `author` | string | No | Author name from spine | `"Andy Weir"` |
| `boundingBox` | object | Yes | Normalized coordinates (0-1) | `{x1, y1, x2, y2}` |
| `confidence` | float | Yes | Detection confidence (0.0-1.0) | `0.95` |
| `enrichmentStatus` | string | No | Enrichment result | `"ENRICHED"` |
| `isbn` | string | No | ISBN from enrichment | `"9780553418026"` |
| `coverUrl` | string | No | Cover image URL | `"https://..."` |
| `publisher` | string | No | Publisher from enrichment | `"Broadway Books"` |
| `publicationYear` | integer | No | Year from enrichment | `2014` |

**`enrichmentStatus` Values:**
- `"ENRICHED"` - Successfully enriched with metadata
- `"NOT_FOUND"` - Book not found in databases
- `"SKIPPED"` - Confidence too low (<0.7)
- `"FAILED"` - Enrichment API error

**Error Responses:**
```json
// 400 Bad Request - Invalid image
{
  "success": false,
  "error": "Invalid image format",
  "acceptedFormats": ["image/jpeg"]
}

// 413 Payload Too Large
{
  "success": false,
  "error": "Image size exceeds 10MB limit",
  "maxSize": 10485760
}

// 422 Unprocessable Entity - Poor image quality
{
  "success": false,
  "error": "Image quality insufficient",
  "metadata": {
    "imageQuality": "poor",
    "lighting": "too_dark",
    "sharpness": "blurry",
    "suggestion": "Retake photo with better lighting"
  }
}

// 504 Gateway Timeout - AI processing timeout
{
  "success": false,
  "error": "AI processing timeout",
  "processingTime": 70000,
  "maxTimeout": 70000
}
```

**Processing Times:**
- AI Detection (Gemini): 25-40 seconds
- Enrichment (books-api-proxy): 5-10 seconds
- Total timeout: 70 seconds

---

#### `GET /health`

**Purpose:** Worker health check

**Response Format (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2025-10-15T13:30:00Z",
  "version": "1.0.0",
  "services": {
    "gemini_api": "operational",
    "books_api_proxy": "operational"
  },
  "config": {
    "aiModel": "gemini-2.5-flash-preview-05-20",
    "maxImageSize": 10485760,
    "requestTimeout": 70000,
    "confidenceThreshold": 0.7
  }
}
```

---

## 3. External APIs Worker

**Base URL:** `https://external-apis-worker.jukasdrj.workers.dev`
**Purpose:** Unified interface for Google Books, OpenLibrary, ISBNdb APIs
**Service Bindings:** None (external API calls only)
**Caching:** Delegated to books-api-proxy

### 3.1 RPC Methods (Service Binding Only)

This worker is accessed via RPC service binding from books-api-proxy. Not exposed as HTTP endpoints.

**Available RPC Methods:**
```typescript
// Search Google Books
searchGoogleBooks(query: string, maxResults: number): Promise<Book[]>

// Search OpenLibrary
searchOpenLibrary(query: string, maxResults: number): Promise<Book[]>

// Search ISBNdb
searchISBNdb(query: string, maxResults: number): Promise<Book[]>

// Get book by ISBN
getBookByISBN(isbn: string, provider: string): Promise<Book>

// Get author bibliography
getAuthorBibliography(name: string, provider: string): Promise<Author>
```

**RPC Call Example (from books-api-proxy):**
```javascript
const results = await env.EXTERNAL_APIS_WORKER.searchGoogleBooks(
  "Neil Gaiman",
  20
);
```

---

## 4. Personal Library Cache Warmer

**Base URL:** `https://personal-library-cache-warmer.jukasdrj.workers.dev`
**Purpose:** Proactive cache warming for user libraries and popular authors
**Service Bindings:** `BOOKS_API_PROXY`, `ISBNDB_WORKER`, `OPENLIBRARY_WORKER`
**Caching:** KV (progress tracking) + R2 (library storage)

### 4.1 Cache Warming Endpoints

#### `POST /warm`

**Purpose:** Execute cache warming session

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "maxAuthors": 50,
  "maxBooksPerAuthor": 100,
  "force": false
}
```

**Request Example:**
```bash
curl -X POST https://personal-library-cache-warmer.jukasdrj.workers.dev/warm \
  -H "Content-Type: application/json" \
  -d '{"maxAuthors": 50, "maxBooksPerAuthor": 100}'
```

**Response Format (200 OK):**
```json
{
  "success": true,
  "sessionId": "warming_1697385600000",
  "message": "Cache warming initiated",
  "config": {
    "maxAuthors": 50,
    "maxBooksPerAuthor": 100,
    "force": false
  },
  "estimatedTime": "5-8 minutes"
}
```

---

#### `GET /status`

**Purpose:** Check cache warming progress

**Response Format (200 OK):**
```json
{
  "success": true,
  "status": "in_progress",
  "progress": {
    "authorsProcessed": 23,
    "totalAuthors": 50,
    "booksWarmed": 487,
    "percentComplete": 46
  },
  "currentSession": {
    "sessionId": "warming_1697385600000",
    "startTime": "2025-10-15T13:25:00Z",
    "elapsedTime": 187
  }
}
```

---

#### `POST /upload-csv`

**Purpose:** Upload personal library CSV for cache warming

**Request Headers:**
```
Content-Type: multipart/form-data
```

**Request Body:**
- CSV file (max 10MB)
- Supported formats: Goodreads, LibraryThing, StoryGraph

**Response Format (200 OK):**
```json
{
  "success": true,
  "message": "CSV uploaded successfully",
  "fileName": "goodreads_library_2025.csv",
  "r2Key": "libraries/user_123/goodreads_library_2025.csv",
  "metadata": {
    "rowCount": 487,
    "uniqueAuthors": 142,
    "fileSize": 2847621
  }
}
```

---

## 5. Service Binding Architecture

### 5.1 Inter-Worker Communication Patterns

**Current Architecture (October 2025):**
```
iOS App
    ↓ HTTPS
bookshelf-ai-worker
    ↓ Service Binding (HTTP fetch)
books-api-proxy
    ↓ Service Binding (RPC)
external-apis-worker
    ↓ HTTPS
External APIs (Google Books, OpenLibrary, ISBNdb)
```

### 5.2 Service Binding Types

**HTTP Fetch Pattern (bookshelf-ai-worker → books-api-proxy):**
```javascript
// bookshelf-ai-worker/src/index.js
const searchURL = new URL(
  `https://books-api-proxy.jukasdrj.workers.dev/search/auto?q=${encodeURIComponent(query)}`
);
const response = await env.BOOKS_API_PROXY.fetch(searchURL);
const data = await response.json();
```

**Configuration:**
```toml
# bookshelf-ai-worker/wrangler.toml
[[services]]
binding = "BOOKS_API_PROXY"
service = "books-api-proxy"
# No entrypoint = HTTP fetch only (not RPC)
```

**RPC Method Call Pattern (books-api-proxy → external-apis-worker):**
```javascript
// books-api-proxy/src/index.js
const results = await env.EXTERNAL_APIS_WORKER.searchGoogleBooks(
  "Neil Gaiman",
  20
);
```

**Configuration:**
```toml
# books-api-proxy/wrangler.toml
[[services]]
binding = "EXTERNAL_APIS_WORKER"
service = "external-apis-worker"
entrypoint = "ExternalAPIsWorker"  # ← Enables RPC method calls
```

### 5.3 When to Use Each Pattern

**Use HTTP Fetch When:**
- Worker doesn't expose RPC entrypoint
- Need to call specific HTTP endpoints
- Want standard HTTP response handling
- Example: bookshelf-ai-worker → books-api-proxy

**Use RPC Methods When:**
- Worker extends `WorkerEntrypoint` class
- Need type-safe method calls
- Want direct JavaScript function invocation
- Example: books-api-proxy → external-apis-worker

### 5.4 Legacy Pattern (Deprecated)

**❌ REMOVED: Direct ISBNdb/OpenLibrary Worker Bindings**

Previously, cache-warmer had direct bindings to non-existent workers:
```toml
# ❌ REMOVED (October 2025)
[[services]]
binding = "ISBNDB_WORKER"
service = "isbndb-biography-worker-production"
entrypoint = "ISBNdbWorker"

[[services]]
binding = "OPENLIBRARY_WORKER"
service = "openlibrary-search-worker"
entrypoint = "OpenLibraryWorker"
```

**✅ CURRENT: All workers use books-api-proxy**
```toml
# ✅ CORRECT (October 2025)
[[services]]
binding = "BOOKS_API_PROXY"
service = "books-api-proxy"
```

---

## 6. Common Response Patterns

### 6.1 Success Response Structure

All successful responses follow this pattern:

```json
{
  "success": true,
  "data": { /* endpoint-specific data */ },
  "metadata": {
    "timestamp": "2025-10-15T13:30:00Z",
    "cached": false,
    "provider": "google",
    "processingTime": 287
  }
}
```

### 6.2 Error Response Structure

All error responses follow this pattern:

```json
{
  "success": false,
  "error": "Human-readable error message",
  "errorCode": "VALIDATION_ERROR",
  "details": {
    "field": "isbn",
    "reason": "Invalid format"
  },
  "timestamp": "2025-10-15T13:30:00Z"
}
```

### 6.3 Standard Error Codes

| HTTP Status | Error Code | Description |
|-------------|------------|-------------|
| 400 | `VALIDATION_ERROR` | Invalid request parameters |
| 401 | `UNAUTHORIZED` | Missing or invalid API key |
| 404 | `NOT_FOUND` | Resource not found |
| 413 | `PAYLOAD_TOO_LARGE` | Request body exceeds limit |
| 422 | `UNPROCESSABLE_ENTITY` | Valid request, but can't process |
| 429 | `RATE_LIMIT_EXCEEDED` | Too many requests |
| 500 | `INTERNAL_ERROR` | Server error |
| 503 | `SERVICE_UNAVAILABLE` | Temporary outage |
| 504 | `GATEWAY_TIMEOUT` | Request timeout |

---

## 7. Rate Limiting

### 7.1 Rate Limit Headers

All responses include rate limit headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 87
X-RateLimit-Reset: 1697385600
```

### 7.2 Rate Limit Policies

| Worker | Limit | Window | Scope |
|--------|-------|--------|-------|
| books-api-proxy | 100 req | 1 minute | Per IP |
| bookshelf-ai-worker | 10 req | 1 hour | Per IP |
| cache-warmer | 5 req | 1 hour | Per IP |

---

## 8. Versioning & Deprecation

### 8.1 Version Format

API versions follow semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes, backward compatible

### 8.2 Current Versions

| Worker | Version | Status |
|--------|---------|--------|
| books-api-proxy | 1.0.0 | Stable |
| bookshelf-ai-worker | 1.0.0 | Stable |
| external-apis-worker | 1.0.0 | Stable |
| cache-warmer | 1.0.0 | Stable |

### 8.3 Deprecation Policy

**Deprecation Timeline:**
1. **T+0 days**: Add deprecation notice to response headers
2. **T+30 days**: Add console warnings for deprecated endpoints
3. **T+60 days**: Return 410 Gone for deprecated endpoints
4. **T+90 days**: Remove endpoint entirely

**Deprecation Header:**
```
Deprecation: true
Sunset: Wed, 15 Jan 2026 23:59:59 GMT
Link: <https://docs.bookstrack.com/api/migration>; rel="deprecation"
```

---

## 9. Change Log

### Version 1.0.0 (October 15, 2025)

**Added:**
- Initial API contract documentation
- Bookshelf AI Worker endpoints
- Enrichment integration (Tasks 4-6)
- Rate limiting headers
- Standard error codes

**Changed:**
- `bookshelf-ai-worker` timeout: 60s → 70s (for enrichment)
- Response model: Added `confidence`, `enrichmentStatus`, `coverUrl`

**Deprecated:**
- None

**Removed:**
- None

---

## 10. Developer Guidelines

### 10.1 Making API Changes

**Before changing any endpoint:**

1. ✅ Update this API contract document
2. ✅ Update worker version in `wrangler.toml`
3. ✅ Test with iOS app integration
4. ✅ Add migration guide if breaking change
5. ✅ Update CLAUDE.md with changes
6. ✅ Commit with semantic commit message

### 10.2 Testing Changes

```bash
# Test books-api-proxy
curl "https://books-api-proxy.jukasdrj.workers.dev/health"

# Test bookshelf-ai-worker
curl -X POST https://bookshelf-ai-worker.jukasdrj.workers.dev/scan \
  -H "Content-Type: image/jpeg" \
  --data-binary @test.jpg

# Monitor logs
wrangler tail books-api-proxy --format pretty
```

### 10.3 Contract Validation

Before deploying changes:

- [ ] All request/response examples tested
- [ ] Error codes documented
- [ ] Rate limits verified
- [ ] iOS app updated (if breaking change)
- [ ] Deprecation notices added (if applicable)

---

## 11. Support & Contact

**Documentation:** See `/cloudflare-workers/README.md`
**GitHub Issues:** https://github.com/jukasdrj/books-tracker-v1/issues
**Issue #33:** API Contract tracking issue

**Maintainers:**
- Primary: BooksTracker Development Team
- Last Updated By: Claude Code (October 15, 2025)

---

**Contract Version:** 1.0.0
**Status:** ✅ Complete and Production Ready
