# Google Books Worker

A specialized Cloudflare Worker that provides Google Books API integration for the BooksTracker ecosystem. This worker normalizes Google Books API responses into the consistent format used across all BooksTracker workers.

## Features

- **RPC Interface**: Designed for service binding integration with books-api-proxy
- **Dual Search Methods**: General search and ISBN-specific search
- **Response Normalization**: Converts Google Books API format to BooksTracker Work/Edition schema
- **Analytics Integration**: Performance metrics via Analytics Engine
- **Error Resilience**: Comprehensive error handling and graceful degradation

## API Methods

### `search(query, params)`
General search against Google Books API.

**Parameters:**
- `query` (string): Search query
- `params` (object): Optional parameters
  - `maxResults` (number): Maximum results to return (default: 20)

**Example:**
```javascript
const result = await env.GOOGLE_BOOKS_WORKER.search("Andy Weir", { maxResults: 10 });
```

### `searchByISBN(isbn)`
Search for a specific book by ISBN.

**Parameters:**
- `isbn` (string): ISBN-10 or ISBN-13

**Example:**
```javascript
const result = await env.GOOGLE_BOOKS_WORKER.searchByISBN("9780553418026");
```

## Response Format

All methods return a normalized response with:

```javascript
{
  success: boolean,
  provider: "google-books",
  processingTime: number, // ms
  works: [
    {
      title: string,
      subtitle: string,
      authors: [{ name: string }],
      firstPublishYear: number,
      editions: [
        {
          googleBooksVolumeId: string,
          isbn13: string,
          isbn10: string,
          title: string,
          publisher: string,
          publishDate: string,
          publishYear: number,
          pages: number,
          language: string,
          genres: string[],
          description: string,
          coverImageURL: string,
          previewLink: string,
          infoLink: string,
          source: "google-books"
        }
      ]
    }
  ],
  authors: [
    {
      name: string,
      source: "google-books"
    }
  ]
}
```

## Configuration

### Secrets (via Secrets Store)
- `GOOGLE_BOOKS_API_KEY`: Google Books API key

### Analytics
- `GOOGLE_BOOKS_ANALYTICS`: Analytics Engine dataset for performance tracking

### Cache
- `KV_CACHE`: KV namespace for response caching (production environment)

## Integration with books-api-proxy

Add the service binding to `books-api-proxy/wrangler.toml`:

```toml
[[services]]
binding = "GOOGLE_BOOKS_WORKER"
service = "google-books-worker-production"
entrypoint = "GoogleBooksWorker"
```

Use in proxy code:
```javascript
// General search
const result = await env.GOOGLE_BOOKS_WORKER.search(query);

// ISBN search
const result = await env.GOOGLE_BOOKS_WORKER.searchByISBN(isbn);
```

## Deployment

### Development
```bash
npm run dev
```

### Production
```bash
npm run deploy:production
```

### Health Check
```bash
curl https://google-books-worker-production.jukasdrj.workers.dev/health
```

## Monitoring

### Tail Logs
```bash
npm run tail
```

### Analytics Queries
Performance metrics are written to the `google_books_performance` dataset with:
- Search queries and types
- Processing times
- Result counts
- Error tracking

## Architecture Notes

This worker follows the BooksTracker specialist worker pattern:
- Single responsibility (Google Books API only)
- RPC interface for service binding
- Consistent error handling
- Analytics integration
- Normalized response format

It serves as a plug-and-play component in the BooksTracker ecosystem, allowing the main proxy to leverage Google Books data alongside OpenLibrary and ISBNdb sources.