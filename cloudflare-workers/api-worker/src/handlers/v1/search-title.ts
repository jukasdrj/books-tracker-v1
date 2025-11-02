/**
 * GET /v1/search/title
 *
 * Search for books by title using canonical response format
 * Refactored to use shared enrichSingleBook() service (Task 2)
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { enrichSingleBook } from '../../services/enrichment.js';
import type { AuthorDTO } from '../../types/canonical.js';

export async function handleSearchTitle(
  query: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation
  if (!query || query.trim().length === 0) {
    return createErrorResponse(
      'Search query is required',
      'INVALID_QUERY',
      { query }
    );
  }

  try {
    console.log(`v1 title search for "${query}" (using enrichSingleBook)`);

    // Use shared enrichment service (DRY - multi-provider fallback included)
    const result = await enrichSingleBook({ title: query }, env);

    if (!result) {
      // Book not found in any provider
      return createSuccessResponse(
        { works: [], authors: [] },
        {
          processingTime: Date.now() - startTime,
          provider: 'none',
          cached: false,
        }
      );
    }

    // enrichSingleBook returns a single WorkDTO with embedded authors
    // Extract authors from the work for the canonical response format
    const authors: AuthorDTO[] = result.authors || [];

    return createSuccessResponse(
      { works: [result], authors },
      {
        processingTime: Date.now() - startTime,
        provider: result.primaryProvider || 'google-books',
        cached: false,
      }
    );
  } catch (error: any) {
    console.error('Error in v1 title search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
