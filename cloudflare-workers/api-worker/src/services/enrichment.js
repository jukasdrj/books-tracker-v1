/**
 * Book enrichment service
 *
 * Contains TWO enrichment systems:
 * 1. NEW: enrichSingleBook() - DRY service for individual book enrichment
 *    - Multi-provider fallback (Google Books → OpenLibrary)
 *    - Used by: /api/enrichment/start (via batch handler), /v1/search/* (future)
 *
 * 2. OLD: enrichBatch() - Legacy batch enrichment (deprecated, preserved for /api/enrichment/start)
 *    - Will be replaced by batch-enrichment.js calling enrichSingleBook()
 *    - Scheduled for removal in Task 2
 */

import * as externalApis from './external-apis.js';

/**
 * Enrich multiple books with metadata from external providers
 * Used by search endpoints that need multiple results
 *
 * @param {Object} query - Book search query
 * @param {string} [query.title] - Book title (optional)
 * @param {string} [query.author] - Author name (optional)
 * @param {string} [query.isbn] - ISBN (optional, returns single result)
 * @param {Object} env - Worker environment bindings
 * @param {Object} options - Search options
 * @param {number} [options.maxResults=20] - Maximum results to return
 * @returns {Promise<Object[]>} Array of WorkDTOs with provenance fields
 */
export async function enrichMultipleBooks(query, env, options = { maxResults: 20 }) {
  const { title, author, isbn } = query;
  const { maxResults = 20 } = options;

  // ISBN search returns single result (ISBNs are unique)
  if (isbn) {
    const result = await enrichSingleBook({ isbn }, env);
    return result ? [result] : [];
  }

  // Build search query for Google Books
  let searchQuery = '';
  if (title) searchQuery += `${title}`;
  if (author) searchQuery += (searchQuery ? ' ' : '') + author;

  if (!searchQuery) {
    console.warn('enrichMultipleBooks: No search parameters provided');
    return [];
  }

  try {
    // Try Google Books first with maxResults
    console.log(`enrichMultipleBooks: Searching Google Books for "${searchQuery}" (maxResults: ${maxResults})`);
    const googleResult = await externalApis.searchGoogleBooks(searchQuery, { maxResults }, env);

    if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
      // Add provenance fields to all works
      return googleResult.works.map(work => addProvenanceFields(work, 'google-books'));
    }

    // Fallback to OpenLibrary
    console.log(`enrichMultipleBooks: Google Books returned no results, trying OpenLibrary`);
    const olResult = await externalApis.searchOpenLibrary(searchQuery, { maxResults }, env);

    if (olResult.success && olResult.works && olResult.works.length > 0) {
      // Add provenance fields to all works
      return olResult.works.map(work => addProvenanceFields(work, 'openlibrary'));
    }

    // No results from any provider
    console.log(`enrichMultipleBooks: No results for "${searchQuery}"`);
    return [];

  } catch (error) {
    console.error('enrichMultipleBooks error:', error);
    // Best-effort: API errors = empty results (don't propagate errors)
    return [];
  }
}

/**
 * Enrich a single book with metadata from external providers
 * Used by enrichment pipeline that needs best match for a specific book
 *
 * @param {Object} query - Book search query
 * @param {string} [query.title] - Book title (optional)
 * @param {string} [query.author] - Author name (optional)
 * @param {string} [query.isbn] - ISBN (optional, highest accuracy)
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object|null>} WorkDTO with editions and authors, or null if not found
 */
export async function enrichSingleBook(query, env) {
  const { title, author, isbn } = query;

  // Require at least one search parameter
  if (!title && !isbn && !author) {
    console.warn('enrichSingleBook: No search parameters provided');
    return null;
  }

  try {
    // Strategy 1: If ISBN provided, use ISBN search (most accurate)
    if (isbn) {
      const result = await searchByISBN(isbn, env);
      if (result) return result;
    }

    // Strategy 2: Try Google Books with title+author
    const googleResult = await searchGoogleBooks(query, env);
    if (googleResult) {
      return googleResult;
    }

    // Strategy 3: Fallback to OpenLibrary
    const openLibResult = await searchOpenLibrary(query, env);
    if (openLibResult) {
      return openLibResult;
    }

    // Book not found in any provider
    console.log(`enrichSingleBook: No results for "${title}" by "${author || 'unknown'}"`);
    return null;

  } catch (error) {
    console.error('enrichSingleBook error:', error);
    // Best-effort: API errors = not found (don't propagate errors)
    return null;
  }
}

