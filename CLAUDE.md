# 📚 BooksTrack by oooe - Claude Code Guide

**Version 3.0.0 (Build 47+)** | **iOS 26.0+** | **Swift 6.1+** | **Updated: October 23, 2025**

Personal book tracking iOS app with cultural diversity insights. SwiftUI, SwiftData, Cloudflare Workers backend.

**🎉 NOW ON APP STORE!** Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`

## Quick Start

**Note:** Implementation plans tracked in [GitHub Issues](https://github.com/users/jukasdrj/projects/2).

### Core Stack
- SwiftUI + @Observable + SwiftData + CloudKit sync
- Swift 6.1 concurrency (@MainActor, actors, typed throws)
- Swift Testing (@Test, #expect, parameterized tests)
- iOS 26 Liquid Glass design system
- Cloudflare Workers (RPC service bindings, Durable Objects, KV/R2)

### Essential Commands

**🚀 MCP Workflows (Recommended):**
```bash
/gogo          # App Store validation pipeline
/build         # Quick build check
/test          # Run Swift Testing suite
/device-deploy # Deploy to iPhone/iPad
/sim           # Launch with log streaming
```
See **[MCP_SETUP.md](MCP_SETUP.md)** for XcodeBuildMCP configuration.

**Backend:**
```bash
cd cloudflare-workers
npm run deploy           # Deploy all workers
wrangler tail --format pretty  # Real-time logs
```

## Architecture

### SwiftData Models

**Entities:** Work, Edition, Author, UserLibraryEntry

**Relationships:**
```
Work 1:many Edition
Work many:many Author
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

**CloudKit Rules:**
- Inverse relationships MUST be declared on to-many side only
- All attributes need defaults
- All relationships optional
- Predicates can't filter on to-many (filter in-memory)

### State Management - No ViewModels!

**Pattern: @Observable models + @State**
```swift
@Observable
class SearchModel {
    var state: SearchViewState = .initial(trending: [], recentSearches: [])
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch searchModel.state {
        case .initial(let trending, _): TrendingBooksView(trending: trending)
        case .results(_, _, let items, _, _): ResultsListView(items: items)
        // ... handle all cases
        }
    }
}
```

**Property Wrappers:**
- `@State` - View-specific state and model objects
- `@Observable` - Observable model classes (replaces ObservableObject)
- `@Environment` - Dependency injection (ThemeStore, ModelContext)
- `@Bindable` - **CRITICAL for SwiftData models!** Enables reactive updates on relationships

**🚨 CRITICAL: @Bindable for SwiftData Reactivity**
```swift
// ❌ WRONG: View won't update when rating changes
struct BookDetailView: View {
    let work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}

// ✅ CORRECT: @Bindable observes changes
struct BookDetailView: View {
    @Bindable var work: Work
    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
    }
}
```

### Backend Architecture

**Worker:** `api-worker` (Cloudflare Worker monolith)

**Endpoints:**
- `GET /search/title?q={query}` - Book search (6h cache)
- `GET /search/isbn?isbn={isbn}` - ISBN lookup (7-day cache)
- `POST /search/advanced` - Multi-field search (title + author + ISBN)
- `POST /api/enrichment/start` - Batch enrichment with WebSocket progress
- `POST /api/scan-bookshelf?jobId={uuid}` - AI bookshelf scan with Gemini 2.0 Flash
- `POST /api/scan-bookshelf/batch` - Batch scan (max 5 photos, parallel upload → sequential processing)
- `GET /ws/progress?jobId={uuid}` - WebSocket progress (unified for ALL jobs)

**AI Provider (Gemini Only):**
- **Gemini 2.0 Flash:** Google's production vision model with 2M token context window
- Processing time: 25-40s (includes AI inference + enrichment)
- Image size: Handles 4-5MB images natively (no resizing needed)
- Accuracy: High (0.7-0.95 confidence scores)
- Optimized for ISBN detection and small text on book spines

**Note:** Cloudflare Workers AI models (Llama, LLaVA, UForm) removed due to small context windows (128K-8K tokens) that couldn't handle typical bookshelf images. See `cloudflare-workers/GEMINI_OPTIMIZATION.md` and [GitHub Issue #134](https://github.com/jukasdrj/books-tracker-v1/issues/134) for details.

**Architecture:**
- Single monolith worker with direct function calls (no RPC service bindings)
- ProgressWebSocketDO for real-time status updates (all background jobs)
- No circular dependencies, no polling endpoints
- KV caching, R2 image storage, multi-provider AI integration

