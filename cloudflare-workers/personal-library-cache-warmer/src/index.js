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
    // ... your existing fetch handler for CSV uploads, status checks, etc. ...
    // This part of your code does not need to change.
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
      // ✅ CORRECT & EFFICIENT: Use direct RPC call
      const result = await env.ISBNDB_WORKER.getAuthorBibliography(author);

      if (result.success && result.works) {
        // Cache the result in the main proxy's format
        await storeNormalizedCache(env, author, result);
        console.log(`✅ Cached ${result.works.length} works for ${author} via RPC`);
      } else {
        console.error(`Failed to get bibliography for ${author}: ${result.error}`);
      }
    } catch (error) {
      console.error(`Error processing author ${author} via RPC:`, error);
    }
  }

  // Update and save the state for the next run
  state.currentIndex = endIndex;
  await env.CACHE.put('processing_state', JSON.stringify(state));
  console.log(`Micro-batch finished. Next run will start from index ${endIndex}.`);
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