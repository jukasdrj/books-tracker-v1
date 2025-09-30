/**
 * Data Transformation Utilities
 *
 * Shared transformation functions for normalizing data across different providers
 * into the Google Books API format for iOS app compatibility.
 */

/**
 * Transform a Work object to Google Books API format for iOS app compatibility
 */
export function transformWorkToGoogleFormat(work) {
    const primaryEdition = work.editions && work.editions.length > 0 ? work.editions[0] : null;

    // Handle different author formats from different providers
    let authors = [];
    if (work.authors) {
        if (Array.isArray(work.authors)) {
            authors = work.authors.map(a => {
                if (typeof a === 'string') return a;
                if (a && a.name) return a.name;
                return String(a);
            });
        } else if (typeof work.authors === 'string') {
            authors = [work.authors];
        }
    }

    // If no authors in work, try to get from edition or use a fallback
    if (authors.length === 0 && primaryEdition?.authors) {
        authors = Array.isArray(primaryEdition.authors)
            ? primaryEdition.authors.map(a => typeof a === 'string' ? a : a.name || String(a))
            : [String(primaryEdition.authors)];
    }

    // Collect external IDs from both work and edition level
    const workExternalIds = work.externalIds || {};
    const editionExternalIds = primaryEdition?.externalIds || {};

    // Prepare industry identifiers including ISBNs and enhanced external IDs
    const industryIdentifiers = [];

    // Add ISBNs
    if (primaryEdition?.isbn13) {
        industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn13 });
    }
    if (primaryEdition?.isbn10) {
        industryIdentifiers.push({ type: "ISBN_10", identifier: primaryEdition.isbn10 });
    }
    // Fallback for legacy isbn field
    if (primaryEdition?.isbn && !primaryEdition?.isbn13 && !primaryEdition?.isbn10) {
        industryIdentifiers.push({ type: "ISBN_13", identifier: primaryEdition.isbn });
    }

    // Enhanced Google Books format with cross-reference IDs
    const volumeInfo = {
        title: work.title,
        subtitle: work.subtitle || "",
        authors: authors,
        publisher: primaryEdition?.publisher || "",
        publishedDate: work.firstPublicationYear ? work.firstPublicationYear.toString() : (primaryEdition?.publicationDate || primaryEdition?.publishedDate || ""),
        description: work.description || primaryEdition?.description || "",
        industryIdentifiers: industryIdentifiers,
        pageCount: primaryEdition?.pageCount || 0,
        categories: work.subjects || work.categories || [],
        imageLinks: primaryEdition?.coverImageURL ? {
            thumbnail: primaryEdition.coverImageURL,
            smallThumbnail: primaryEdition.coverImageURL
        } : undefined,

        // Enhanced cross-reference identifiers for future provider integration
        crossReferenceIds: {
            // OpenLibrary IDs
            openLibraryWorkId: workExternalIds.openLibraryWorkId || work.openLibraryWorkKey,
            openLibraryEditionId: editionExternalIds.openLibraryEditionId || workExternalIds.openLibraryEditionId,

            // Commercial platform IDs
            goodreadsWorkIds: [...(workExternalIds.goodreadsWorkIds || []), ...(editionExternalIds.goodreadsWorkIds || [])],
            amazonASINs: [...(workExternalIds.amazonASINs || []), ...(editionExternalIds.amazonASINs || [])],
            googleBooksVolumeIds: [...(workExternalIds.googleBooksVolumeIds || []), ...(editionExternalIds.googleBooksVolumeIds || [])],

            // Future provider IDs
            librarythingIds: [...(workExternalIds.librarythingIds || []), ...(editionExternalIds.librarythingIds || [])],
            isbndbIds: [...(workExternalIds.isbndbIds || []), ...(editionExternalIds.isbndbIds || [])]
        }
    };

    // Determine best ID for the volume
    const volumeId = work.id ||
                    workExternalIds.googleBooksVolumeIds?.[0] ||
                    workExternalIds.openLibraryWorkId ||
                    work.openLibraryWorkKey ||
                    work.googleBooksVolumeID ||
                    `synthetic-${work.title.replace(/\s+/g, '-').toLowerCase()}`;

    return {
        kind: "books#volume",
        id: volumeId,
        volumeInfo: volumeInfo
    };
}

/**
 * Filter Google Books API items to remove collections and non-primary works
 */