**Internal Structure:**
```
api-worker/
├── src/index.js                # Main router
├── durable-objects/            # WebSocket DO
├── services/                   # Business logic (AI, enrichment, APIs)
├── providers/                  # AI provider modules (Gemini, Cloudflare)
├── handlers/                   # Request handlers (search)
└── utils/                      # Shared utilities (cache)
```

**Rule:** All background jobs report via WebSocket. No polling. All services communicate via direct function calls.

**See:** `cloudflare-workers/SERVICE_BINDING_ARCHITECTURE.md` for monolith architecture details. Previous distributed architecture archived in `cloudflare-workers/_archived/`.

### Navigation Structure

**4-Tab Layout (iOS 26 HIG Optimized):**
- **Library** - Main collection view with Settings gear icon in toolbar
- **Search** - Book search with ISBN scanner
- **Shelf** - AI-powered bookshelf scanner (Gemini 2.0 Flash)
- **Insights** - Reading statistics and cultural diversity analytics

**Settings Access:**
- Accessed via gear icon in Library tab toolbar (Books.app pattern)
- Sheet presentation with "Done" button
- Not in tab bar (4 tabs optimal per iOS 26 HIG)

**Navigation Patterns:**
```swift
// Push navigation for details
.navigationDestination(item: $selectedBook) { book in WorkDetailView(work: book.work) }

// Sheet presentation for Settings
.sheet(isPresented: $showingSettings) {
    NavigationStack { SettingsView() }
}
```

## Development Standards

### Swift 6 Concurrency

**Actor Isolation:**
- `@MainActor` - UI components, SwiftUI views
- `@CameraSessionActor` - Camera/AVFoundation
- `nonisolated` - Pure functions, initialization

**🚨 BAN `Timer.publish` in Actors:**
- Use `await Task.sleep(for:)` instead
- Combine doesn't integrate with Swift 6 actor isolation

**Best Practice:**
```swift
@State private var tracker = PollingProgressTracker<MyJob>()
let result = try await tracker.start(
    job: myJob,
    strategy: AdaptivePollingStrategy(),  // Battery-optimized!
    timeout: 90
)
```

**See:** `docs/CONCURRENCY_GUIDE.md` for full patterns + `docs/SWIFT6_COMPILER_BUG.md` for lessons learned.

### iOS 26 HIG Compliance

**🚨 CRITICAL: Don't Mix @FocusState with .searchable()**
- iOS 26's `.searchable()` manages focus internally
- Manual `@FocusState` creates keyboard conflicts

**Navigation:**
```swift
// ✅ CORRECT: Push navigation
.navigationDestination(item: $selectedBook) { book in WorkDetailView(work: book.work) }

// ❌ WRONG: Sheets break navigation stack
.sheet(item: $selectedBook) { ... }
```

### Code Quality

**Swift Conventions:**
- UpperCamelCase types, lowerCamelCase properties
- Use `guard let`/`if let`, avoid force unwrapping
- `struct` for models, `class` only for reference semantics

**Zero Warnings Policy:**
- All PRs must build with zero warnings
- Warnings treated as errors (`-Werror`)

**Nested Types Pattern:**
```swift
@MainActor
public class CSVImportService {
    public enum DuplicateStrategy: Sendable { case skip, update, smart }
    public struct ImportResult { let successCount: Int }
}
```

**Sendable Rule:** Don't claim Sendable for types containing SwiftData @Model objects. Use `@MainActor` isolation.

**PR Checklist:**
- [ ] Zero warnings (Swift 6 concurrency, deprecated APIs)
- [ ] @Bindable for SwiftData models in child views
- [ ] No Timer.publish in actors (use Task.sleep)
- [ ] Nested supporting types
- [ ] WCAG AA contrast (4.5:1+)
- [ ] Real device testing

## Common Tasks

### Adding Features

1. Develop in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. Use `public` for types exposed to app shell
3. Add dependencies in `BooksTrackerPackage/Package.swift`
4. Add tests in `BooksTrackerPackage/Tests/`

### Library Reset

**Comprehensive Reset (Settings → Reset Library):**
- Cancels in-flight backend enrichment jobs (prevents resource waste)
- Stops local enrichment processing
- Deletes all SwiftData models (Works, Editions, Authors, UserLibraryEntries)
- Clears enrichment queue
- Resets AI provider to Gemini
- Resets feature flags to defaults
- Clears search history

**Backend Cancellation Flow:**
1. iOS calls `EnrichmentQueue.shared.cancelBackendJob()`
2. POST to `/api/enrichment/cancel` with jobId
3. Worker calls `doStub.cancelJob()` on ProgressWebSocketDO
4. DO sets "canceled" status in Durable Object storage
5. Enrichment loop checks `doStub.isCanceled()` before each book
6. If canceled, sends final status update and breaks loop