/**
 * Search Google Books API with query
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param {Object} query - Search parameters
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object|null>} First work result or null
 */
async function searchGoogleBooks(query, env) {
  const { title, author, isbn } = query;

  // Build search query (title + author for better precision)
  const searchQuery = isbn
    ? isbn // ISBN takes precedence
    : [title, author].filter(Boolean).join(' ');

  const result = isbn
    ? await externalApis.searchGoogleBooksByISBN(searchQuery, env)
    : await externalApis.searchGoogleBooks(searchQuery, { maxResults: 1 }, env);

  if (!result.success || !result.works || result.works.length === 0) {
    return null;
  }

  // Return first work with provenance fields added
  const work = result.works[0];
  return addProvenanceFields(work, 'google-books');
}

/**
 * Search OpenLibrary API with query
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param {Object} query - Search parameters
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object|null>} First work result or null
 */
async function searchOpenLibrary(query, env) {
  const { title, author } = query;

  const searchQuery = [title, author].filter(Boolean).join(' ');
  const result = await externalApis.searchOpenLibrary(searchQuery, { maxResults: 1 }, env);

  if (!result.success || !result.works || result.works.length === 0) {
    return null;
  }

  // Return first work with provenance fields added
  const work = result.works[0];
  return addProvenanceFields(work, 'openlibrary');
}

/**
 * ISBN-specific search (tries Google Books, then OpenLibrary)
 * Thin wrapper around external-apis.js - just adds provenance fields
 *
 * @param {string} isbn - ISBN-10 or ISBN-13
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object|null>} Work result or null
 */
async function searchByISBN(isbn, env) {
  // Try Google Books ISBN search first
  const googleResult = await externalApis.searchGoogleBooksByISBN(isbn, env);

  if (googleResult.success && googleResult.works && googleResult.works.length > 0) {
    const work = googleResult.works[0];
    return addProvenanceFields(work, 'google-books');
  }

  // Fallback to OpenLibrary ISBN search
  const olResult = await externalApis.searchOpenLibrary(isbn, { maxResults: 1, isbn }, env);

  if (olResult.success && olResult.works && olResult.works.length > 0) {
    const work = olResult.works[0];
    return addProvenanceFields(work, 'openlibrary');
  }

  return null;
}

/**
 * Add provenance fields to work already normalized by external-apis.js
 *
 * The external-apis.js already returns fully normalized works.
 * We just add provenance tracking fields:
 * - primaryProvider - Which API contributed the data
 * - contributors - Array of all providers (single provider for direct calls)
 * - synthetic - Flag for inferred works (false for direct API results)
 *
 * @param {Object} work - Normalized work from external-apis.js
 * @param {string} provider - Provider name ('google-books', 'openlibrary')
 * @returns {Object} WorkDTO with provenance fields
 */
function addProvenanceFields(work, provider) {
  return {
    ...work, // Preserve all existing normalized fields
    primaryProvider: provider,
    contributors: [provider],
    synthetic: false // Direct API result, not inferred
  };
}

// ============================================================================
// LEGACY CODE - Preserved for backward compatibility with /api/enrichment/start
// Will be removed in Task 2 when batch-enrichment.js is refactored
// ============================================================================

/**
 * Enrich batch of works with progress updates via WebSocket
 * LEGACY FUNCTION - Preserved for /api/enrichment/start endpoint
 *
 * @param {string} jobId - Job identifier for tracking
 * @param {string[]} workIds - Array of work IDs to enrich (ISBN or title+author)
 * @param {Object} env - Worker environment bindings
 * @param {Object} doStub - ProgressWebSocketDO stub for direct progress updates
 * @returns {Promise<Object>} Enrichment result
 */
