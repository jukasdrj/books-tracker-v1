# Enhanced Cache Architecture (Option 1)
## SwiftData-Aligned Work/Edition Normalization

### Current Problem
The cache system treats editions as separate works, breaking the SwiftData normalization where:
- **Work**: Abstract creative work (1 novel = 1 work)
- **Edition**: Specific published versions (1 work = many editions)
- **Author**: Creators with external API identifiers

### Enhanced Cache Structure Design

#### 1. Work-Centric Cache Keys
```javascript
// PRIMARY CACHE STRUCTURE
// Key: work:{workIdentifier}
// Value: NormalizedWork object

const workCacheKey = `work:${workIdentifier}`; // e.g., "work:OL43063908W" or "work:the-martian-andy-weir"

const NormalizedWork = {
  // Core Work Data
  title: "The Martian",
  originalLanguage: "en",
  firstPublicationYear: 2011,

  // External API Identifiers (SwiftData Work model)
  identifiers: {
    openLibraryID: "OL43063908W",     // OpenLibrary work ID
    isbndbID: "book_12345",           // ISBNdb work/book ID
    googleBooksVolumeID: "beSP5CCpiGUC", // Google Books volume ID
    goodreadsID: null                 // Future integration
  },

  // Authors with full identifier mapping
  authors: [
    {
      name: "Andy Weir",
      identifiers: {
        openLibraryID: "OL7234434A",   // OpenLibrary author ID
        isbndbID: "author_67890",      // ISBNdb author ID
        googleBooksID: "google_author_123", // Google Books author ID
        goodreadsID: null              // Future integration
      },
      gender: "male",
      culturalRegion: "northAmerica",
      nationality: "American"
    }
  ],

  // Editions grouped under this work
  editions: [
    {
      // Edition-specific data
      isbn: "9780553418026",
      isbns: ["9780553418026", "0553418025"],
      publisher: "Broadway Books",
      publicationDate: "2014-02-11",
      format: "paperback",
      pageCount: 369,
      coverImageURL: "https://covers.isbndb.com/covers/42/02/9780553418026.jpg",

      // External API Identifiers (SwiftData Edition model)
      identifiers: {
        openLibraryID: "OL26321457M",    // OpenLibrary edition ID (M = manifest)
        isbndbID: "edition_12345",       // ISBNdb edition ID
        googleBooksVolumeID: "beSP5CCpiGUC", // Same as work for Google Books
        goodreadsID: null                // Future integration
      },

      // ISBNdb-specific metadata
      isbndb_metadata: {
        lastSync: "2024-09-25T10:30:00Z",
        quality: 95,
        source: "isbndb"
      }
    }
    // Additional editions for same work...
  ],

  // Cache metadata
  cache_metadata: {
    created: "2024-09-25T10:30:00Z",
    lastUpdated: "2024-09-25T10:30:00Z",
    sources: ["isbndb", "openlibrary"],  // Which APIs provided data
    quality: 95,                         // Overall data quality score
    promotedToKV: true                   // Whether in hot cache (KV)
  }
}
```

#### 2. Author-Centric Cache Keys
```javascript
// AUTHOR CACHE STRUCTURE
// Key: author:{authorIdentifier}
// Value: NormalizedAuthor object

const authorCacheKey = `author:${authorIdentifier}`; // e.g., "author:OL7234434A" or "author:andy-weir"

const NormalizedAuthor = {
  // Core Author Data
  name: "Andy Weir",
  nationality: "American",
  gender: "male",
  culturalRegion: "northAmerica",
  birthYear: 1972,

  // External API Identifiers (SwiftData Author model)
  identifiers: {
    openLibraryID: "OL7234434A",      // OpenLibrary author ID
    isbndbID: "author_67890",         // ISBNdb author ID
    googleBooksID: "google_author_123", // Google Books author ID
    goodreadsID: null                 // Future integration
  },

  // Works by this author (references to work cache keys)
  works: [
    {
      workIdentifier: "OL43063908W",   // References work cache
      title: "The Martian",
      role: "author",                  // author, co-author, editor, etc.
      firstPublicationYear: 2011
    },
    {
      workIdentifier: "OL43063909W",
      title: "Artemis",
      role: "author",
      firstPublicationYear: 2017
    }
  ],

  // Cache metadata
  cache_metadata: {
    created: "2024-09-25T10:30:00Z",
    lastUpdated: "2024-09-25T10:30:00Z",
    sources: ["isbndb"],
    quality: 90,
    promotedToKV: false
  }
}
```

