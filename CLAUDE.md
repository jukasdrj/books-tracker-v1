# 📚 BooksTracker - Claude Code Guide

## Project Overview

This is a **BooksTracker** iOS application built with **Swift 6.1+** and **SwiftUI**, targeting **iOS 26.0+**. The app tracks personal book libraries with cultural diversity insights. It uses a **workspace + Swift Package Manager (SPM)** architecture for clean separation between the app shell and feature code.

### Core Technologies
- **SwiftUI** with @Observable, @Environment state management
- **SwiftData** with CloudKit sync
- **Swift Concurrency** (async/await, @MainActor)
- **Swift Testing** framework (@Test macros, #expect assertions)
- **iOS 26 Liquid Glass** design system

### Key Directories
- `BooksTracker.xcworkspace/` - Open this in Xcode
- `BooksTrackerPackage/` - Primary development area (SPM)
- `cloudflare-workers/` - Backend API & caching
- `Scripts/` - Build & release automation

## Versioning & Release Management

### Automated Scripts
```bash
./Scripts/update_version.sh patch          # 1.0.0 → 1.0.1
./Scripts/release.sh minor "New features"  # Complete release workflow
./Scripts/setup_hooks.sh                   # Auto-updates build on commits
```

**Version Configuration**: Managed in `Config/Shared.xcconfig`
- `MARKETING_VERSION`: User-facing version
- `CURRENT_PROJECT_VERSION`: Auto-generated build number

## Development Commands

### Building & Testing
```javascript
// Build and run
build_run_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 17 Pro"
})

// Run tests
swift_package_test({ packagePath: "/path/to/BooksTrackerPackage" })
test_sim({ workspacePath: "...", scheme: "BooksTracker", simulatorName: "..." })
```

### Backend (Cloudflare Workers)
```bash
npm run dev              # Start local development
npm run deploy           # Deploy all workers
wrangler tail --format pretty           # Real-time logs
```

**Primary API**: `https://books-api-proxy.jukasdrj.workers.dev/search/auto`

## Architecture & Data Models

### Core SwiftData Models
- **Work**: Creative work (title, authors, publication year)
- **Edition**: Specific published edition (ISBN, publisher, format)
- **Author**: Author info with cultural diversity metadata
- **UserLibraryEntry**: User's relationship to work (status, progress, ratings)

### Key Relationships
```
Work 1:many Edition
Work many:many Author
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

### Cultural Diversity Tracking
- **AuthorGender**: female, male, nonBinary, other, unknown
- **CulturalRegion**: africa, asia, europe, northAmerica, etc.
- **Marginalized Voice Detection**: Built-in underrepresented author identification

## SwiftUI Architecture

### State Management (No ViewModels)
- **@State**: View-specific state and model objects
- **@Observable**: Observable model classes (replaces ObservableObject)
- **@Environment**: Dependency injection (ThemeStore, ModelContext)
- **@Binding**: Two-way data flow

### Example Pattern
```swift
@Observable
class DataService {
    var items: [Item] = []
    var isLoading = false
}

struct ContentView: View {
    @State private var dataService = DataService()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(dataService.items) { item in
            Text(item.name)
        }
        .task { await dataService.loadData() }
    }
}
```

## iOS 26 Liquid Glass Design System

### Theme System
- **iOS26ThemeStore**: App-wide theming (@Observable)
- **5 Built-in Themes**: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- **Cultural Color Mapping**: Theme-aware colors for regions
- **Key Components**: GlassEffectContainer, iOS26AdaptiveBookCard, FluidGridSystem

## Code Quality Standards

### Swift Conventions
- **Naming**: UpperCamelCase for types, lowerCamelCase for properties/functions
- **Optionals**: Use `guard let`/`if let` - avoid force unwrapping
- **Value Types**: Use `struct` for models, `class` only for reference semantics

### Concurrency Requirements
- **@MainActor**: All UI updates must use @MainActor isolation
- **Swift Concurrency**: Use async/await, actors, Task (no GCD)
- **.task Modifier**: Use `.task {}` on views for async operations
- **Sendable Conformance**: Types crossing concurrency boundaries must be Sendable

### Swift Testing Example
```swift
@Test func userCanAddBookToLibrary() async throws {
    let work = Work(title: "Test Book")
    let entry = UserLibraryEntry.createWishlistEntry(for: work)
    #expect(entry.readingStatus == .wishlist)
}
```
## 📷 Barcode Scanning Module

### Key Files
- `ISBNValidator.swift` - ISBN-10/13 validation with checksum
- `CameraManager.swift` - Swift 6 actor-isolated camera management
- `BarcodeDetectionService.swift` - AsyncStream detection (Vision + AVFoundation)
- `ModernCameraPreview.swift` - SwiftUI camera preview with glass effects
- `ModernBarcodeScannerView.swift` - Complete scanner UI

### Integration
- **SearchView**: Barcode button in navigation toolbar
- **SearchModel**: `searchByISBN()` method for immediate lookup
- **Backend**: Connects to books-api-proxy endpoint
- **Theme**: Full iOS 26 Liquid Glass integration

### Features
- Dual detection (Vision + AVFoundation fallback)
- Smart throttling prevents duplicate scans
- Perfect Swift 6 concurrency compliance
- Zero external dependencies
- Haptic feedback and smooth permissions

## Development Workflow

### Adding Features
1. Work in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Types exposed to app need `public` access
3. Edit `Package.swift` for SPM dependencies
4. Add Swift Testing tests in `BooksTrackerPackage/Tests/`

### App Capabilities
Edit `Config/BooksTracker.entitlements`:
```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

