import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { cache } from 'hono/cache';
import { etag } from 'hono/etag';
import { timing } from 'hono/timing';
import { logger, logMiddleware } from './utils/logging';
import { getClientIp } from './utils/request';
import { contentNegotiation } from './middleware/contentNegotiation';
import { rateLimiter } from './middleware/rateLimiter';
import { searchHandler } from './handlers/searchHandler';
import { isbnHandler } from './handlers/isbnHandler';
import { authorHandler } from './handlers/authorHandler';
import { multiContextSearchHandler } from './handlers/multiContextSearchHandler';
import { getCorsConfig, getCacheConfig } from './config/appConfig';

// Define the environment bindings
export type Env = {
  AI: Ai;
  CACHE: KVNamespace;
  API_CACHE_COLD: R2Bucket;
  LIBRARY_DATA: R2Bucket;
  PERFORMANCE_ANALYTICS: AnalyticsEngineDataset;
  CACHE_ANALYTICS: AnalyticsEngineDataset;
  PROVIDER_ANALYTICS: AnalyticsEngineDataset;
  EXTERNAL_APIS_WORKER: Fetcher;
  GOOGLE_BOOKS_API_KEY: string;
  GOOGLE_BOOKS_IOSKEY: string;
  ISBNDB_API_KEY: string;
  ISBN_SEARCH_KEY: string;
  CACHE_HOT_TTL: string;
  CACHE_COLD_TTL: string;
  MAX_RESULTS_DEFAULT: string;
  RATE_LIMIT_MS: string;
  CONCURRENCY_LIMIT: string;
  AGGRESSIVE_CACHING: string;
  ENABLE_PERFORMANCE_LOGGING: string;
  ENABLE_CACHE_ANALYTICS: string;
  ENABLE_PROVIDER_METRICS: string;
  LOG_LEVEL: string;
  STRUCTURED_LOGGING: string;
};

// Initialize Hono app
const app = new Hono<{ Bindings: Env }>();

// --- Middleware ---
app.use('*', timing());
app.use('*', etag());
app.use('*', contentNegotiation);
app.use('*', cors(getCorsConfig()));
app.use('*', (c, next) => logMiddleware(c, next));
app.use('*', (c, next) => rateLimiter(c, next));

// --- Caching ---
app.get('*', cache(getCacheConfig()));

// --- Routes ---
app.get('/', (c) => c.text('Books API Proxy is running!'));

// Health check
app.get('/health', (c) => {
  const ip = getClientIp(c);
  return c.json({ status: 'ok', ip: ip, timestamp: new Date().toISOString() });
});

// Search for books by query (title, author, etc.)
app.get('/search', searchHandler);

// Get book details by ISBN
app.get('/isbn/:isbn', isbnHandler);

// Get books by author
app.get('/author/:author', authorHandler);

// Multi-context search (e.g., title and author)
app.post('/search/multi', multiContextSearchHandler);

// AI-powered bookshelf scanner
app.post('/ai/scan-bookshelf', async (c) => {
  const log = logger(c);
  try {
    const imageBlob = await c.req.blob();
    if (imageBlob.size === 0) {
      return c.json({ error: 'No image data received' }, 400);
    }
    const imageBytes = await imageBlob.arrayBuffer();

    log.info('Received image for analysis. Calling Workers AI...');

    const inputs = {
      image: [...new Uint8Array(imageBytes)],
      prompt: `
        You are an expert librarian's assistant specialized in digitizing bookshelves from images. You will be given an image containing one or more books.

        Your task is to:
        1. Identify every visible book spine in the image.
        2. For each spine, accurately read the text to determine the book's title and author.
        3. Return the data as a single, valid JSON array.

        Each object in the array must have the following keys:
        - "title": The full title of the book.
        - "author": The author's name. If the author is not visible or cannot be determined, the value should be null.

        If you cannot confidently identify the title of a book on a spine, do not include it in the array. Do not return any text other than the JSON array itself.
      `,
    };

    const modelResponse = await c.env.AI.run('@cf/llava-hf/llava-1.5-7b-hf', inputs);

    log.info('Received response from Workers AI. Parsing result...');
    
    let jsonString = modelResponse.response || '';
    if (jsonString.startsWith('```json')) {
      jsonString = jsonString.substring(7, jsonString.length - 3).trim();
    }

    const booksJson = JSON.parse(jsonString);
    return c.json(booksJson);

  } catch (err) {
    const error = err as Error;
    log.error(`Bookshelf scan failed: ${error.message}`, { stack: error.stack });
    return c.json({ error: 'Failed to analyze bookshelf image.', message: error.message }, 500);
  }
});

// --- Error Handling ---
app.onError((err, c) => {
  const log = logger(c);
  log.error(`Hono Error: ${err.message}`, {
    path: c.req.path,
    method: c.req.method,
    ip: getClientIp(c),
    stack: err.stack,
  });
  return c.json({ error: 'Internal Server Error', message: err.message }, 500);
});

app.notFound((c) => {
  return c.json({ error: 'Not Found', message: `The path ${c.req.path} was not found.` }, 404);
});

export default app;
