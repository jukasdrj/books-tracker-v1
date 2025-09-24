# BooksTracker V1.0 Data Models 📊

Clean Work/Edition architecture with proper normalization and user intent modeling.

## Core Entities

### Work 📖
**Represents the conceptual book** - the intellectual creation independent of specific publications.

```swift
class Work {
    var title: String
    var authors: [Author]          // ✅ Normalized relationship (not string)
    var originalLanguage: String?
    var firstPublicationYear: Int?
    var subjectTags: [String]

    // Relationships
    var editions: [Edition]        // One-to-many
    var userLibraryEntries: [UserLibraryEntry] // One-to-many
}
```

**Key Benefits:**
- Single search result per work (no duplicate "Huckleberry Finn" entries)
- Proper author normalization enables complex queries
- Cultural data derived from author relationships

### Edition 📚
**Represents a specific published version** of a work with physical/digital characteristics.

```swift
class Edition {
    var isbn: String?
    var publisher: String?
    var publicationDate: String?
    var pageCount: Int?
    var format: BookFormat        // .physical, .ebook, .audiobook
    var coverImageURL: String?
    var editionTitle: String?     // "Deluxe Edition", "Abridged"

    // Relationship
    var work: Work?               // Many-to-one
}
```

**Key Benefits:**
- Multiple editions per work (hardcover, paperback, ebook)
- ISBN-specific metadata for precise tracking
- Edition-specific features (page count, cover art)

### UserLibraryEntry 👤
**Represents user's relationship** to a Work/Edition with proper ownership semantics.

```swift
class UserLibraryEntry {
    var work: Work?               // Always present
    var edition: Edition?         // Nil for wishlist items
    var readingStatus: ReadingStatus
    var currentPage: Int
    var rating: Int?
    var notes: String?

    // Reading tracking
    var dateStarted: Date?
    var dateCompleted: Date?
}
```

**Status Logic (V1.0 Specification):**
- **Wishlist**: "Want to have/read but don't own" → `edition = nil`
- **To Read**: "Have it and want to read" → `edition != nil`
- **Reading**: Currently reading owned edition
- **Read**: Finished reading owned edition
- **On Hold**: Paused reading owned edition
- **DNF**: Did not finish owned edition

### Author 👨‍💼
**Normalized author entity** with cultural diversity tracking.

```swift
class Author {
    var name: String
    var nationality: String?
    var gender: AuthorGender
    var culturalRegion: CulturalRegion?
    var birthYear: Int?
    var deathYear: Int?

    // Relationship
    var works: [Work]             // Many-to-many
}
```

**Key Benefits:**
- No duplicate author data across works
- Enables "find all books by author" queries
- Cultural analytics across entire catalog

## Relationship Summary

```
Author ←→ Work → Edition
   ↑        ↓
   └── UserLibraryEntry
```

### Relationship Rules

1. **Author ←→ Work**: Many-to-many (co-authors, multiple works)
2. **Work → Edition**: One-to-many (multiple publications)
3. **Work → UserLibraryEntry**: One-to-many (multiple users, status changes)
4. **Edition → UserLibraryEntry**: Many-to-one (user owns specific edition)

### Wishlist vs Ownership Logic

```swift
// Wishlist: Want the work but don't own any edition
UserLibraryEntry(work: work, edition: nil, status: .wishlist)

// Owned: Have specific edition of the work
UserLibraryEntry(work: work, edition: edition, status: .toRead)

// Conversion: Acquire edition
wishlistEntry.acquireEdition(edition, status: .toRead)
```

## Query Examples

### Find all books by an author
```swift
let authorBooks = author.works // Direct relationship
```

### Check if user owns a work
```swift
let isOwned = work.isOwned // work.userEntry?.edition != nil
```

### Get user's wishlist
```swift
let wishlist = userEntries.filter { $0.readingStatus == .wishlist }
```

### Search results (no duplicates)
```swift
// Search returns Works, not individual editions
let results: [Work] = searchService.findWorks(title: "Huckleberry Finn")
// Returns single Work with multiple editions available
```

## Migration from Legacy

### Legacy Issues Fixed
- ❌ 720-line UserBook with embedded strings
- ❌ Duplicate search results for same work
- ❌ Complex JSON caching for SwiftData compatibility
- ❌ Mixed cultural data approaches

### V1.0 Benefits
- ✅ Clean 4-model architecture
- ✅ Proper database normalization
- ✅ CloudKit-optimized relationships
- ✅ Clear user intent modeling (wishlist vs owned)
- ✅ Scalable foundation for V2+ features

This architecture directly implements the V1.0 specification requirements for Work/Edition separation and proper user-book relationship tracking.