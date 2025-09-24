# BooksTracker V1.0 📚

A clean, modern iOS book tracking app built with SwiftUI, SwiftData, and CloudKit.

## Architecture

**Work/Edition Separation**: Clean data model that separates conceptual books (Works) from specific published versions (Editions).

- **Work**: The conceptual book ("The Adventures of Huckleberry Finn")
- **Edition**: Specific published version (ISBN, publisher, page count)
- **UserLibraryEntry**: User's relationship to a Work/Edition (status, rating, notes)

## Features

### V1.0 Core Features
- 🔍 **Smart Search**: Single clean results per work, no duplicates
- 📱 **Barcode Scanning**: Quick ISBN scanning and lookup
- 📚 **Library Management**: Track reading status and personal ratings
- 📊 **Reading Analytics**: Author demographics, genre distribution
- 📝 **CSV Import**: Goodreads library import support
- ☁️ **CloudKit Sync**: Seamless device synchronization

### Technical Stack
- **iOS 26+** SwiftUI with modern lifecycle
- **SwiftData + CloudKit** for persistence and sync
- **Swift 6.0** with strict concurrency checking
- **CloudFlare Workers** for search proxy and caching
- **Work/Edition Data Model** for clean search results

## Project Structure

```
BooksTracker/
├── Models/              # Clean SwiftData models
│   ├── Work.swift       # Conceptual book entity
│   ├── Edition.swift    # Published version entity
│   ├── UserLibraryEntry.swift # User's book relationship
│   └── Author.swift     # Author entity
├── Views/               # SwiftUI interface
├── Services/            # Business logic layer
└── CloudFlare-Workers/  # Search proxy infrastructure
```

## Development

### Building
```bash
# iOS Simulator
xcodebuild -project BooksTracker.xcodeproj -scheme BooksTracker -destination 'platform=iOS Simulator,name=iPhone 16'

# CloudFlare Workers
cd cloudflare-workers/books-api-proxy
wrangler deploy
```

### Architecture Goals
- ✅ **Simple**: 4 clean models vs legacy 720-line UserBook
- ✅ **Fast**: CloudKit-optimized relationships
- ✅ **Scalable**: Foundation for V2 features
- ✅ **Cultural**: Built-in diversity analytics

---

**This is a greenfield V1.0 rebuild** - clean slate implementation of the Work/Edition architecture for optimal performance and maintainability.