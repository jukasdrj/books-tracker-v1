/**
 * Personal Library Cache Warmer - RPC Enhanced
 *
 * Uses direct RPC calls to the ISBNdb worker for reliable and efficient
 * author bibliography fetching during the cache warming process.
 */

const CACHE_TTL = 86400 * 7; // 7 days

export default {
  async scheduled(event, env, ctx) {
    console.log(`CRON: Starting micro-batch processing`);
    ctx.waitUntil(processMicroBatch(env, 25)); // Process 25 authors every 15 mins
  },
  
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/status') {
      // Status endpoint
      const libraryData = await env.CACHE.get('current_library', 'json');
      const state = await env.CACHE.get('processing_state', 'json') || { currentIndex: 0 };

      return new Response(JSON.stringify({
        status: 'running',
        authors_count: libraryData?.authors?.length || 0,
        current_index: state.currentIndex,
        next_batch_in: '5 minutes (every 5 min cron)',
        popular_authors: libraryData?.authors?.slice(0, 10) || []
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (request.method === 'POST' && url.pathname === '/upload-authors') {
      // CSV upload endpoint
      const text = await request.text();
      const authors = text.split(',').map(a => a.trim()).filter(a => a.length > 0);

      if (authors.length === 0) {
        return new Response('No valid authors found', { status: 400 });
      }

      const libraryData = {
        authors: authors,
        uploaded_at: new Date().toISOString(),
        count: authors.length
      };

      await env.CACHE.put('current_library', JSON.stringify(libraryData));

      // Reset processing state
      await env.CACHE.put('processing_state', JSON.stringify({ currentIndex: 0 }));

      return new Response(JSON.stringify({
        success: true,
        message: `Uploaded ${authors.length} authors for cache warming`,
        authors: authors
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (request.method === 'POST' && url.pathname === '/bootstrap-popular') {
      // Bootstrap with popular authors
      const popularAuthors = [
        'Stephen King', 'J.K. Rowling', 'Andy Weir', 'Neil Gaiman', 'Margaret Atwood',
        'George R.R. Martin', 'Brandon Sanderson', 'Agatha Christie', 'Isaac Asimov',
        'Ursula K. Le Guin', 'Ray Bradbury', 'Douglas Adams', 'Terry Pratchett',
        'Gillian Flynn', 'John Grisham', 'Dan Brown', 'Suzanne Collins', 'Toni Morrison',
        'Harper Lee', 'F. Scott Fitzgerald', 'Ernest Hemingway', 'Jane Austen',
        'George Orwell', 'Aldous Huxley', 'Kurt Vonnegut', 'Philip K. Dick',
        'Octavia Butler', 'Liu Cixin', 'Kim Stanley Robinson'
      ];

      const libraryData = {
        authors: popularAuthors,
        uploaded_at: new Date().toISOString(),
        count: popularAuthors.length,
        type: 'bootstrap_popular'
      };

      await env.CACHE.put('current_library', JSON.stringify(libraryData));
      await env.CACHE.put('processing_state', JSON.stringify({ currentIndex: 0 }));

      return new Response(JSON.stringify({
        success: true,
        message: `Bootstrapped with ${popularAuthors.length} popular authors`,
        authors: popularAuthors
      }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response("Cache warmer is running on a schedule.", { status: 200 });
  }
};

/**
 * Processes a micro-batch of authors from the library using RPC.
 */
async function processMicroBatch(env, maxAuthors = 25) {
  console.log(`Processing micro-batch of up to ${maxAuthors} authors.`);
  
  const libraryData = await env.CACHE.get('current_library', 'json');
  if (!libraryData || !libraryData.authors) {
    console.log('No library data found. Aborting micro-batch.');
    return;
  }

  let state = await env.CACHE.get('processing_state', 'json') || { currentIndex: 0 };
  
  const startIndex = state.currentIndex;
  const endIndex = Math.min(startIndex + maxAuthors, libraryData.authors.length);
  const authorsToProcess = libraryData.authors.slice(startIndex, endIndex);

  if (authorsToProcess.length === 0) {
      console.log("All authors processed. Resetting for next cycle.");
      state.currentIndex = 0; // Reset for the next full run
      await env.CACHE.put('processing_state', JSON.stringify(state));
      return;
  }

  console.log(`Processing authors from index ${startIndex} to ${endIndex - 1}`);

  for (const author of authorsToProcess) {
    try {
      // ✅ CORRECT: Use OpenLibrary worker for author bibliography
      const result = await env.OPENLIBRARY_WORKER.getAuthorWorks(author);

      if (result.success && result.works) {
        // Transform OpenLibrary works to proxy cache format
        const transformedResult = transformOpenLibraryToProxyFormat(result, author);
        await storeNormalizedCache(env, author, transformedResult);
        console.log(`✅ Cached ${result.works.length} works for ${author} via OpenLibrary RPC`);
      } else {
        console.error(`Failed to get bibliography for ${author}: ${result.error || 'No works found'}`);
      }
    } catch (error) {
      console.error(`Error processing author ${author} via OpenLibrary RPC:`, error);
    }
  }

  // Update and save the state for the next run
  state.currentIndex = endIndex;
  await env.CACHE.put('processing_state', JSON.stringify(state));
  console.log(`Micro-batch finished. Next run will start from index ${endIndex}.`);
}

/**
 * Transform OpenLibrary author works response to books-api-proxy cache format
 */
function transformOpenLibraryToProxyFormat(openLibraryResult, authorName) {
  const works = openLibraryResult.works || [];

  // Transform each OpenLibrary work to Google Books API compatible format
  const transformedItems = works.map(work => ({
    kind: "books#volume",
    id: work.openLibraryWorkKey || `ol-${work.title?.replace(/\s+/g, '-').toLowerCase()}`,
    volumeInfo: {
      title: work.title || 'Unknown Title',
      subtitle: work.subtitle || "",
      authors: [authorName], // Use the searched author name for consistency
      publishedDate: work.firstPublicationYear?.toString() || "",
      description: work.description || "",
      industryIdentifiers: [],
      pageCount: 0,
      categories: work.subjects || [],
      imageLinks: work.coverImageURL ? {
        thumbnail: work.coverImageURL,
        smallThumbnail: work.coverImageURL
      } : undefined,

      // Enhanced cross-reference identifiers from our OpenLibrary worker
      crossReferenceIds: {
        openLibraryWorkId: work.openLibraryWorkKey,
        openLibraryEditionId: null,
        goodreadsWorkIds: [],
        amazonASINs: [],
        googleBooksVolumeIds: [],
        librarythingIds: [],
        isbndbIds: []
      }
    }
  }));

  // Return in books-api-proxy response format
  return {
    kind: "books#volumes",
    totalItems: transformedItems.length,
    items: transformedItems,
    format: "enhanced_work_edition_v1",
    provider: "openlibrary-cache-warmer",
    cached: true,
    responseTime: 0
  };
}

/**
 * Stores the normalized data in the format expected by the books-api-proxy.
 */
async function storeNormalizedCache(env, authorName, resultData) {
  const normalizedQuery = authorName.toLowerCase().trim();
  const queryB64 = btoa(normalizedQuery).replace(/[/+=]/g, '_');
  const defaultParams = { maxResults: 40, showAllEditions: false, sortBy: 'relevance' };
  const paramsString = Object.keys(defaultParams).sort().map(key => `${key}=${defaultParams[key]}`).join('&');
  const paramsB64 = btoa(paramsString).replace(/[/+=]/g, '_');
  const autoSearchKey = `auto-search:${queryB64}:${paramsB64}`;

  await env.CACHE.put(autoSearchKey, JSON.stringify(resultData), { expirationTtl: CACHE_TTL });
}