/**
 * ISBNdb Biography Worker - Enhanced with Proven Query Patterns
 * 
 * Implements 4 validated ISBNdb API patterns for reliable book data retrieval:
 * 1. Author works in English: /author/{name}?language=en
 * 2. Book by ISBN: /book/{isbn}?with_prices=0
 * 3. Title search: /books/{title}?column=title&language=en&shouldMatchAll=1
 * 4. Combined search: /search/books?author=X&text=Y&publisher=Z
 * 
 * Success target: >90% success rate with test authors
 */

// Rate limiting storage
const RATE_LIMIT_KEY = 'isbndb_last_request';
const RATE_LIMIT_INTERVAL = 1000; // 1 second between requests

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    console.log(`${request.method} ${path}`);
    
    try {
      // Route handling with proven ISBNdb patterns
      if (path.startsWith('/author/') && request.method === 'GET') {
        return await handleAuthorRequest(request, env, path, url);
      } else if (path.startsWith('/book/') && request.method === 'GET') {
        return await handleBookRequest(request, env, path, url);
      } else if (path.startsWith('/books/') && request.method === 'GET') {
        return await handleBooksRequest(request, env, path, url);
      } else if (path.startsWith('/search/books') && request.method === 'GET') {
        return await handleSearchRequest(request, env, path, url);
      } else if (path.startsWith('/cache/author/') && request.method === 'POST') {
        return await handleCacheRequest(request, env, path);
      } else if (path === '/health') {
        return await handleHealthCheck(env);
      }
      
      return new Response(JSON.stringify({ error: 'Endpoint not found' }), { 
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
      
    } catch (error) {
      console.error('Request handler error:', error);
      return new Response(JSON.stringify({ 
        error: 'Internal server error',
        details: error.message 
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
};

/**
 * Handle author biography requests - Pattern 1: Author works in English
 * URL: /author/andy%20weir?page=10&pageSize=50&language=en
 */
async function handleAuthorRequest(request, env, path, url) {
  const authorName = decodeURIComponent(path.replace('/author/', ''));
  
  if (!authorName || authorName.trim().length === 0) {
    return new Response(JSON.stringify({ 
      error: 'Author name is required' 
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  console.log(`Fetching bibliography for author: ${authorName}`);
  
  try {
    // Check cache first
    const cacheKey = `author:${authorName.toLowerCase()}`;
    const cached = await env.KV_CACHE.get(cacheKey, 'json');
    
    if (cached) {
      console.log(`Cache hit for ${authorName}`);
      return new Response(JSON.stringify({
        success: true,
        author: authorName,
        books: cached.books,
        totalBooks: cached.books.length,
        cached: true,
        timestamp: cached.timestamp
      }), {
        status: 200,
        headers: { 
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=3600'
        }
      });
    }
    
    // Rate limiting check
    await enforceRateLimit(env);
    
    // Extract query parameters for proven pattern
    const page = url.searchParams.get('page') || '1';
    const pageSize = url.searchParams.get('pageSize') || '50';
    const language = url.searchParams.get('language') || 'en';
    
    // Fetch from ISBNdb using proven pattern
    const bibliography = await fetchAuthorBibliography(authorName, env, { page, pageSize, language });
    
    if (!bibliography.books || bibliography.books.length === 0) {
      return new Response(JSON.stringify({
        success: false,
        error: 'No books found for author',
        author: authorName
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Process and filter books
    const processedBooks = bibliography.books
      .filter(book => book.title && book.authors)
      .map(book => selectBestEdition([book]))
      .filter(book => book !== null);
    
    // Cache the results
    const cacheData = {
      books: processedBooks,
      timestamp: new Date().toISOString(),
      source: 'isbndb',
      total: bibliography.total || processedBooks.length
    };
    
    await env.KV_CACHE.put(cacheKey, JSON.stringify(cacheData), {
      expirationTtl: 86400 // 24 hours
    });
    
    console.log(`Successfully fetched ${processedBooks.length} books for ${authorName}`);
    
    return new Response(JSON.stringify({
      success: true,
      author: authorName,
      books: processedBooks,
      totalBooks: processedBooks.length,
      total: bibliography.total,
      cached: false,
      timestamp: new Date().toISOString()
    }), {
      status: 200,
      headers: { 
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=3600'
      }
    });
    
  } catch (error) {
    console.error(`Error fetching author ${authorName}:`, error);
    
    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to fetch author bibliography',
      author: authorName,
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Pattern 2: Book by ISBN (10 or 13 digit)
 * URL: /book/9780385539258?with_prices=0
 */
async function handleBookRequest(request, env, path, url) {
  const isbn = path.replace('/book/', '');
  
  if (!isbn || isbn.trim().length === 0) {
    return new Response(JSON.stringify({ error: 'ISBN is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  console.log(`Fetching book by ISBN: ${isbn}`);
  
  try {
    const cacheKey = `book:${isbn}`;
    const cached = await env.KV_CACHE.get(cacheKey, 'json');
    
    if (cached) {
      console.log(`Cache hit for ISBN ${isbn}`);
      return new Response(JSON.stringify({ ...cached, cached: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
      });
    }
    
    await enforceRateLimit(env);
    
    const withPrices = url.searchParams.get('with_prices') || '0';
    const bookData = await fetchBookByISBN(isbn, env, { withPrices });
    
    await env.KV_CACHE.put(cacheKey, JSON.stringify({ ...bookData, timestamp: new Date().toISOString() }), {
      expirationTtl: 86400
    });
    
    return new Response(JSON.stringify({ ...bookData, cached: false }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
    });
    
  } catch (error) {
    console.error(`Error fetching ISBN ${isbn}:`, error);
    return new Response(JSON.stringify({ success: false, error: error.message, isbn }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Pattern 3: Title-only search
 * URL: /books/a%20little%20life?page=1&pageSize=25&column=title&language=en&shouldMatchAll=1
 */
async function handleBooksRequest(request, env, path, url) {
  const title = decodeURIComponent(path.replace('/books/', ''));
  
  if (!title || title.trim().length === 0) {
    return new Response(JSON.stringify({ error: 'Title is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  console.log(`Searching books by title: ${title}`);
  
  try {
    const cacheKey = `books:title:${title.toLowerCase()}`;
    const cached = await env.KV_CACHE.get(cacheKey, 'json');
    
    if (cached) {
      console.log(`Cache hit for title search: ${title}`);
      return new Response(JSON.stringify({ ...cached, cached: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
      });
    }
    
    await enforceRateLimit(env);
    
    const params = {
      page: url.searchParams.get('page') || '1',
      pageSize: url.searchParams.get('pageSize') || '25',
      column: url.searchParams.get('column') || 'title',
      language: url.searchParams.get('language') || 'en',
      shouldMatchAll: url.searchParams.get('shouldMatchAll') || '1'
    };
    
    const booksData = await fetchBooksByTitle(title, env, params);
    
    await env.KV_CACHE.put(cacheKey, JSON.stringify({ ...booksData, timestamp: new Date().toISOString() }), {
      expirationTtl: 86400
    });
    
    return new Response(JSON.stringify({ ...booksData, cached: false }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
    });
    
  } catch (error) {
    console.error(`Error searching title ${title}:`, error);
    return new Response(JSON.stringify({ success: false, error: error.message, title }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Pattern 4: Combined author + title + publisher search
 * URL: /search/books?page=1&pageSize=50&author=andy%20weir&text=the%20martian&publisher=crown
 */
async function handleSearchRequest(request, env, path, url) {
  const author = url.searchParams.get('author');
  const text = url.searchParams.get('text');
  const publisher = url.searchParams.get('publisher');
  
  if (!author && !text && !publisher) {
    return new Response(JSON.stringify({ error: 'At least one search parameter (author, text, publisher) is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  console.log(`Combined search - Author: ${author}, Text: ${text}, Publisher: ${publisher}`);
  
  try {
    const cacheKey = `search:${author || 'none'}:${text || 'none'}:${publisher || 'none'}`;
    const cached = await env.KV_CACHE.get(cacheKey, 'json');
    
    if (cached) {
      console.log(`Cache hit for combined search`);
      return new Response(JSON.stringify({ ...cached, cached: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
      });
    }
    
    await enforceRateLimit(env);
    
    const params = {
      page: url.searchParams.get('page') || '1',
      pageSize: url.searchParams.get('pageSize') || '50',
      author,
      text,
      publisher
    };
    
    const searchData = await fetchCombinedSearch(env, params);
    
    await env.KV_CACHE.put(cacheKey, JSON.stringify({ ...searchData, timestamp: new Date().toISOString() }), {
      expirationTtl: 86400
    });
    
    return new Response(JSON.stringify({ ...searchData, cached: false }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' }
    });
    
  } catch (error) {
    console.error(`Error in combined search:`, error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Handle cache operations
 */
async function handleCacheRequest(request, env, path) {
  const authorName = decodeURIComponent(path.replace('/cache/author/', ''));
  
  if (!authorName || authorName.trim().length === 0) {
    return new Response(JSON.stringify({ 
      error: 'Author name is required' 
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  try {
    // Force refresh from ISBNdb
    await enforceRateLimit(env);
    const bibliography = await fetchAuthorBibliography(authorName, env);
    
    if (!bibliography.books || bibliography.books.length === 0) {
      return new Response(JSON.stringify({
        success: false,
        error: 'No books found for author',
        author: authorName
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    const processedBooks = bibliography.books
      .filter(book => book.title && book.authors)
      .map(book => selectBestEdition([book]))
      .filter(book => book !== null);
    
    // Store in both KV and R2
    const cacheKey = `author:${authorName.toLowerCase()}`;
    const cacheData = {
      books: processedBooks,
      timestamp: new Date().toISOString(),
      source: 'isbndb'
    };
    
    // KV storage (hot cache)
    await env.KV_CACHE.put(cacheKey, JSON.stringify(cacheData), {
      expirationTtl: 86400
    });
    
    // R2 storage (cold cache)
    const r2Key = `authors/${authorName.toLowerCase()}.json`;
    await env.R2_BUCKET.put(r2Key, JSON.stringify(cacheData), {
      httpMetadata: { contentType: 'application/json' }
    });
    
    return new Response(JSON.stringify({
      success: true,
      message: 'Author bibliography cached successfully',
      author: authorName,
      booksCount: processedBooks.length,
      cached: {
        kv: true,
        r2: true
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error(`Error caching author ${authorName}:`, error);
    
    return new Response(JSON.stringify({
      success: false,
      error: 'Failed to cache author bibliography',
      author: authorName,
      details: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Health check endpoint
 */
async function handleHealthCheck(env) {
  const timestamp = new Date().toISOString();
  
  try {
    // Test KV connectivity
    const kvTest = await env.KV_CACHE.get('health:test');
    await env.KV_CACHE.put('health:test', timestamp, { expirationTtl: 60 });
    
    // Test R2 connectivity
    const r2Test = await env.R2_BUCKET.head('health/test.json');
    
    return new Response(JSON.stringify({
      status: 'healthy',
      timestamp,
      services: {
        kv: 'connected',
        r2: 'connected',
        isbndb: env.ISBNDB_API_KEY ? 'configured' : 'missing'
      },
      version: '1.1.0-enhanced',
      patterns: {
        'author_works': '/author/{name}?language=en',
        'book_isbn': '/book/{isbn}?with_prices=0',
        'title_search': '/books/{title}?column=title&language=en',
        'combined_search': '/search/books?author=X&text=Y'
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    return new Response(JSON.stringify({
      status: 'unhealthy',
      timestamp,
      error: error.message
    }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Fetch author bibliography from ISBNdb using proven working pattern
 */
async function fetchAuthorBibliography(authorName, env, params = {}) {
  if (!env.ISBNDB_API_KEY) {
    throw new Error('ISBNDB_API_KEY not configured');
  }

  const apiKey = await env.ISBNDB_API_KEY.get();
  console.log(`ISBNdb API key status: ${apiKey ? 'retrieved' : 'null'}, length: ${apiKey?.length || 0}`);

  if (!apiKey) {
    throw new Error('ISBNDB_API_KEY retrieved but empty');
  }
  
  // Pattern 1: Exact format that works with curl
  const { page = '1', pageSize = '50', language = 'en' } = params;
  const url = `https://api2.isbndb.com/author/${encodeURIComponent(authorName)}?page=${page}&pageSize=${pageSize}&language=${language}`;
  
  console.log(`ISBNdb author request: ${url}`);
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'accept': 'application/json',
      'Authorization': apiKey  // Using secrets store value
    }
  });
  
  console.log(`ISBNdb response status: ${response.status}`);
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`ISBNdb API error: ${response.status} - ${errorText}`);
    throw new Error(`ISBNdb API error: ${response.status} - ${errorText}`);
  }
  
  const data = await response.json();
  console.log(`ISBNdb returned ${data.books?.length || 0} books`);
  
  return data;
}

/**
 * Fetch book by ISBN using proven pattern 2
 */
async function fetchBookByISBN(isbn, env, params = {}) {
  if (!env.ISBNDB_API_KEY) {
    throw new Error('ISBNDB_API_KEY not configured');
  }

  const apiKey = await env.ISBNDB_API_KEY.get();
  console.log(`ISBNdb API key status: ${apiKey ? 'retrieved' : 'null'}, length: ${apiKey?.length || 0}`);

  if (!apiKey) {
    throw new Error('ISBNDB_API_KEY retrieved but empty');
  }
  
  const { withPrices = '0' } = params;
  const url = `https://api2.isbndb.com/book/${isbn}?with_prices=${withPrices}`;
  
  console.log(`ISBNdb book request: ${url}`);
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'accept': 'application/json',
      'Authorization': apiKey
    }
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`ISBNdb book API error: ${response.status} - ${errorText}`);
    throw new Error(`ISBNdb book API error: ${response.status} - ${errorText}`);
  }
  
  const data = await response.json();
  console.log(`ISBNdb returned book data for ISBN ${isbn}`);
  
  return { success: true, book: data.book, source: 'isbndb' };
}

/**
 * Fetch books by title using proven pattern 3
 */
async function fetchBooksByTitle(title, env, params = {}) {
  if (!env.ISBNDB_API_KEY) {
    throw new Error('ISBNDB_API_KEY not configured');
  }

  const apiKey = await env.ISBNDB_API_KEY.get();
  console.log(`ISBNdb API key status: ${apiKey ? 'retrieved' : 'null'}, length: ${apiKey?.length || 0}`);

  if (!apiKey) {
    throw new Error('ISBNDB_API_KEY retrieved but empty');
  }
  
  const { page = '1', pageSize = '25', column = 'title', language = 'en', shouldMatchAll = '1' } = params;
  const url = `https://api2.isbndb.com/books/${encodeURIComponent(title)}?page=${page}&pageSize=${pageSize}&column=${column}&language=${language}&shouldMatchAll=${shouldMatchAll}`;
  
  console.log(`ISBNdb books request: ${url}`);
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'accept': 'application/json',
      'Authorization': apiKey
    }
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`ISBNdb books API error: ${response.status} - ${errorText}`);
    throw new Error(`ISBNdb books API error: ${response.status} - ${errorText}`);
  }
  
  const data = await response.json();
  console.log(`ISBNdb returned ${data.books?.length || 0} books for title search`);
  
  return { success: true, books: data.books, total: data.total, source: 'isbndb' };
}

/**
 * Combined search using proven pattern 4
 */
async function fetchCombinedSearch(env, params = {}) {
  if (!env.ISBNDB_API_KEY) {
    throw new Error('ISBNDB_API_KEY not configured');
  }

  const apiKey = await env.ISBNDB_API_KEY.get();
  console.log(`ISBNdb API key status: ${apiKey ? 'retrieved' : 'null'}, length: ${apiKey?.length || 0}`);

  if (!apiKey) {
    throw new Error('ISBNDB_API_KEY retrieved but empty');
  }
  
  const { page = '1', pageSize = '50', author, text, publisher } = params;
  
  const urlParams = new URLSearchParams({
    page,
    pageSize
  });
  
  if (author) urlParams.append('author', author);
  if (text) urlParams.append('text', text);
  if (publisher) urlParams.append('publisher', publisher);
  
  const url = `https://api2.isbndb.com/search/books?${urlParams.toString()}`;
  
  console.log(`ISBNdb combined search request: ${url}`);
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'accept': 'application/json',
      'Authorization': apiKey
    }
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`ISBNdb search API error: ${response.status} - ${errorText}`);
    throw new Error(`ISBNdb search API error: ${response.status} - ${errorText}`);
  }
  
  const data = await response.json();
  console.log(`ISBNdb returned ${data.books?.length || 0} books for combined search`);
  
  return { success: true, books: data.books, total: data.total, source: 'isbndb' };
}

/**
 * Select the best edition from available books
 */
function selectBestEdition(books, originalISBN = null) {
  if (!books || books.length === 0) return null;
  
  const scoredBooks = books
    .filter(book => book.title && book.authors)
    .map(book => ({
      ...book,
      score: calculateEditionScore(book, originalISBN)
    }))
    .sort((a, b) => b.score - a.score);
  
  return scoredBooks.length > 0 ? scoredBooks[0] : null;
}

/**
 * Calculate quality score for book editions
 */
function calculateEditionScore(book, originalISBN) {
  let score = 0;
  
  // Prefer original ISBN if it matches
  if (originalISBN && (book.isbn13 === originalISBN || book.isbn === originalISBN)) {
    score += 100;
  }
  
  // Avoid low-quality publishers
  const publisher = (book.publisher || '').toLowerCase();
  if (!publisher.includes('createspace') && 
      !publisher.includes('publishamerica') &&
      !publisher.includes('lightning source') &&
      !publisher.includes('independently published')) {
    score += 20;
  }
  
  // Avoid study guides and classroom materials
  const title = (book.title || '').toLowerCase();
  if (!title.includes('study guide') &&
      !title.includes('classroom') &&
      !title.includes('large print') &&
      !title.includes('companion') &&
      !title.includes('workbook') &&
      !title.includes('test prep') &&
      !title.includes('exam guide')) {
    score += 15;
  }
  
  // Prefer standard bindings
  const binding = (book.binding || '').toLowerCase();
  if (binding.includes('hardcover')) score += 10;
  else if (binding.includes('paperback')) score += 8;
  else if (binding.includes('trade paperback')) score += 9;
  
  // Prefer recent editions (better metadata)
  if (book.date_published) {
    const year = parseInt(book.date_published);
    if (year > 2010) score += 8;
    if (year > 2000) score += 5;
  }
  
  // Prefer books with more metadata
  if (book.synopsis) score += 5;
  if (book.dewey_decimal) score += 3;
  if (book.subjects && book.subjects.length > 0) score += 3;
  
  return score;
}

/**
 * Enforce ISBNdb rate limiting (1 request per second)
 */
async function enforceRateLimit(env) {
  try {
    const lastRequest = await env.KV_CACHE.get(RATE_LIMIT_KEY);
    
    if (lastRequest) {
      const lastTime = parseInt(lastRequest);
      const now = Date.now();
      const timeDiff = now - lastTime;
      
      if (timeDiff < RATE_LIMIT_INTERVAL) {
        const waitTime = RATE_LIMIT_INTERVAL - timeDiff;
        console.log(`Rate limiting: waiting ${waitTime}ms`);
        await new Promise(resolve => setTimeout(resolve, waitTime));
      }
    }
    
    // Store current timestamp
    await env.KV_CACHE.put(RATE_LIMIT_KEY, Date.now().toString(), {
      expirationTtl: 60
    });
    
  } catch (error) {
    console.warn('Rate limiting error:', error);
    // Don't fail the request due to rate limiting issues
  }
}