### SwiftData Model Changes
Add new models to schema in `BooksTrackerApp.swift`:
```swift
let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
```

## Key Business Logic

### Reading Status Workflow
- **Wishlist**: Want to read → `.wishlist` status, no edition
- **Owned**: Have edition → `.toRead`, `.reading`, `.read` status with edition
- **Progress**: Page-based tracking with automatic completion

### Architecture Decisions
- **No ViewModels**: Pure SwiftUI with @Observable for better performance
- **SwiftData**: Type-safe API, SwiftUI integration, CloudKit sync
- **Package Architecture**: Clean separation, improved build times, modularity

## Backend Architecture

### Cloudflare Workers Ecosystem
- **books-api-proxy**: Main search API with ISBNdb/OpenLibrary/Google Books
- **personal-library-cache-warmer**: Intelligent caching system
- **isbndb-biography-worker**: Author biography enhancement

### System Status
- **Cache**: 800+ entries with automatic warming
- **API Coverage**: 3 providers with intelligent fallbacks
- **Performance**: Sub-second responses for cached hits
- **Monitoring**: Real-time dashboard and logging

### Key Features
- Work/Edition normalization matching SwiftData models
- External ID extraction (isbndbID, openLibraryID, googleBooksVolumeID)
- Service bindings with RPC communication
- Multi-tier cron job scheduling

## Common Patterns

### Model Access in Views
```swift
struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var works: [Work]
    let work: Work

    var body: some View {
        // Direct model access, no ViewModel layer
    }
}
```

### Async Operations
```swift
struct LibraryView: View {
    @State private var books: [Work] = []

    var body: some View {
        List(books) { book in
            BookRow(book: book)
        }
        .task { await loadBooks() }
        .refreshable { await refreshBooks() }
    }
}
```

## Debugging & Troubleshooting

### Key Debugging Commands
```bash
# Backend monitoring
wrangler tail personal-library-cache-warmer --search "📚"
wrangler tail books-api-proxy --search "provider"

# Debug endpoints
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/debug-kv"
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

### iOS App Debugging
```javascript
// Test app with logs
launch_app_logs_sim({
    simulatorUuid: "SIMULATOR_UUID",
    bundleId: "com.bookstrack.BooksTracker"
})

// UI hierarchy debugging
describe_ui({ simulatorUuid: "SIMULATOR_UUID" })
```

### Resolved Issues
- **Navigation Fix (v1.1.1)**: Fixed gesture conflicts in iOS26FloatingBookCard
- **Backend Cache System (v1.2)**: Fixed service binding URL patterns (absolute vs relative)

### Debugging Best Practices
- Trust runtime verification over CLI tools for distributed systems
- Test actual functionality before assuming system failure
- Add debug endpoints early in development
- Use 5 Whys analysis for systematic debugging