**Critical:** Backend jobs are tracked via `currentJobId` in EnrichmentQueue. Always call `setCurrentJobId()` when starting enrichment and `clearCurrentJobId()` when complete.

### Barcode Scanning

```swift
// Quick integration in SearchView
.sheet(isPresented: $showingScanner) {
    ModernBarcodeScannerView { isbn in
        Task { await searchModel.searchByISBN(isbn) }
    }
}
```

**Critical:** Single CameraManager instance! Pass via dependency injection.

### Features

**Bookshelf AI Scanner:** See `docs/features/BOOKSHELF_SCANNER.md`
- Gemini 2.0 Flash AI (optimized, 2M token context window)
- WebSocket real-time progress (8ms latency!)
- 60% confidence threshold for review queue
- iOS preprocessing (3072px @ 90% quality, 400-600KB)

**Batch Bookshelf Scanning:** See `docs/features/BATCH_BOOKSHELF_SCANNING.md`
- Capture up to 5 photos in one session
- Parallel upload → sequential Gemini processing
- Real-time per-photo progress via WebSocket
- Automatic deduplication by ISBN
- Cancel mid-batch with partial results

**CSV Import:** See `docs/features/CSV_IMPORT.md`
- 100 books/min, <200MB memory
- Auto-detects Goodreads/LibraryThing/StoryGraph
- 90%+ enrichment success (title normalization!)

**Review Queue:** See `docs/features/REVIEW_QUEUE.md`
- Human-in-the-loop for low-confidence AI detections
- CorrectionView with spine image cropping
- Automatic temp file cleanup

## Debugging

### iOS
```javascript
launch_app_logs_sim({ simulatorUuid: "UUID", bundleId: "com.bookstrack.BooksTracker" })
describe_ui({ simulatorUuid: "UUID" })
```

### Backend
```bash
wrangler tail books-api-proxy --search "provider"
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

### Critical Lessons

**Real Device Testing:**
- `.navigationBarDrawer(displayMode: .always)` breaks keyboard on real devices (iOS 26 bug!)
- Always test keyboard input on physical devices
- Glass overlays need `.allowsHitTesting(false)` to pass touches through

**SwiftData:**
- Persistent IDs can outlive models → always check existence
- Clean derived data for macro issues: `rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*`

**Architecture:**
- Check provider tags: `"orchestrated:google+openlibrary"` vs `"google"`
- Direct API calls between workers = violation
- Trust runtime verification over CLI tools

## Design System

### Themes
- 5 built-in: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- `@Environment(iOS26ThemeStore.self)` for access

### Text Contrast (WCAG AA)
```swift
// ✅ Use system semantic colors (auto-adapt to backgrounds)
Text("Author").foregroundColor(.secondary)
Text("Publisher").foregroundColor(.tertiary)

// ❌ Don't use custom "accessible" colors (deleted v1.12.0)
```

**Rule:** `themeStore.primaryColor` for brand, `.secondary`/`.tertiary` for metadata.

## Documentation

```
📄 CLAUDE.md                 ← This file (quick reference)
📄 MCP_SETUP.md             ← XcodeBuildMCP workflows
📄 CHANGELOG.md             ← Victory stories + debugging sagas
📁 docs/features/           ← Deep dives (BOOKSHELF_SCANNER, BATCH_BOOKSHELF_SCANNING, CSV_IMPORT, REVIEW_QUEUE)
📁 cloudflare-workers/      ← SERVICE_BINDING_ARCHITECTURE.md (RPC + deployment)
📁 .claude/commands/        ← Slash commands (/gogo, /build, /test, /sim)
```

**Philosophy:**
- CLAUDE.md: Current standards (<500 lines, quick reference)
- docs/features/: Deep dives with architecture + lessons
- CHANGELOG.md: Historical victories
- GitHub Issues: Active tasks

## Key Business Logic

### Reading Status
```swift
// Wishlist → Owned → Reading → Read
let entry = UserLibraryEntry.createWishlistEntry(for: work)
entry.status = .toRead; entry.edition = ownedEdition
entry.currentPage = 150; entry.status = .reading
entry.status = .read; entry.completionDate = Date()
```

### Cultural Diversity
- AuthorGender: female, male, nonBinary, other, unknown
- CulturalRegion: africa, asia, europe, northAmerica, etc.
- Marginalized Voice: Auto-detection

---

**Build Status:** ✅ Zero warnings, zero errors
**HIG Compliance:** 100% iOS 26 standards
**Swift 6:** Full concurrency compliance
**Accessibility:** WCAG AA compliant contrast
