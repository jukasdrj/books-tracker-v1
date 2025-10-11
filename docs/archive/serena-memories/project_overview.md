# BooksTracker Project Overview

## Purpose
BooksTracker is a beautiful iOS application for tracking personal book libraries with cultural diversity insights. The app allows users to:
- Track books in their library (owned, wishlist, reading status)
- Monitor cultural diversity in reading habits
- Manage book editions and metadata
- Track reading progress and ratings

## Architecture
- **Workspace + SPM Structure**: Clean separation between app shell and feature code
- **App Shell**: `BooksTracker/` contains minimal app lifecycle code
- **Feature Code**: `BooksTrackerPackage/Sources/BooksTrackerFeature/` is where development happens
- **Business Logic**: Lives in SPM package, app target imports and displays it

## Core Data Models (SwiftData)
- **Work**: Creative work/book with title, authors, publication year
- **Edition**: Specific published editions (ISBN, publisher, format, page count)  
- **Author**: Author information with cultural diversity metadata
- **UserLibraryEntry**: User's relationship to a work (reading status, progress, ratings)

## Key Relationships
```
Work 1:many Edition
Work many:many Author  
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

## Cultural Diversity Features
- AuthorGender: female, male, nonBinary, other, unknown
- CulturalRegion: africa, asia, europe, northAmerica, etc.
- Marginalized voice detection for reading analytics