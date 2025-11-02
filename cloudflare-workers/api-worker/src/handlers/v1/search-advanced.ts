/**
 * GET /v1/search/advanced
 *
 * Advanced search for books by title and/or author using canonical response format
 * Refactored to use shared enrichSingleBook() service (Task 2)
 */

import type { ApiResponse, BookSearchResponse } from '../../types/responses.js';
import { createSuccessResponse, createErrorResponse } from '../../types/responses.js';
import { enrichSingleBook } from '../../services/enrichment.js';
import type { AuthorDTO } from '../../types/canonical.js';

export async function handleSearchAdvanced(
  title: string,
  author: string,
  env: any
): Promise<ApiResponse<BookSearchResponse>> {
  const startTime = Date.now();

  // Validation - require at least one parameter
  const hasTitle = title && title.trim().length > 0;
  const hasAuthor = author && author.trim().length > 0;

  if (!hasTitle && !hasAuthor) {
    return createErrorResponse(
      'At least one of title or author is required',
      'INVALID_QUERY',
      { title, author }
    );
  }

  try {
    console.log(`v1 advanced search - title: "${title}", author: "${author}" (using enrichSingleBook)`);

    // Use shared enrichment service (DRY - multi-provider fallback included)
    const result = await enrichSingleBook(
      {
        title: hasTitle ? title : undefined,
        author: hasAuthor ? author : undefined
      },
      env
    );

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
    console.error('Error in v1 advanced search:', error);
    return createErrorResponse(
      error.message || 'Internal server error',
      'INTERNAL_ERROR',
      { error: error.toString() },
      { processingTime: Date.now() - startTime }
    );
  }
}
