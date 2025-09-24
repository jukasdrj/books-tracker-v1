/**
 * ISBNdb Biography Worker - Phase 1 Implementation
 * 
 * Focused minimal worker for ISBNdb author bibliography integration
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
      // Route handling
      if (path.startsWith('/author/') && request.method === 'GET') {
        return await handleAuthorRequest(request, env, path);
      } else if (path.startsWith('/cache/author/') && request.method === 'POST') {
        return await handleCacheRequest(request, env, path);
      } else if (path === '/health') {
        return await handleHealthCheck(env);
      }
      
      return new Response('Not Found', { 
        status: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Endpoint not found' })
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
 * Handle author biography requests
 */
async function handleAuthorRequest(request, env, path) {
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
    
    // Fetch from ISBNdb
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
    
    // Process and filter books
    const processedBooks = bibliography.books
      .filter(book => book.title && book.authors)
      .map(book => selectBestEdition([book]))
      .filter(book => book !== null);
    
    // Cache the results
    const cacheData = {
      books: processedBooks,
      timestamp: new Date().toISOString(),
      source: 'isbndb'
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
      version: '1.0.0-phase1'
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
async function fetchAuthorBibliography(authorName, env) {
  if (!env.ISBNDB_API_KEY) {
    throw new Error('ISBNDB_API_KEY not configured');
  }
  
  // Use exact same format that works with curl
  const url = `https://api2.isbndb.com/author/${encodeURIComponent(authorName)}?pageSize=500&language=en`;
  
  console.log(`ISBNdb request: ${url}`);
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'accept': 'application/json',
      'Authorization': env.ISBNDB_API_KEY  // Exact format that works
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