export function filterGoogleBooksItems(items, searchQuery = '') {
    if (!items || !Array.isArray(items)) return [];

    // Extract potential author name from search query for validation
    const queryLower = searchQuery.toLowerCase();
    const isAuthorSearch = queryLower.includes(' ') && !queryLower.includes('the ') && !queryLower.includes('a ');
    const potentialAuthor = isAuthorSearch ? queryLower : null;

    const excludePatterns = [
        // Collections and box sets - more aggressive
        /collection/i,
        /set\b/i,
        /boxed/i,
        /box set/i,
        /\d+-book/i,
        /bundle/i,
        /\bbinge\b/i,                    // "Binge Reads"
        /compilation/i,
        /omnibus/i,

        // Study materials and guides - enhanced
        /study guide/i,
        /conversation starter/i,
        /conversation starters/i,        // Plural form
        /summary/i,
        /analysis/i,
        /cliff.*notes/i,
        /sparknotes/i,
        /discussion/i,
        /questions/i,
        /workbook/i,
        /study.*notes/i,

        // Meta books about the author/work
        /about\s+\w+/i,
        /guide to/i,
        /understanding/i,
        /introduction to/i,
        /companion/i,

        // Publisher-specific exclusions for study materials
        /by.*daily.*books/i,
        /\|.*conversation/i,            // "Title | Conversation Starters"
        /\|.*summary/i,                 // "Title | Summary"
        /\|.*study/i,                   // "Title | Study Guide"
    ];

    return items.filter(item => {
        const volumeInfo = item.volumeInfo || {};
        const title = volumeInfo.title || '';
        const subtitle = volumeInfo.subtitle || '';
        const fullTitle = `${title} ${subtitle}`.toLowerCase();

        // Exclude if matches any exclude pattern
        for (const pattern of excludePatterns) {
            if (pattern.test(fullTitle)) {
                return false;
            }
        }

        // Prefer books with actual content (page count > 10)
        const pageCount = volumeInfo.pageCount || 0;
        if (pageCount > 0 && pageCount < 10) {
            return false;
        }

        // Author validation for author searches
        if (potentialAuthor && volumeInfo.authors) {
            const authors = volumeInfo.authors || [];
            const authorsText = authors.join(' ').toLowerCase();

            // Check if any of the search terms appear in the author names
            const searchTerms = potentialAuthor.split(' ').filter(term => term.length > 2);
            const hasMatchingAuthor = searchTerms.some(term => authorsText.includes(term));

            // If this appears to be an author search but no author matches, filter out
            // Exception: keep obvious study materials that might be legitimately about the author
            if (!hasMatchingAuthor && !fullTitle.includes('about') && !fullTitle.includes('guide')) {
                return false;
            }
        }

        return true;
    });
}

/**
 * Deduplicate Google Books items by title and author
 */
export function deduplicateGoogleBooksItems(items) {
    if (!items || items.length <= 1) return items;

    const dedupedItems = [];
    const seenKeys = new Set();

    for (const item of items) {
        const volumeInfo = item.volumeInfo || {};
        const title = (volumeInfo.title || '').toLowerCase()
            .replace(/[^\w\s]/g, '') // Remove punctuation
            .replace(/\s+/g, ' ')     // Normalize whitespace
            .trim();

        const authors = (volumeInfo.authors || [])
            .map(a => a.toLowerCase())
            .join(',');

        const normalizedKey = `${authors}:${title}`;

        // Check for near-duplicates (85% similarity for Google Books items)
        let isDuplicate = false;
        for (const existingKey of seenKeys) {
            if (calculateSimilarity(normalizedKey, existingKey) > 0.85) {
                isDuplicate = true;
                break;
            }
        }

        if (!isDuplicate) {
            seenKeys.add(normalizedKey);
            dedupedItems.push(item);
        }
    }

    return dedupedItems;
}

/**
 * Calculate string similarity using Jaccard coefficient
 */
function calculateSimilarity(str1, str2) {
    const set1 = new Set(str1.toLowerCase().split(/\s+/));
    const set2 = new Set(str2.toLowerCase().split(/\s+/));

    const intersection = new Set([...set1].filter(x => set2.has(x)));
    const union = new Set([...set1, ...set2]);

    return intersection.size / union.size;
}

/**
 * Filter out collections, study guides, conversation starters, and special editions
 * to focus on primary works by the author
 */
export function filterPrimaryWorks(works) {
    if (!works || !Array.isArray(works)) return [];

    const excludePatterns = [
        // Collections and box sets - more aggressive
        /collection/i,
        /set\b/i,
        /series\b/i,
        /boxed/i,
        /box set/i,
        /\d+-book/i,
        /bundle/i,
        /\bbinge\b/i,                    // "Binge Reads"
        /compilation/i,
        /omnibus/i,

        // Study materials - enhanced
        /study guide/i,
        /conversation starter/i,
        /conversation starters/i,        // Plural form
        /summary/i,
        /analysis/i,
        /cliff.*notes/i,
        /sparknotes/i,
        /discussion/i,
        /questions/i,
        /study.*notes/i,

        // Special editions and formats (but not primary graphic novels)
        /annotated/i,
        /illustrated/i,
        /companion/i,
        /workbook/i,
        /journal/i,
        /diary/i,

        // Exclude graphic novels only if they're supplementary (not primary works)
        /graphic novel.*guide/i,
        /graphic novel.*companion/i,

        // Meta books about the author/work
        /about\s+\w+/i,
        /guide to/i,
        /understanding/i,
        /introduction to/i,

        // Publisher-specific exclusions for study materials
        /by.*daily.*books/i,
        /\|.*conversation/i,            // "Title | Conversation Starters"
        /\|.*summary/i,                 // "Title | Summary"
        /\|.*study/i,                   // "Title | Study Guide"
    ];

    const includeIfContains = [
        // These patterns indicate it's likely a primary work
        /novel/i,
        /book/i,
        /story/i,
        /tales/i,
    ];

    return works.filter(work => {
        const title = work.title || '';
        const subtitle = work.subtitle || '';
        const fullTitle = `${title} ${subtitle}`.toLowerCase();

        // Exclude if matches any exclude pattern
        for (const pattern of excludePatterns) {
            if (pattern.test(fullTitle)) {
                return false;
            }
        }

        // If it's a very short title (likely primary work), include it
        if (title.length <= 50) {
            return true;
        }

        // For longer titles, check if they contain positive indicators
        return includeIfContains.some(pattern => pattern.test(fullTitle));
    });
}
