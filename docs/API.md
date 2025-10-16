# BooksTrack API Documentation

**Updated:** October 16, 2025
**Version:** 3.0.0 (Build 46+)

## Overview

BooksTrack uses a distributed Cloudflare Workers architecture for backend services.

## Architecture

```
iOS App → books-api-proxy → RPC Service Bindings:
                              ├── isbndb-worker
                              ├── google-books-worker
                              ├── openlibrary-worker
                              └── isbndb-biography-worker

iOS App → bookshelf-ai-worker → books-api-proxy (enrichment)
```

## books-api-proxy Endpoints

### POST /search/title
General search orchestrator (ISBNdb, OpenLibrary, Google Books)

**Request:**
```typescript
{
  query: string;        // Search query
  limit?: number;       // Results limit (default: 10)
  offset?: number;      // Pagination offset (default: 0)
}
```

**Response:**
```typescript
{
  results: SearchResult[];
  provider: string;     // "orchestrated:google+openlibrary" or single provider
  cached: boolean;
  totalResults: number;
}
```

**Caching:** 6 hours

### POST /search/isbn
Dedicated ISBN lookup (ISBNdb-first, 7-day cache)

**Request:**
```typescript
{
  isbn: string;  // ISBN-10 or ISBN-13
}
```

**Response:**
```typescript
{
  title: string;
  authors: string[];
  isbn: string;
  publisher?: string;
  publishedDate?: string;
  coverUrl?: string;
  provider: "isbndb" | "openlibrary" | "google";
}
```

**Caching:** 7 days

### POST /search/advanced
Multi-field filtering (title + author)

**Request:**
```typescript
{
  title?: string;
  author?: string;
  limit?: number;
}
```

**Response:** Same as /search/title

**Caching:** 6 hours

### POST /search/author
Author bibliography

**Request:**
```typescript
{
  author: string;
  limit?: number;
}
```

**Response:**
```typescript
{
  works: Work[];
  author: string;
  provider: string;
}
```

**Caching:** 6 hours

## bookshelf-ai-worker Endpoints

### POST /scan
Bookshelf photo AI analysis with enrichment

**Request:**
```typescript
{
  image: string;  // Base64-encoded JPEG
}
```

**Response:**
```typescript
{
  detections: {
    title: string;
    authors: string[];
    confidence: number;          // Direct field (0-1)
    enrichmentStatus: string;    // "ENRICHED", "FOUND", "UNCERTAIN", "REJECTED"
    coverUrl?: string;           // Enriched cover URL
    isbn?: string;
    publisher?: string;
    publishedDate?: string;
  }[];
  suggestions?: {
    type: string;       // "unreadable_books", "low_confidence", etc.
    severity: string;   // "info", "warning", "error"
    count?: number;
  }[];
  processingTime: number;  // milliseconds
}
```

**Timeout:** 70 seconds (AI 25-40s + enrichment 5-10s)

**AI Model:** Gemini 2.5 Flash

**Enrichment:** Automatic via books-api-proxy RPC (89.7% success rate)

## RPC Service Bindings

Workers communicate via service bindings (NOT direct API calls).

### ISBNdb Worker
- RPC method: `searchByISBN(isbn: string)`
- RPC method: `searchByTitle(query: string)`

### Google Books Worker
- RPC method: `search(query: string, maxResults: number)`
- RPC method: `searchByISBN(isbn: string)`

### OpenLibrary Worker
- RPC method: `search(query: string, limit: number)`
- RPC method: `searchByISBN(isbn: string)`

### ISBNdb Biography Worker
- RPC method: `getBiography(authorName: string)`

## Error Handling

**Standard Error Response:**
```typescript
{
  error: string;      // Human-readable error
  code: number;       // HTTP status
  details?: string;   // Stack trace (dev only)
}
```

**Common Errors:**
- `400`: Invalid request (missing fields, bad ISBN)
- `404`: No results found
- `408`: Timeout (AI processing exceeded 70s)
- `429`: Rate limit exceeded (ISBNdb quota)
- `500`: Internal server error
- `502`: Upstream provider error

## Rate Limits

- **ISBNdb:** 500 requests/month (free tier)
- **Google Books:** No documented limit
- **OpenLibrary:** Polite crawling (1 req/second recommended)
- **Gemini AI:** Cloudflare AI Gateway limits apply

## Caching Strategy

| Endpoint | TTL | KV Namespace |
|----------|-----|--------------|
| /search/title | 6h | BOOKS_CACHE |
| /search/isbn | 7d | BOOKS_CACHE |
| /search/advanced | 6h | BOOKS_CACHE |
| /search/author | 6h | BOOKS_CACHE |
| Popular authors | Permanent | BOOKS_CACHE |

**Cache Key Format:** `provider:query:params`

## Authentication

Currently no authentication required (public API).

## CORS

All workers configured with CORS headers for iOS app domain.

## Monitoring

See `docs/CLOUDFLARE_DEBUGGING.md` for:
- `wrangler tail` commands
- Log filtering patterns
- Debug endpoints
- KV inspection

## Related Documentation

- CLAUDE.md: Backend Architecture section
- cloudflare-workers/README.md: Deployment guide
- cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md: RPC technical details