export async function enrichBatch(jobId, workIds, env, doStub) {
  const totalCount = workIds.length;
  let processedCount = 0;
  const enrichedWorks = [];
  const errors = [];

  try {
    // Initial progress update
    await doStub.pushProgress({
      progress: 0,
      processedItems: 0,
      totalItems: totalCount,
      currentStatus: `Starting enrichment for ${totalCount} books...`,
      jobId
    });

    // Process each work
    for (const workId of workIds) {
      // Cancellation check
      let canceled = false;
      try {
        canceled = await doStub.isCanceled();
      } catch (e) {
        console.warn(`[${jobId}] Stopping batch, DO stub threw: ${e.message}`);
        canceled = true;
      }

      if (canceled) {
        console.log(`[${jobId}] Cancellation detected. Stopping enrichment batch.`);
        await doStub.pushProgress({
          progress: processedCount / totalCount,
          processedItems: processedCount,
          totalItems: totalCount,
          currentStatus: 'Enrichment canceled by user',
          jobId,
          result: {
            success: false,
            canceled: true,
            processedCount: processedCount,
            totalCount: totalCount,
            enrichedCount: enrichedWorks.length,
            errorCount: errors.length
          }
        }).catch(() => {
          console.log(`[${jobId}] Could not send cancel status (socket closed)`);
        });
        break;
      }

      try {
        // Enrich single work using internal function call
        const result = await enrichWorkWithAPIs(workId, env);
        enrichedWorks.push(result);

        processedCount++;
        const progress = processedCount / totalCount;

        await doStub.pushProgress({
          progress: progress,
          processedItems: processedCount,
          totalItems: totalCount,
          currentStatus: `Enriched ${processedCount}/${totalCount} books`,
          currentWorkId: workId,
          jobId
        });

      } catch (error) {
        console.error(`Enrichment failed for ${workId}:`, error);
        errors.push({
          workId,
          error: error.message
        });

        processedCount++;
      }

      // Yield to event loop
      await new Promise(resolve => setTimeout(resolve, 0));
    }

    // Final success update
    await doStub.pushProgress({
      progress: 1.0,
      processedItems: processedCount,
      totalItems: totalCount,
      currentStatus: 'Enrichment complete',
      jobId,
      result: {
        success: true,
        processedCount: processedCount,
        totalCount: totalCount,
        enrichedCount: enrichedWorks.length,
        errorCount: errors.length,
        works: enrichedWorks.map(item => item.work).filter(Boolean),
        editions: enrichedWorks.flatMap(item => item.editions || []),
        authors: enrichedWorks.flatMap(item => item.authors || []),
        errors: errors
      }
    });

    return {
      success: true,
      processedCount: processedCount,
      totalCount: totalCount,
      works: enrichedWorks.map(item => item.work).filter(Boolean),
      editions: enrichedWorks.flatMap(item => item.editions || []),
      authors: enrichedWorks.flatMap(item => item.authors || []),
      errors: errors
    };

  } catch (error) {
    console.error('Enrichment batch failed:', error);

    await doStub.pushProgress({
      progress: processedCount / totalCount,
      error: error.message,
      currentStatus: 'Enrichment failed',
      jobId
    });

    throw error;

  } finally {
    await doStub.closeConnection(1000, "Job complete");
  }
}

/**
 * Internal: Enrich single work using external APIs
 * LEGACY HELPER - Used by enrichBatch()
 *
 * Note: This uses the old enrichment format for backward compatibility.
 * New code should use enrichSingleBook() instead.
 */
async function enrichWorkWithAPIs(workId, env) {
  try {
    const isISBN = /^(97[89])?\d{9}[\dX]$/i.test(workId);

    let result;
    if (isISBN) {
      result = await externalApis.searchGoogleBooksByISBN(workId, env);

      if (!result.success || !result.works || result.works.length === 0) {
        console.log(`Google Books returned no results for ISBN ${workId}, trying alternatives...`);
        return {
          workId,
          enriched: false,
          error: 'No results found',
          timestamp: new Date().toISOString()
        };
      }
    } else {
      result = await externalApis.searchGoogleBooks(workId, { maxResults: 5 }, env);

      if (!result.success || !result.works || result.works.length === 0) {
        return {
          workId,
          enriched: false,
          error: 'No results found',
          timestamp: new Date().toISOString()
        };
      }
    }

    // external-apis.js returns { success: true, works: [...], authors: [...] }
    const work = result.works[0];
    const editions = work.editions || [];
    const authors = result.authors || [];

    return {
      workId,
      enriched: true,
      work: work,
      editions: editions,
      authors: authors,
      isISBN,
      timestamp: new Date().toISOString()
    };

  } catch (error) {
    console.error(`enrichWorkWithAPIs failed for ${workId}:`, error);

    return {
      workId,
      enriched: false,
      error: error.message,
      timestamp: new Date().toISOString()
    };
  }
}