#### 3. Search Index Cache Keys
```javascript
// SEARCH INDEX STRUCTURE
// Key: search:{searchType}:{normalizedQuery}
// Value: Array of work/author references

const searchCacheKey = `search:author:andy-weir`;
const searchResults = {
  query: "andy weir",
  results: [
    {
      type: "author",
      identifier: "OL7234434A",
      name: "Andy Weir",
      relevanceScore: 1.0,
      cacheKey: "author:OL7234434A"
    }
  ],

  // Related works by this author
  related_works: [
    {
      type: "work",
      identifier: "OL43063908W",
      title: "The Martian",
      relevanceScore: 0.95,
      cacheKey: "work:OL43063908W"
    }
  ],

  cache_metadata: {
    created: "2024-09-25T10:30:00Z",
    ttl: 3600  // Search results have shorter TTL
  }
}
```

### 4. API Identifier Mapping Strategy

#### OpenLibrary Integration
```javascript
// OpenLibrary provides proper Work/Author separation
const openLibraryWorkID = "OL43063908W";    // Work-level ID
const openLibraryAuthorID = "OL7234434A";   // Author-level ID
const openLibraryEditionID = "OL26321457M"; // Edition-level ID (M = manifest)
```

#### ISBNdb Integration
```javascript
// ISBNdb doesn't distinguish Work vs Edition - we normalize
const isbndbBookResponse = {
  book: {
    id: "book_12345",           // Maps to Work.isbndbID
    isbn13: "9780553418026",    // Maps to Edition.isbn
    // We create Work/Edition separation in our cache
  }
}
```

#### Google Books Integration
```javascript
// Google Books uses same volume ID for Work and Edition
const googleBooksVolumeID = "beSP5CCpiGUC"; // Maps to both Work.googleBooksVolumeID and Edition.googleBooksVolumeID
```

### 5. Cache Consolidation Logic

#### Work Deduplication
```javascript
function findOrCreateWork(bookData) {
  // Priority order for work identification:
  // 1. OpenLibrary work ID (most reliable for Work/Edition distinction)
  // 2. ISBNdb book ID (treat as work-level)
  // 3. Title + primary author combination

  const workIdentifier = bookData.openLibraryWorkID ||
                         bookData.isbndbID ||
                         generateWorkKey(bookData.title, bookData.primaryAuthor);

  return workIdentifier;
}
```

#### Edition Consolidation
```javascript
function addEditionToWork(workIdentifier, editionData) {
  // Each ISBN creates a new edition under the work
  // Editions are consolidated by ISBN, publisher, publication date

  const work = cache.get(`work:${workIdentifier}`);
  const existingEdition = work.editions.find(e =>
    e.isbn === editionData.isbn ||
    e.isbns.some(isbn => editionData.isbns.includes(isbn))
  );

  if (!existingEdition) {
    work.editions.push(normalizeEdition(editionData));
  } else {
    mergeEditionData(existingEdition, editionData);
  }
}
```

### 6. Integration with Current Cache System

#### Backward Compatibility Keys
```javascript
// Maintain existing search patterns for API proxy
const legacyAuthorKey = `author:andy-weir`;  // Current format
const enhancedAuthorKey = `author:OL7234434A`; // New format with OpenLibrary ID

// Store both formats during transition:
await cache.put(legacyAuthorKey, authorData);   // For existing API
await cache.put(enhancedAuthorKey, authorData); // For future queries
```

#### Response Format Enhancement
```javascript
// books-api-proxy response format
const enhancedResponse = {
  works: [
    {
      // Work-level data
      title: "The Martian",
      identifiers: { /* all external API IDs */ },
      authors: [{ /* author with identifiers */ }],

      // Available editions
      editions: [
        {
          isbn: "9780553418026",
          publisher: "Broadway Books",
          identifiers: { /* edition identifiers */ }
        }
      ]
    }
  ],

  // Response metadata
  response_metadata: {
    sources: ["isbndb"],
    query: "andy weir",
    cached: true,
    cache_age: 1800
  }
}
```

### 7. Implementation Benefits

#### For SwiftData Integration
- **Perfect Model Mapping**: Cache structure exactly matches SwiftData Work/Edition/Author models
- **External ID Capture**: All `openLibraryID`, `isbndbID`, `googleBooksVolumeID` fields populated
- **Deduplication Ready**: External IDs enable proper Work consolidation
- **Cultural Metadata**: Author cultural/gender data preserved for diversity tracking

#### For Cache Efficiency
- **Work-Centric Storage**: Eliminates edition duplication (multiple ISBNs = 1 work, many editions)
- **Intelligent Promotion**: Popular works auto-promote to KV based on edition access patterns
- **Source Tracking**: Each cache entry tracks which APIs provided data
- **Quality Scoring**: Data quality metrics guide cache promotion decisions

#### For API Performance
- **Single Work Lookup**: One cache hit returns work + all editions + author data
- **Search Optimization**: Search index cache enables fast author/title lookups
- **Fallback Logic**: Multiple identifier types enable robust fallback chains
- **Progressive Enhancement**: New API integrations add identifiers without breaking existing data

This enhanced cache architecture transforms the current edition-focused system into a properly normalized, SwiftData-aligned, multi-API identifier system that maximizes ISBNdb utilization while preparing for future API integrations.