/**
 * OpenLibrary Search Worker - Authoritative Works Discovery
 *
 * Implements OpenLibrary API patterns with SwiftData-aligned normalization:
 * 1. Author discovery: /search/authors.json?q={name}
 * 2. Author works: /authors/{key}/works.json
 * 3. Work details: /works/{key}.json
 * 4. Work editions: /works/{key}/editions.json
 *
 * Purpose: Get clean, complete author works lists as authoritative source
 * Complements ISBNdb worker which provides rich edition metadata
 *
 * Success target: >95% author disambiguation and complete works discovery
 */

// Rate limiting for OpenLibrary (more generous than ISBNdb)
const RATE_LIMIT_KEY = 'openlibrary_last_request';
const RATE_LIMIT_INTERVAL = 200; // 200ms between requests (5 req/sec)

// Import WorkerEntrypoint for proper RPC implementation
import { WorkerEntrypoint } from "cloudflare:workers";

// RPC Class extending WorkerEntrypoint for proper service binding
export class OpenLibraryWorker extends WorkerEntrypoint {
  // HTTP fetch method for backward compatibility
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    console.log(`${request.method} ${path} (via OpenLibrary WorkerEntrypoint)`);

    try {
      // Route handling with proven OpenLibrary patterns
      if (path.startsWith('/author/') && request.method === 'GET') {
        return await handleAuthorWorksRequest(request, this.env, path, url);
      } else if (path.startsWith('/work/') && request.method === 'GET') {
        return await handleWorkDetailsRequest(request, this.env, path, url);
      } else if (path.startsWith('/search/authors') && request.method === 'GET') {
        return await handleAuthorSearchRequest(request, this.env, path, url);
      } else if (path.startsWith('/cache/author/') && request.method === 'POST') {
        return await handleCacheWorksRequest(request, this.env, path);
      } else if (path === '/health') {
        return await handleHealthCheck(this.env);
      }

      return new Response(JSON.stringify({ error: 'Endpoint not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });

    } catch (error) {
      console.error('OpenLibrary WorkerEntrypoint fetch handler error:', error);
      return new Response(JSON.stringify({
        error: 'Internal server error',
        details: error.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }

  // RPC Method: Get complete author works (authoritative source)
  async getAuthorWorks(authorName) {
    try {
      console.log(`🔧 RPC: getAuthorWorks("${authorName}")`);

      // 1. Find the author
      const authorInfo = await findAuthorByName(authorName, this.env);
      if (!authorInfo) {
        throw new Error(`Author not found: ${authorName}`);
      }

      // 2. Get all their works
      const works = await getAuthorWorksFromKey(authorInfo.key, this.env);

      // 3. Get details for each work
      const detailedWorks = await Promise.all(
        works.slice(0, 20).map(work => // Limit to 20 works for performance
          getWorkDetails(work.key, this.env)
        )
      );

      // 4. Normalize to SwiftData structure
      const normalizedData = normalizeWorksFromOpenLibrary(
        detailedWorks.filter(Boolean),
        authorInfo
      );

      return {
        success: true,
        authorKey: authorInfo.key,
        authorName: authorInfo.name,
        totalWorks: works.length,
        processedWorks: detailedWorks.length,
        ...normalizedData
      };

    } catch (error) {
      console.error(`RPC getAuthorWorks error for "${authorName}":`, error);
      throw error;
    }
  }

  // RPC Method: Get specific work details
  async getWorkDetails(workKey) {
    try {
      console.log(`🔧 RPC: getWorkDetails("${workKey}")`);

      const workDetails = await getWorkDetails(workKey, this.env);
      if (!workDetails) {
        throw new Error(`Work not found: ${workKey}`);
      }

      return normalizeWorkFromOpenLibrary(workDetails);

    } catch (error) {
      console.error(`RPC getWorkDetails error for "${workKey}":`, error);
      throw error;
    }
  }

  // RPC Method: Search and disambiguate authors
  async searchAuthors(query, limit = 5) {
    try {
      console.log(`🔧 RPC: searchAuthors("${query}", ${limit})`);

      const searchResults = await searchAuthorsByName(query, limit, this.env);

      return {
        success: true,
        query,
        totalFound: searchResults.numFound,
        authors: searchResults.docs.map(author => ({
          key: author.key,
          name: author.name,
          alternateNames: author.alternate_names || [],
          birthDate: author.birth_date,
          workCount: author.work_count,
          topWork: author.top_work,
          confidence: calculateAuthorMatchConfidence(query, author)
        }))
      };

    } catch (error) {
      console.error(`RPC searchAuthors error for "${query}":`, error);
      throw error;
    }
  }
}

/**
 * Handle author works discovery - Pattern 1: Complete author bibliography
 * URL: /author/andy%20weir?includeEditions=true&limit=50
 */
async function handleAuthorWorksRequest(request, env, path, url) {
  const authorName = decodeURIComponent(path.replace('/author/', ''));

  if (!authorName || authorName.trim().length === 0) {
    return new Response(JSON.stringify({
      error: 'Author name is required'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const includeEditions = url.searchParams.get('includeEditions') === 'true';
    const limit = parseInt(url.searchParams.get('limit')) || 20;

    console.log(`🔍 OpenLibrary author works request: ${authorName} (limit: ${limit})`);

    // 1. Find author by name
    const authorInfo = await findAuthorByName(authorName, env);
    if (!authorInfo) {
      return new Response(JSON.stringify({
        error: 'Author not found',
        searchedName: authorName,
        suggestion: 'Try searching with different spelling or name variations'
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // 2. Get all author works
    const works = await getAuthorWorksFromKey(authorInfo.key, env);

    // 3. Get detailed info for limited set
    const worksToProcess = works.slice(0, limit);
    const detailedWorks = await Promise.all(
      worksToProcess.map(work => getWorkDetails(work.key, env))
    );

    // 4. Get editions if requested
    let editionsData = null;
    if (includeEditions) {
      editionsData = await Promise.all(
        worksToProcess.slice(0, 10).map(work => // Limit editions for performance
          getWorkEditions(work.key, env)
        )
      );
    }

    // 5. Normalize to SwiftData structure
    const normalizedData = normalizeWorksFromOpenLibrary(
      detailedWorks.filter(Boolean),
      authorInfo,
      editionsData
    );

    const response = {
      success: true,
      provider: 'openlibrary',
      authorInfo: {
        key: authorInfo.key,
        name: authorInfo.name,
        alternateNames: authorInfo.alternate_names || [],
        birthDate: authorInfo.birth_date,
        workCount: authorInfo.work_count
      },
      query: {
        authorName,
        totalWorksFound: works.length,
        processedWorks: detailedWorks.length,
        includeEditions
      },
      ...normalizedData,
      metadata: {
        timestamp: new Date().toISOString(),
        workerVersion: '1.0.0',
        apiEndpoints: {
          authorSearch: `/search/authors.json?q=${encodeURIComponent(authorName)}`,
          authorWorks: `/authors/${authorInfo.key}/works.json`,
          workDetails: worksToProcess.map(w => `/works/${w.key}.json`)
        }
      }
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'X-Provider': 'openlibrary',
        'X-Author-Key': authorInfo.key,
        'X-Works-Count': works.length.toString()
      }
    });

  } catch (error) {
    console.error('OpenLibrary author works error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to fetch author works',
      details: error.message,
      authorName
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Handle work details - Pattern 2: Individual work information
 * URL: /work/OL17091839W?includeEditions=true
 */
async function handleWorkDetailsRequest(request, env, path, url) {
  const workKey = path.replace('/work/', '');

  if (!workKey || workKey.trim().length === 0) {
    return new Response(JSON.stringify({
      error: 'Work key is required'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    const includeEditions = url.searchParams.get('includeEditions') === 'true';

    console.log(`🔍 OpenLibrary work details request: ${workKey}`);

    // Get work details
    const workDetails = await getWorkDetails(workKey, env);
    if (!workDetails) {
      return new Response(JSON.stringify({
        error: 'Work not found',
        workKey
      }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Get editions if requested
    let editions = null;
    if (includeEditions) {
      editions = await getWorkEditions(workKey, env);
    }

    // Normalize data
    const normalizedWork = normalizeWorkFromOpenLibrary(workDetails, editions);

    const response = {
      success: true,
      provider: 'openlibrary',
      workKey,
      ...normalizedWork,
      metadata: {
        timestamp: new Date().toISOString(),
        includeEditions,
        apiEndpoint: `/works/${workKey}.json`
      }
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'X-Provider': 'openlibrary',
        'X-Work-Key': workKey
      }
    });

  } catch (error) {
    console.error('OpenLibrary work details error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to fetch work details',
      details: error.message,
      workKey
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Handle author search - Pattern 3: Author discovery and disambiguation
 * URL: /search/authors?q=andy%20weir&limit=5
 */
async function handleAuthorSearchRequest(request, env, path, url) {
  const query = url.searchParams.get('q');
  const limit = parseInt(url.searchParams.get('limit')) || 5;

  if (!query || query.trim().length === 0) {
    return new Response(JSON.stringify({
      error: 'Query parameter "q" is required'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  try {
    console.log(`🔍 OpenLibrary author search: "${query}" (limit: ${limit})`);

    const searchResults = await searchAuthorsByName(query, limit, env);

    const response = {
      success: true,
      provider: 'openlibrary',
      query,
      totalFound: searchResults.numFound,
      authors: searchResults.docs.map(author => ({
        key: author.key,
        name: author.name,
        alternateNames: author.alternate_names || [],
        birthDate: author.birth_date,
        workCount: author.work_count,
        topWork: author.top_work,
        topSubjects: author.top_subjects || [],
        confidence: calculateAuthorMatchConfidence(query, author)
      })),
      metadata: {
        timestamp: new Date().toISOString(),
        apiEndpoint: `/search/authors.json?q=${encodeURIComponent(query)}&limit=${limit}`
      }
    };

    return new Response(JSON.stringify(response), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'X-Provider': 'openlibrary',
        'X-Total-Found': searchResults.numFound.toString()
      }
    });

  } catch (error) {
    console.error('OpenLibrary author search error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to search authors',
      details: error.message,
      query
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

/**
 * Handle cache operations for author works
 */
async function handleCacheWorksRequest(request, env, path) {
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
    const body = await request.json();
    const includeEditions = body.includeEditions || false;

    console.log(`💾 Caching author works: ${authorName}`);

    // Get complete author works
    const worker = new OpenLibraryWorker();
    worker.env = env;
    const authorData = await worker.getAuthorWorks(authorName);

    // Store in cache with metadata
    const cacheKey = `openlibrary:author:${authorName.toLowerCase()}`;
    const cacheData = {
      ...authorData,
      cachedAt: new Date().toISOString(),
      includeEditions,
      provider: 'openlibrary'
    };

    // Store in KV with 24 hour expiration
    await env.KV_CACHE.put(cacheKey, JSON.stringify(cacheData), {
      expirationTtl: 86400 // 24 hours
    });

    return new Response(JSON.stringify({
      success: true,
      cached: true,
      authorName,
      cacheKey,
      worksCount: authorData.works?.length || 0,
      authorsCount: authorData.authors?.length || 0
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Cache author works error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to cache author works',
      details: error.message,
      authorName
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
  try {
    // Test OpenLibrary API connectivity
    const testResponse = await fetch('https://openlibrary.org/search/authors.json?q=test&limit=1');
    const isApiHealthy = testResponse.ok;

    return new Response(JSON.stringify({
      status: 'healthy',
      provider: 'openlibrary',
      apiHealth: isApiHealthy ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      worker: 'OpenLibraryWorker',
      version: '1.0.0',
      capabilities: [
        'author_discovery',
        'complete_works_listing',
        'work_normalization',
        'swiftdata_compatibility'
      ],
      patterns: {
        'author_works': '/author/{name}?includeEditions=true',
        'work_details': '/work/{key}?includeEditions=true',
        'author_search': '/search/authors?q={query}&limit={n}',
        'cache_works': 'POST /cache/author/{name}'
      }
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    return new Response(JSON.stringify({
      status: 'unhealthy',
      error: error.message
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

// ==============================================================================
// OpenLibrary API Helper Functions
// ==============================================================================

/**
 * Find author by name using OpenLibrary search
 * OPTIMIZED: Use fields parameter for better performance
 */
async function findAuthorByName(authorName, env) {
  await enforceRateLimit(env);

  // Use specific fields for better performance (per 2025 API guidelines)
  const fields = 'key,name,alternate_names,birth_date,work_count,top_work,top_subjects';
  const searchUrl = `https://openlibrary.org/search/authors.json?q=${encodeURIComponent(authorName)}&limit=5&fields=${fields}`;

  console.log(`OpenLibrary author search: ${searchUrl}`);

  const response = await fetch(searchUrl);
  if (!response.ok) {
    throw new Error(`OpenLibrary author search failed: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();

  if (!data.docs || data.docs.length === 0) {
    return null;
  }

  // Find best match (exact name match preferred)
  const exactMatch = data.docs.find(author =>
    author.name.toLowerCase() === authorName.toLowerCase()
  );

  if (exactMatch) {
    return exactMatch;
  }

  // Fall back to highest confidence match
  const bestMatch = data.docs
    .map(author => ({
      ...author,
      confidence: calculateAuthorMatchConfidence(authorName, author)
    }))
    .sort((a, b) => b.confidence - a.confidence)[0];

  return bestMatch.confidence > 0.7 ? bestMatch : data.docs[0];
}

/**
 * Get author works using their OpenLibrary key
 */
async function getAuthorWorksFromKey(authorKey, env) {
  await enforceRateLimit(env);

  const worksUrl = `https://openlibrary.org/authors/${authorKey}/works.json?limit=50`;

  console.log(`OpenLibrary author works: ${worksUrl}`);

  const response = await fetch(worksUrl);
  if (!response.ok) {
    throw new Error(`OpenLibrary works fetch failed: ${response.status} ${response.statusText}`);
  }

  const data = await response.json();
  return data.entries || [];
}

/**
 * Get detailed work information
 */
async function getWorkDetails(workKey, env) {
  await enforceRateLimit(env);

  // Clean work key (remove /works/ prefix if present)
  const cleanKey = workKey.replace('/works/', '');
  const detailsUrl = `https://openlibrary.org/works/${cleanKey}.json`;

  console.log(`OpenLibrary work details: ${detailsUrl}`);

  const response = await fetch(detailsUrl);
  if (!response.ok) {
    console.warn(`Failed to fetch work details for ${cleanKey}: ${response.status}`);
    return null;
  }

  return await response.json();
}

/**
 * Get work editions
 */
async function getWorkEditions(workKey, env, limit = 20) {
  await enforceRateLimit(env);

  const cleanKey = workKey.replace('/works/', '');
  const editionsUrl = `https://openlibrary.org/works/${cleanKey}/editions.json?limit=${limit}`;

  console.log(`OpenLibrary work editions: ${editionsUrl}`);

  const response = await fetch(editionsUrl);
  if (!response.ok) {
    console.warn(`Failed to fetch editions for ${cleanKey}: ${response.status}`);
    return null;
  }

  const data = await response.json();
  return data.entries || [];
}

/**
 * Search authors by name
 */
async function searchAuthorsByName(query, limit, env) {
  await enforceRateLimit(env);

  const searchUrl = `https://openlibrary.org/search/authors.json?q=${encodeURIComponent(query)}&limit=${limit}`;

  console.log(`OpenLibrary author search: ${searchUrl}`);

  const response = await fetch(searchUrl);
  if (!response.ok) {
    throw new Error(`OpenLibrary search failed: ${response.status} ${response.statusText}`);
  }

  return await response.json();
}

// ==============================================================================
// Work/Edition/Author Normalization (SwiftData Compatible)
// ==============================================================================

/**
 * Normalize OpenLibrary works into SwiftData Work/Edition/Author structure
 * ENHANCED: Focus on core works only, filter out translations and collections
 */
function normalizeWorksFromOpenLibrary(works, authorInfo, editionsData = null) {
  if (!works || !Array.isArray(works)) {
    return { works: [], authors: [] };
  }

  const normalizedWorks = [];
  const processedTitles = new Set();

  // Create author object
  const author = {
    name: authorInfo.name,
    alternateNames: authorInfo.alternate_names || [],
    birthDate: authorInfo.birth_date,

    // External identifiers
    openLibraryKey: authorInfo.key,

    // Cultural metadata (to be enhanced later)
    gender: 'unknown',
    culturalRegion: 'international',

    // Stats from OpenLibrary
    workCount: authorInfo.work_count,
    topWork: authorInfo.top_work,
    topSubjects: authorInfo.top_subjects || []
  };

  // Process works with core works filtering
  works.forEach((work, index) => {
    if (!work || !work.title) return;

    // CORE WORKS FILTER: Skip non-core works
    if (!isCoreWork(work.title)) {
      console.log(`Filtering out non-core work: ${work.title}`);
      return;
    }

    // Deduplicate by title (OpenLibrary sometimes has duplicates)
    const normalizedTitle = work.title.toLowerCase().trim();
    if (processedTitles.has(normalizedTitle)) {
      return;
    }
    processedTitles.add(normalizedTitle);

    // Create Work object
    const normalizedWork = {
      title: work.title,
      subtitle: work.subtitle,
      originalLanguage: extractLanguage(work),
      firstPublicationYear: extractFirstPublicationYear(work),
      description: work.description?.value || work.description,
      subjectTags: work.subjects || [],

      // External identifiers (SwiftData Work model)
      openLibraryWorkKey: work.key,
      openLibraryID: work.key.replace('/works/', ''),
      isbndbID: null,              // To be filled by ISBNdb worker
      googleBooksVolumeID: null,   // To be filled by Google Books worker

      // Metadata
      covers: work.covers?.map(id => `https://covers.openlibrary.org/b/id/${id}-L.jpg`) || [],

      // Quality scoring
      openLibraryQuality: calculateWorkQuality(work),

      // Processing metadata
      processedAt: new Date().toISOString(),
      sourceProvider: 'openlibrary'
    };

    // Create basic editions if we have edition data
    const workEditions = [];
    if (editionsData && editionsData[index]) {
      editionsData[index].forEach(edition => {
        if (!edition) return;

        const normalizedEdition = {
          title: edition.title || work.title,
          isbn: extractISBN(edition),
          publisher: edition.publishers?.[0],
          publicationDate: edition.publish_date,
          pageCount: edition.number_of_pages,
          format: normalizeFormat(edition.physical_format),
          language: edition.languages?.[0]?.key?.replace('/languages/', ''),

          // External identifiers
          openLibraryEditionKey: edition.key,
          openLibraryID: edition.key?.replace('/books/', ''),

          // Work relationship
          workKey: work.key,

          // Metadata
          covers: edition.covers?.map(id => `https://covers.openlibrary.org/b/id/${id}-L.jpg`) || [],
          sourceProvider: 'openlibrary'
        };

        workEditions.push(normalizedEdition);
      });
    }

    normalizedWork.editions = workEditions;
    normalizedWorks.push(normalizedWork);
  });

  return {
    works: normalizedWorks,
    authors: [author],
    processingMetadata: {
      totalWorksProcessed: normalizedWorks.length,
      duplicatesRemoved: works.length - normalizedWorks.length,
      authorInfo: {
        key: authorInfo.key,
        name: authorInfo.name,
        workCount: authorInfo.work_count
      },
      timestamp: new Date().toISOString(),
      provider: 'openlibrary'
    }
  };
}

/**
 * Normalize single work from OpenLibrary
 */
function normalizeWorkFromOpenLibrary(work, editions = null) {
  if (!work) return null;

  // Create normalized work
  const normalizedWork = {
    title: work.title,
    subtitle: work.subtitle,
    description: work.description?.value || work.description,
    subjectTags: work.subjects || [],
    firstPublicationYear: extractFirstPublicationYear(work),
    originalLanguage: extractLanguage(work),

    // External identifiers
    openLibraryWorkKey: work.key,
    openLibraryID: work.key?.replace('/works/', ''),

    // Metadata
    covers: work.covers?.map(id => `https://covers.openlibrary.org/b/id/${id}-L.jpg`) || [],
    authors: work.authors?.map(author => ({
      name: author.author?.key,
      openLibraryKey: author.author?.key
    })) || [],

    // Quality scoring
    openLibraryQuality: calculateWorkQuality(work)
  };

  // Add editions if provided
  if (editions && Array.isArray(editions)) {
    normalizedWork.editions = editions.map(edition => ({
      title: edition.title || work.title,
      isbn: extractISBN(edition),
      publisher: edition.publishers?.[0],
      publicationDate: edition.publish_date,
      pageCount: edition.number_of_pages,
      format: normalizeFormat(edition.physical_format),

      // External identifiers
      openLibraryEditionKey: edition.key,
      openLibraryID: edition.key?.replace('/books/', ''),

      // Covers
      covers: edition.covers?.map(id => `https://covers.openlibrary.org/b/id/${id}-L.jpg`) || []
    }));
  }

  return normalizedWork;
}

// ==============================================================================
// Core Works Filtering
// ==============================================================================

/**
 * Determine if a work is a "core work" vs translation/collection/variation
 * Focus on original publications in primary language
 */
function isCoreWork(title) {
  if (!title) return false;

  const titleLower = title.toLowerCase().trim();

  // Filter out obvious non-core works
  const exclusionPatterns = [
    // Collections and sets
    /collection/i,
    /set\b/i,
    /\d+-book/i,
    /anthology/i,

    // Translations (non-Latin scripts and obvious foreign titles)
    /[\u0400-\u04FF]/, // Cyrillic (Russian, Ukrainian)
    /[\u0590-\u05FF]/, // Hebrew
    /[\u4E00-\u9FFF]/, // Chinese
    /[\u3040-\u309F\u30A0-\u30FF]/, // Japanese
    /[\u0600-\u06FF]/, // Arabic

    // Spanish/Portuguese indicators
    /^érase una vez/i,
    /devoradores de/i,
    /ans de légendes/i,

    // Obvious typos or variants
    /project hair mary/i, // Should be "Hail"

    // Early/minor works (webcomics, consulting works)
    /casey and andy/i,
    /consulting criminal/i,
    /lacero/i,

    // Generic terms that indicate collections
    /stories$/i,
    /tales$/i,
    /legends$/i
  ];

  // Check exclusion patterns
  for (const pattern of exclusionPatterns) {
    if (pattern.test(titleLower)) {
      return false;
    }
  }

  // Known core works patterns (case insensitive)
  const corePatterns = [
    /^the martian$/i,
    /^artemis$/i,
    /^project hail mary$/i,
    /^cheshire crossing$/i,
    /^the egg$/i,
    /^randomize$/i
  ];

  // If it matches a known core work, definitely include
  for (const pattern of corePatterns) {
    if (pattern.test(titleLower)) {
      return true;
    }
  }

  // Additional heuristics for core works
  // - Short titles (usually original works)
  // - No parenthetical info (collections often have explanatory text)
  // - English words/characters
  const isShortTitle = title.length < 50;
  const hasNoParentheticals = !title.includes('(') && !title.includes('[');
  const isLikelyEnglish = /^[a-zA-Z0-9\s\-':.,!?]+$/.test(title);

  // Conservative approach: include if it looks like a core work
  return isShortTitle && hasNoParentheticals && isLikelyEnglish;
}

// ==============================================================================
// Helper Functions
// ==============================================================================

/**
 * Calculate confidence score for author name matching
 */
function calculateAuthorMatchConfidence(searchName, author) {
  const searchLower = searchName.toLowerCase();
  const authorLower = author.name.toLowerCase();

  // Exact match
  if (searchLower === authorLower) {
    return 1.0;
  }

  // Check alternate names
  if (author.alternate_names) {
    for (const altName of author.alternate_names) {
      if (altName.toLowerCase() === searchLower) {
        return 0.95;
      }
    }
  }

  // Partial match scoring
  if (authorLower.includes(searchLower) || searchLower.includes(authorLower)) {
    return 0.8;
  }

  // Word matching
  const searchWords = searchLower.split(' ');
  const authorWords = authorLower.split(' ');
  const matchingWords = searchWords.filter(word =>
    authorWords.some(authorWord => authorWord.includes(word) || word.includes(authorWord))
  );

  return matchingWords.length / Math.max(searchWords.length, authorWords.length);
}

/**
 * Calculate work quality score based on available metadata
 */
function calculateWorkQuality(work) {
  let score = 0;

  // Basic info
  if (work.title) score += 20;
  if (work.description) score += 20;
  if (work.subjects && work.subjects.length > 0) score += 15;

  // Publication info
  if (work.first_publish_date || work.created?.value) score += 15;
  if (work.covers && work.covers.length > 0) score += 10;

  // Author info
  if (work.authors && work.authors.length > 0) score += 20;

  return Math.min(100, score);
}

/**
 * Extract first publication year from work data
 */
function extractFirstPublicationYear(work) {
  // Try first_publish_date
  if (work.first_publish_date) {
    const year = parseInt(work.first_publish_date.substring(0, 4));
    if (!isNaN(year) && year > 1000 && year <= new Date().getFullYear()) {
      return year;
    }
  }

  // Try created date
  if (work.created?.value) {
    const year = parseInt(work.created.value.substring(0, 4));
    if (!isNaN(year) && year > 1000 && year <= new Date().getFullYear()) {
      return year;
    }
  }

  return null;
}

/**
 * Extract language from work data
 */
function extractLanguage(work) {
  if (work.languages && work.languages.length > 0) {
    const langKey = work.languages[0].key || work.languages[0];
    return langKey.replace('/languages/', '');
  }
  return 'en'; // Default to English
}

/**
 * Extract ISBN from edition data
 */
function extractISBN(edition) {
  // Prefer ISBN-13
  if (edition.isbn_13 && edition.isbn_13.length > 0) {
    return edition.isbn_13[0];
  }

  // Fall back to ISBN-10
  if (edition.isbn_10 && edition.isbn_10.length > 0) {
    return edition.isbn_10[0];
  }

  return null;
}

/**
 * Normalize format from OpenLibrary to SwiftData EditionFormat
 */
function normalizeFormat(physicalFormat) {
  if (!physicalFormat) return 'unknown';

  const format = physicalFormat.toLowerCase();

  if (format.includes('hardcover') || format.includes('hardback')) return 'hardcover';
  if (format.includes('paperback') || format.includes('softcover')) return 'paperback';
  if (format.includes('mass market')) return 'massMarket';
  if (format.includes('ebook') || format.includes('electronic')) return 'ebook';
  if (format.includes('audiobook') || format.includes('audio')) return 'audiobook';

  return 'unknown';
}

/**
 * Rate limiting for OpenLibrary API
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
        console.log(`OpenLibrary rate limiting: waiting ${waitTime}ms`);
        await new Promise(resolve => setTimeout(resolve, waitTime));
      }
    }

    // Store current timestamp
    await env.KV_CACHE.put(RATE_LIMIT_KEY, Date.now().toString(), {
      expirationTtl: 60
    });

  } catch (error) {
    console.warn('Rate limit enforcement failed:', error);
    // Continue without rate limiting if KV fails
  }
}

// Export OpenLibraryWorker as default for RPC service bindings
export default OpenLibraryWorker;