# 📚 BooksTrack by oooe - Claude Code Guide

**Version 3.0.0 (Build 47+)** | **iOS 26.0+** | **Swift 6.1+** | **Updated: October 17, 2025**

This is a personal book tracking iOS app with cultural diversity insights, built with SwiftUI, SwiftData, and a Cloudflare Workers backend.

**🎉 NOW ON APP STORE!** Bundle ID: `Z67H8Y8DW.com.oooefam.booksV3`

## Quick Start

**Note:** Implementation plans and feature proposals now tracked in [GitHub Issues](https://github.com/users/jukasdrj/projects/2). Former docs/plans/ content migrated Oct 2025.

### Core Technologies
- **SwiftUI** with @Observable, @Environment state management
- **SwiftData** with CloudKit sync
- **Swift Concurrency** (async/await, @MainActor, actors)
- **Swift Testing** framework (@Test macros, #expect assertions)
- **iOS 26 Liquid Glass** design system
- **Cloudflare Workers** backend (books-api-proxy, cache-warmer, biography services)

### Key Directories
```
BooksTracker.xcworkspace/          # Open this in Xcode
├── BooksTrackerPackage/           # Primary development (SPM)
│   ├── Sources/BooksTrackerFeature/
│   └── Tests/
├── cloudflare-workers/            # Backend API & caching
├── Config/                        # Xcconfig & entitlements
└── Scripts/                       # Build & release automation
```

### Essential Commands

**🚀 MCP-Powered Workflows (Recommended):**
```bash
/gogo              # Complete App Store validation pipeline
/build             # Quick build check for simulator
/test              # Run Swift Testing suite
/device-deploy     # Deploy to connected iPhone/iPad
/sim               # Launch in simulator with log streaming
```
See **[MCP_SETUP.md](MCP_SETUP.md)** for XcodeBuildMCP configuration and autonomous workflows.

**Manual iOS Development (Fallback):**
```javascript
// Build and run
build_run_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 17 Pro"
})

// Run tests
test_sim({ workspacePath: "...", scheme: "BooksTracker", simulatorName: "..." })
swift_package_test({ packagePath: "/path/to/BooksTrackerPackage" })
```

**Backend (Cloudflare Workers):**
```bash
cd cloudflare-workers
npm run dev              # Local development
npm run deploy           # Deploy all workers
wrangler tail --format pretty  # Real-time logs
```

**Version Management:**
```bash
./Scripts/update_version.sh patch          # 1.0.0 → 1.0.1
./Scripts/release.sh minor "New features"  # Complete release
```

**App Icon Generation:**
```bash
./Scripts/generate_app_icons.sh ~/path/to/icon-1024x1024.png
# Generates all 15 iOS icon sizes (20px → 1024px)
# Updates BooksTracker/Assets.xcassets/AppIcon.appiconset/
```

## Architecture

### SwiftData Models

**Core Entities:**
- **Work**: Creative work (title, authors, publication year)
- **Edition**: Specific published edition (ISBN, publisher, format)
- **Author**: Author info with cultural diversity metadata
- **UserLibraryEntry**: User's reading status, progress, ratings

**Relationships:**
```
Work 1:many Edition
Work many:many Author
Work 1:many UserLibraryEntry
UserLibraryEntry many:1 Edition
```

**Critical CloudKit Rules:**
- Inverse relationships MUST be declared on to-many side only
- All attributes need defaults for CloudKit compatibility
- All relationships should be optional
- Predicates cannot filter on to-many relationships (filter in-memory instead)

### State Management (No ViewModels)

**Pattern: Direct model access with @Observable**
```swift
@Observable
class SearchModel {
    var searchText = ""
    var results: [SearchResult] = []
    var isLoading = false
}

struct SearchView: View {
    @State private var searchModel = SearchModel()
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List(searchModel.results) { result in
            ResultRow(result: result)
        }
        .task { await searchModel.performSearch() }
    }
}
```

**Key Principles:**
- `@State`: View-specific state and model objects
- `@Observable`: Observable model classes (replaces ObservableObject)
- `@Environment`: Dependency injection (ThemeStore, ModelContext)
- `@Binding`: Two-way data flow
- `@Bindable`: **CRITICAL for SwiftData models in views!**
- No separate ViewModel layer - models are observable directly

**🚨 CRITICAL: SwiftData Reactivity Pattern**
```swift
// ❌ WRONG: SwiftUI won't observe relationship changes
struct BookDetailView: View {
    let work: Work  // Static reference - no observation

    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
        // User updates rating → Database saves ✅
        // View updates → ❌ DOESN'T HAPPEN!
    }
}

// ✅ CORRECT: @Bindable enables reactive updates
struct BookDetailView: View {
    @Bindable var work: Work  // Observed reference

    var body: some View {
        Text("\(work.userLibraryEntries?.first?.personalRating ?? 0)")
        // User updates rating → Database saves ✅
        // @Bindable observes change → View updates ✅
    }
}
```

**When to use `@Bindable`:**
- Passing SwiftData models to child views
- Views that display/edit model relationships
- Any view that needs to react to model changes
- Star ratings, progress bars, status indicators, etc.

### Search State Architecture (October 2025)

**Pattern: Unified State Enum**

The search feature uses a comprehensive state enum that eliminates impossible states through Swift's type system:

```swift
@MainActor
public enum SearchViewState: Equatable, Sendable {
    /// Initial state with discovery content
    case initial(trending: [SearchResult], recentSearches: [String])

    /// Actively searching - preserves previous results for smooth UX
    case searching(query: String, scope: SearchScope, previousResults: [SearchResult])

    /// Successful search with results
    case results(query: String, scope: SearchScope, items: [SearchResult],
                 hasMorePages: Bool, cacheHitRate: Double)

    /// No results found
    case noResults(query: String, scope: SearchScope)

    /// Error state with retry context
    case error(message: String, lastQuery: String, lastScope: SearchScope,
               recoverySuggestion: String)
}
```

**Key Benefits:**
- **Impossible States Eliminated**: Can't have `isSearching=true` + `errorMessage` simultaneously
- **Rich Context**: Each state carries all necessary data (query, scope, results, error info)
- **Smooth UX**: `.searching` preserves previous results to prevent flickering
- **Error Recovery**: Error state includes `lastQuery` and `lastScope` for retry functionality

**Usage in Views:**
```swift
struct SearchView: View {
    @State private var searchModel = SearchModel()

    var body: some View {
        switch searchModel.state {
        case .initial(let trending, let recentSearches):
            TrendingBooksView(trending: trending, recentSearches: recentSearches)

        case .searching(let query, _, let previousResults):
            LoadingView(query: query, previousResults: previousResults)

        case .results(_, _, let items, let hasMorePages, _):
            ResultsListView(items: items, hasMorePages: hasMorePages)

        case .noResults(let query, let scope):
            EmptyStateView(query: query, scope: scope)

        case .error(let message, let lastQuery, let lastScope, let suggestion):
            ErrorView(message: message, suggestion: suggestion) {
                searchModel.search(query: lastQuery, scope: lastScope)  // Retry
            }
        }
    }
}
```

**Architectural Lessons:**
- Single source of truth prevents sync bugs
- Associated values make data flow explicit
- Pattern matching forces exhaustive case handling
- Computed properties (`currentResults`, `isSearching`) provide convenience

**Files:**
- `SearchViewState.swift` - Enum definition with computed properties
- `SearchModel.swift` - State management with `var state: SearchViewState`
- `SearchView.swift` - UI rendering via pattern matching
- `SearchModelTests.swift` - 22 tests covering state transitions

### Backend Architecture

**Cloudflare Workers Ecosystem:**
- **books-api-proxy**: Main search orchestrator (ISBNdb/OpenLibrary/Google Books)
- **personal-library-cache-warmer**: Intelligent caching with cron jobs
- **isbndb-biography-worker**: Author biography enhancement
- **google-books-worker**: Google Books API wrapper
- **openlibrary-worker**: OpenLibrary API wrapper

**API Endpoints:**
- `/search/title` - Smart general search (6h cache)
- `/search/isbn` - Dedicated ISBN lookup (7-day cache, ISBNdb-first)
- `/search/advanced` - Multi-field filtering (title+author) - **Now orchestrates 3 providers: Google Books + OpenLibrary + ISBNdb**
- `/search/author` - Author bibliography

**Provider Orchestration (October 2025):**
- **Parallel Execution**: All 3 providers queried simultaneously via `Promise.allSettled()`
- **Graceful Degradation**: If any provider fails, others continue (resilient to API downtime)
- **Smart Deduplication**: 90% similarity threshold merges duplicate results
- **Provider Tags**: Response shows `orchestrated:google+openlibrary+isbndb` (or subset if providers fail)

**Architecture Rule:** Workers communicate via RPC service bindings - **never** direct API calls from proxy worker. Always orchestrate through specialized workers.

**API Documentation:** See [GitHub Issue #33](https://github.com/jukasdrj/books-tracker-v1/issues/33) for complete API contracts, RPC methods, and endpoint specifications.

## Development Standards

### Swift 6 Concurrency

**Actor Isolation:**
- `@MainActor`: UI components, SwiftUI views, user-facing state
- `@CameraSessionActor`: Camera/AVFoundation operations
- `nonisolated`: Pure functions, initialization, cross-actor setup
- Thread-safe APIs (NSCache, DispatchQueue): No isolation needed

**Initializer Pattern:**
```swift
actor CameraManager {
    nonisolated init() {
        // Initializers rarely need actor isolation
        // Set up notification observers with Task wrappers
        NotificationCenter.default.addObserver(
            forName: .cameraInterruption,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { await self?.handleInterruption() }
        }
    }
}
```

**AsyncStream Actor Bridging:**
```swift
let manager = cameraManager  // Capture before actor boundary
return AsyncStream { continuation in
    Task { @CameraSessionActor in
        for await item in actorMethod(manager: manager) {
            continuation.yield(item)
        }
    }
}
```

**🚨 BAN `Timer.publish` in Actors (Swift 6.2+):**

- **Rule:** Never use `Timer.publish` for polling or delays inside an `actor`
- **Reason:** Combine doesn't integrate with Swift 6 actor isolation
- **Solution:** Always use `await Task.sleep(for:)` for delays and polling loops

**🎯 Polling Pattern:**

```swift
// ✅ CORRECT: Separation of concerns
Task.detached {
    while !Task.isCancelled {
        let data = await actor.fetchData()        // Background work
        await MainActor.run { updateUI(data) }    // UI updates
        try await Task.sleep(for: .milliseconds(100))
    }
}

// 🏆 Best Practice: Reusable PollingProgressTracker
@State private var tracker = PollingProgressTracker<MyJob>()
let result = try await tracker.start(
    job: myJob,
    strategy: AdaptivePollingStrategy(),  // Battery-optimized!
    timeout: 90
)
```

**Swift 6.2 Enhancements:**

*   **Modern `NotificationCenter` API:** The project now uses the `async/await` API for `NotificationCenter`, which simplifies notification handling and improves readability.

    ```swift
    // ✅ CORRECT: Swift 6.2 async/await API
    private func handleNotifications() async {
        let notifications = AsyncStream.merge(
            NotificationCenter.default.notifications(named: .switchToLibraryTab),
            NotificationCenter.default.notifications(named: .enrichmentStarted)
        )

        for await notification in notifications {
            handle(notification)
        }
    }
    ```

*   **`@concurrent` Attribute:** The `@concurrent` attribute is used to mark functions that are safe to run concurrently. This allows the compiler to verify their safety and can lead to performance improvements.

    ```swift
    // ✅ CORRECT: Swift 6.2 @concurrent attribute
    @concurrent func calculateExpectedProgress(
        elapsed: Int,
        stages: [ScanJobResponse.StageMetadata]
    ) -> Double {
        // ... function implementation
    }
    ```

*   **Swift Testing Enhancements:** The project leverages new features in Swift Testing, such as parameterized tests, to write more concise and effective tests.

    ```swift
    // ✅ CORRECT: Swift 6.2 parameterized test
    @Test(
        "Normalize title for search",
        arguments: [
            (input: "The da Vinci Code: The Young Adult Adaptation", expected: "The da Vinci Code"),
            (input: "Devil's Knot (Justice Knot, #1)", expected: "Devil's Knot")
        ]
    )
    func testTitleNormalization(input: String, expected: String) {
        #expect(input.normalizedTitleForSearch == expected)
    }
    ```

**Lesson:** Don't fight Swift 6 isolation. Let `await` boundaries handle actor → MainActor transitions naturally.

**Full Story:** See CHANGELOG.md "Great Polling Breakthrough" + `docs/SWIFT6_COMPILER_BUG.md`

### iOS 26 HIG Compliance

**🚨 CRITICAL: iOS 26 Search Pattern Bug**
```swift
// ❌ WRONG: displayMode: .always blocks keyboard on real devices (iOS 26 regression!)
.searchable(
    text: $searchModel.searchText,
    placement: .navigationBarDrawer(displayMode: .always),  // ← BREAKS KEYBOARD!
    prompt: "Search books, authors, or ISBN"
)

// ✅ CORRECT: Omit displayMode parameter
.searchable(
    text: $searchModel.searchText,
    placement: .navigationBarDrawer,  // Works perfectly!
    prompt: "Search books, authors, or ISBN"
)
.searchScopes($searchScope) {
    ForEach(SearchScope.allCases) { scope in
        Text(scope.rawValue).tag(scope)
    }
}
```

**🚨 CRITICAL: Don't Mix @FocusState with .searchable()**
- iOS 26's `.searchable()` manages focus internally
- Adding manual `@FocusState` creates conflicts
- Result: Keyboard events blocked, space bar doesn't work
- **Solution:** Let `.searchable()` handle focus automatically

**Navigation Pattern:**
```swift
// ✅ CORRECT: Push navigation for content exploration
.navigationDestination(item: $selectedBook) { book in
    WorkDetailView(work: book.work)
}

// ❌ WRONG: Sheets break navigation stack (use for tasks/forms only)
.sheet(item: $selectedBook) { ... }
```

**Context-Aware UI (iOS 26):**
- **Never** use `UIScreen.main` (deprecated)
- Use `GeometryReader` for screen dimensions
- Responsive design is mandatory, not optional

### Code Quality

**Swift Conventions:**
- **Naming**: UpperCamelCase for types, lowerCamelCase for properties/functions
- **Optionals**: Use `guard let`/`if let` - avoid force unwrapping
- **Existence Checks**: Use `if value != nil`, not `if let _ = value`
- **Value Types**: Use `struct` for models, `class` only for reference semantics

**Zero Warnings Policy:**
- All PRs must build with zero warnings.
- All warnings, including Swift 6 concurrency warnings, are treated as errors.
- This is enforced at the build configuration level (`-Werror`).

**PR Checklist Example:**
```markdown
- [ ] Build succeeds with zero warnings
- [ ] Zero Swift 6 concurrency warnings
- [ ] Zero deprecated API warnings
```

**Swift Testing:**
```swift
@Test func userCanAddBookToLibrary() async throws {
    let work = Work(title: "Test Book")
    let entry = UserLibraryEntry.createWishlistEntry(for: work)
    #expect(entry.readingStatus == .wishlist)
}
```

**Nested Types Pattern:**

**Rule:** Supporting types should be nested inside their primary class/service to establish clear ownership and prevent namespace pollution.

**Benefits:**
- Clear ownership: `CSVImportService.DuplicateStrategy` shows relationship at call site
- Namespace organization: Prevents module-level type proliferation
- Improved discoverability: Types grouped with their usage context
- Swift 6 friendly: Makes Sendable boundaries and isolation explicit

**Example:**
```swift
@MainActor
public class CSVImportService {
    // Service methods...

    // MARK: - Supporting Types

    public enum DuplicateStrategy: Sendable {
        case skip, update, addNew, smart
    }

    public struct ImportResult {  // Not Sendable - contains SwiftData models
        let successCount: Int
        let importedWorks: [Work]  // Work is @Model (reference type)
    }
}

// Usage in caller:
let strategy: CSVImportService.DuplicateStrategy = .smart
```

**Sendable Rule:** Don't claim Sendable for types containing SwiftData @Model objects (Work, Edition, Author, UserLibraryEntry). These are reference types and violate Sendable requirements. Use `@MainActor` isolation instead.

**When to Nest:**
- Types used exclusively by one service/feature
- Enums defining service-specific options (strategies, states, errors)
- Result/response types specific to one operation

**When NOT to Nest:**
- Types shared across multiple unrelated features
- Domain models (Work, Edition, Author, etc.)
- Protocol definitions meant for broad adoption

**Pull Request Checklist:**
- [ ] **Swift 6 Concurrency:** All new `actor` and `@MainActor` code adheres to isolation rules.
- [ ] **No `Timer.publish` in actors:** `Task.sleep` is used for all polling and delays in actor contexts.
- [ ] **SwiftData Reactivity:** `@Bindable` is used for all SwiftData models passed to child views.
- [ ] **Nested Types:** Supporting types are nested inside their primary class/service.
- [ ] **No Sendable + SwiftData:** Types containing @Model objects don't claim Sendable conformance.
- [ ] **WCAG AA Compliance:** All new UI components have a contrast ratio of 4.5:1 or higher.
- [ ] **Real Device Testing:** All UI changes have been tested on a physical device.

## Common Tasks

### Adding Features

1. **Develop in SPM Package:**
   ```
   BooksTrackerPackage/Sources/BooksTrackerFeature/
   ```

2. **Public Access for App:**
   Types exposed to app shell need `public` access modifier

3. **Dependencies:**
   Edit `BooksTrackerPackage/Package.swift` for new SPM dependencies

4. **Tests:**
   Add Swift Testing tests in `BooksTrackerPackage/Tests/`

### App Capabilities

Edit entitlements in `Config/BooksTracker.entitlements`:
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.bookstrack.BooksTracker</string>
</array>
```

### SwiftData Schema Changes

Update schema in `BooksTrackerApp.swift`:
```swift
let schema = Schema([
    Work.self,
    Edition.self,
    Author.self,
    UserLibraryEntry.self
])
```

### App Icon Generation 🎨

**Usage:** `./Scripts/generate_app_icons.sh ~/path/to/icon-1024x1024.png`

**What It Does:** Generates all 15 iOS icon sizes (20px → 1024px) using macOS `sips` tool. Updates `Contents.json` for Xcode Asset Catalog.

**Requirements:** 1024x1024 PNG source image, macOS `sips` (pre-installed)

**Pro Tips:** Use transparent background for rounded corners, avoid text <44pt, test on light/dark backgrounds

### Barcode Scanning Integration

**Quick Start:**
```swift
// In SearchView navigation toolbar
ToolbarItem(placement: .topBarTrailing) {
    Button(action: { showingScanner = true }) {
        Image(systemName: "barcode.viewfinder")
    }
}
.sheet(isPresented: $showingScanner) {
    ModernBarcodeScannerView { isbn in
        Task { await searchModel.searchByISBN(isbn) }
    }
}
```

**Key Files:**
- `ISBNValidator.swift` - ISBN-10/13 validation with checksum
- `CameraManager.swift` - Actor-isolated camera management (@CameraSessionActor)
- `BarcodeDetectionService.swift` - AsyncStream detection
- `ModernBarcodeScannerView.swift` - Complete scanner UI
- `ModernCameraPreview.swift` - UIKit camera preview layer

**🎯 CRITICAL Pattern: Single CameraManager Instance**
- Camera hardware requires ONE active session only
- Parent view owns CameraManager, passes to children via dependency injection
- **Rule:** Never create multiple CameraManager instances
- See CHANGELOG.md "Camera Race Condition Fix" for full story

### Bookshelf AI Camera Scanner

**Status:** ✅ SHIPPING (Build 48+ with WebSocket Real-Time Progress)

**Quick Start:**
```swift
// SettingsView - Experimental Features
Button("Scan Bookshelf (Beta)") { showingBookshelfScanner = true }
    .sheet(isPresented: $showingBookshelfScanner) {
        BookshelfScannerView()
    }
```

**Key Features:**
- Gemini 2.5 Flash AI vision analysis (25-40s)
- **WebSocket real-time progress tracking** (8ms latency, 250x faster than polling!)
- Backend enrichment integration (89.7% success rate, 5-10s)
- Suggestions banner (9 types: blurry, glare, cutoff, etc.)
- Background metadata enrichment via `EnrichmentQueue.shared`
- Swift 6.2 compliant with typed throws and @MainActor progress handlers

**Progress Tracking (Build 48+):**
- **Real-time WebSocket updates** (no polling delay!)
- 4 progress stages with smooth percentage updates:
  - "Analyzing image quality..." → 10%
  - "Processing with Gemini AI..." → 30%
  - "Enriching N books..." → 70%
  - "Complete!" → 100%
- **Performance:** 95% fewer network requests (22+ polls → 4 WebSocket events)
- **Battery:** Event-driven updates instead of continuous polling

**WebSocket Implementation (Swift 6.2):**
```swift
// Typed throws for precise error handling
func processBookshelfImageWithWebSocket(
    _ image: UIImage,
    progressHandler: @MainActor @escaping (Double, String) -> Void
) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel])

// Real-time progress updates in UI
@Observable class BookshelfScanModel {
    var currentProgress: Double = 0.0  // 0.0 - 1.0
    var currentStage: String = ""      // Live stage name

    func processImage(_ image: UIImage) async {
        try await BookshelfAIService.shared.processBookshelfImageWithWebSocket(image) {
            progress, stage in
            self.currentProgress = progress  // MainActor-safe!
            self.currentStage = stage
        }
    }
}
```

**Architecture Highlights:**
- **Typed Throws:** `throws(BookshelfAIError)` for precise error handling
- **WebSocket Manager:** `WebSocketProgressManager` with Durable Object backend
- **Result Pattern:** Bridges typed throws with continuation-based WebSocket handling
- **Error Handling:** Comprehensive coverage (network, server, compression, quality rejection)
- **Memory Safety:** Explicit WebSocket cleanup in all code paths
- **Global Actor Pattern:** `@BookshelfCameraActor` for camera isolation

**Key Files:**
- `BookshelfAIService.swift` - WebSocket communication with typed throws
- `WebSocketProgressManager.swift` - Real-time progress tracking
- `BookshelfScannerView.swift` - UI with live progress bar
- `BookshelfCameraSessionManager.swift` - Camera session management
- `ScanResultsView.swift` - Review and import UI
- `SuggestionGenerator.swift` - Client-side suggestion fallback

**Backend:**
- **Cloudflare Durable Object:** `progress-websocket-durable-object`
- **WebSocket Endpoint:** `wss://books-api-proxy.jukasdrj.workers.dev/ws/progress`
- **Tests:** 3/3 passing (connection lifecycle, broadcasting, completion)

**Deprecated (Build 48+):**
- `processBookshelfImageWithProgress()` - Polling-based method (will be removed Q1 2026)
- Use `processBookshelfImageWithWebSocket()` for all new implementations

**Full Documentation:**
- Feature guide: `docs/features/BOOKSHELF_SCANNER.md`
- Validation report: `docs/validation/2025-10-17-websocket-validation-report.md`

### CSV Import & Enrichment System

**Quick Start:**
```swift
// SettingsView
Button("Import CSV Library") { showingCSVImport = true }
    .sheet(isPresented: $showingCSVImport) { CSVImportFlowView() }
```

**Architecture:** CSV → CSVParsingActor → SyncCoordinator → CSVImportService → SwiftData → EnrichmentQueue

**Key Files:**
- `CSVImportFlowView.swift` - UI orchestration with SyncCoordinator
- `SyncCoordinator.swift` - Job lifecycle management
- `CSVImportService.swift` - Stateless import logic
- `EnrichmentQueue.swift` - Background metadata enrichment

**Migration Complete (October 2025):**
- ✅ CSVImportFlowView now uses SyncCoordinator pattern
- ✅ Removed @Published state from views
- ✅ Uses ProgressBanner and StagedProgressView components
- ✅ Full Swift 6 concurrency compliance

**Performance:** 100 books/min, <200MB memory (1500+ books), 90%+ enrichment success

**Format Support:** Goodreads, LibraryThing, StoryGraph (auto-detects columns)

**🎯 Title Normalization (October 2025):**
- Two-tier storage: Original title for display, normalized for API searches
- Removes series markers: `(Series, #1)`, edition markers: `[Special]`, subtitles
- 5-step algorithm in `String+TitleNormalization.swift`
- **Impact:** Enrichment success 70% → 90%+

**Full Documentation:** See `docs/features/CSV_IMPORT.md`

## Debugging & Troubleshooting

### iOS Debugging Commands

```javascript
// Test app with logs
launch_app_logs_sim({
    simulatorUuid: "SIMULATOR_UUID",
    bundleId: "com.bookstrack.BooksTracker"
})

// UI hierarchy debugging
describe_ui({ simulatorUuid: "SIMULATOR_UUID" })
```

### Backend Debugging

```bash
# Monitor specific workers
wrangler tail personal-library-cache-warmer --search "📚"
wrangler tail books-api-proxy --search "provider"

# Debug endpoints
curl "https://personal-library-cache-warmer.jukasdrj.workers.dev/debug-kv"
curl "https://books-api-proxy.jukasdrj.workers.dev/health"
```

### Critical Debugging Lessons

**Swift Macro Issues:**
- Look for `@__swiftmacro_...` in crash logs
- Property names in crash logs not matching source code = stale macros
- **Solution:** Clean derived data and rebuild from scratch
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/BooksTracker-*
  xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker clean
  xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build
  ```

**SwiftData + CloudKit:**
- Use `#if targetEnvironment(simulator)` to detect simulator
- Set `cloudKitDatabase: .none` for simulator
- Use `isStoredInMemoryOnly: true` for clean testing

**Architecture Verification:**
- Check response provider tags: `"orchestrated:google+openlibrary"` vs `"google"`
- Direct API calls = architectural violation
- Always use RPC service bindings between workers

**Common Patterns:**
- Trust runtime verification over CLI tools for distributed systems
- Add debug endpoints early in development
- Use 5 Whys analysis for systematic debugging

**🚨 REAL DEVICE DEBUGGING (Build 45+):**

**iOS 26 Keyboard Regression:**
- `.navigationBarDrawer(displayMode: .always)` blocks keyboard events on physical devices
- Symptom: Space bar doesn't insert spaces, keyboard feels "dead"
- Works fine in simulator, BREAKS on real iPhone/iPad!
- **Solution:** Omit `displayMode` parameter entirely
- **Lesson:** Always test keyboard input on real devices!

**Glass Overlay Touch Blocking:**
```swift
// ❌ WRONG: Decorative overlay blocks ALL touches
.overlay {
    Rectangle()
        .fill(tint.opacity(0.1))
        .blendMode(.overlay)
}

// ✅ CORRECT: Allow touch pass-through
.overlay {
    Rectangle()
        .fill(tint.opacity(0.1))
        .blendMode(.overlay)
        .allowsHitTesting(false)  // ← Critical for decorative layers!
}
```

**Number Pad Keyboard Trap (iOS HIG Violation):**
- `.numberPad` has NO dismiss button (expected behavior)
- Users get stuck with keyboard open after entering numbers
- **Solution:** Add keyboard toolbar with Done button
```swift
TextField("Page Count", value: $pageCount, format: .number)
    .keyboardType(.numberPad)
    .focused($isPageFieldFocused)
    .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                isPageFieldFocused = false
            }
            .foregroundStyle(themeStore.primaryColor)
            .font(.headline)
        }
    }
```

**Frame Safety (Prevent Invalid Dimension Errors):**
- Always clamp calculations: `max(0, width - 20)` prevents negative values
- Always clamp progress: `min(1.0, max(0.0, progress))` keeps 0-100%
- Console errors like "Invalid frame dimension (negative or NaN)" = unclamped math
- Found in: camera scan lines, progress bars, dynamic layouts

**SwiftData Persistent ID Staleness:**
- Persistent IDs can outlive their models (deletion, schema changes)
- Always check existence: `modelContext.model(for: id) as? Type`
- Validate queues/caches on app startup
- Skip gracefully and clean up immediately

## iOS 26 Liquid Glass Design System

### Theme System

**iOS26ThemeStore** (`@Observable`):
- **5 Built-in Themes**: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- **Cultural Color Mapping**: Theme-aware colors for regions
- **Dynamic Switching**: Real-time theme changes across entire app

**Key Components:**
- `GlassEffectContainer` - Frosted glass backgrounds
- `iOS26AdaptiveBookCard` - Theme-aware book cards
- `FluidGridSystem` - Responsive grid layouts
- `iOS26LiquidListRow` - List row with glass effects

**Usage:**
```swift
@Environment(iOS26ThemeStore.self) private var themeStore

var body: some View {
    VStack {
        // Access current theme
        Text("Title")
            .foregroundStyle(themeStore.currentTheme.primaryColor)
    }
    .background(GlassEffectContainer())
}
```

### Progress UI Components

Reusable progress indicators built with iOS 26 Liquid Glass design system.

**Key File:** `ProgressViews/ProgressComponents.swift`

**Components:**
- **ProgressBanner** - Dismissible banner for ongoing operations
- **StagedProgressView** - Multi-stage progress bar for multi-step operations
- **PollingIndicator** - Animated spinner with label for indeterminate tasks
- **EstimatedTimeRemaining** - Countdown text view

**Usage Example:**
```swift
ProgressBanner(
    isShowing: $isBannerShowing,
    title: "Enriching Metadata",
    message: "Processing 24 of 100 books..."
)
```

**🎨 CRITICAL: Text Contrast & Accessibility**

```
   ╔════════════════════════════════════════════════════════╗
   ║  🏆 ACCESSIBILITY VICTORY: System Colors FTW! 🎯     ║
   ║                                                        ║
   ║  ❌ Deleted: Custom accessibleText colors (31 lines) ║
   ║  ✅ Replaced: System semantic colors (130+ instances)║
   ║  🎨 Result: WCAG AA guaranteed across ALL themes!    ║
   ╚════════════════════════════════════════════════════════╝
```

**❌ OLD WAY - Custom "Accessible" Colors (DEPRECATED):**
```swift
// ⚠️ These were removed in v1.12.0 - DON'T USE!
Text("Author Name")
    .foregroundColor(themeStore.accessibleSecondaryText)  // DELETED
    .foregroundStyle(themeStore.accessibleTertiaryText)   // DELETED
```

**✅ NEW WAY - System Semantic Colors (iOS Standard):**
```swift
// System colors automatically adapt to ALL backgrounds 🌈
Text("Author Name")
    .foregroundColor(.secondary)  // Auto-adapts to glass material!

Text("Publisher")
    .foregroundColor(.secondary)  // Handles dark mode automatically!

Text("Page Count")
    .foregroundColor(.tertiary)   // WCAG AA compliant everywhere!
```

**The Big Lesson (October 2025 Cleanup):**
- We tried being clever with custom `accessibleSecondaryText` colors (white @ 0.75-0.85 opacity)
- **PROBLEM:** They looked great on dark backgrounds, terrible on light glass materials 😬
- **SOLUTION:** Deleted ALL custom accessibility colors, switched to `.secondary`/`.tertiary`
- **RESULT:** Perfect contrast everywhere, zero maintenance, future-proof! 🚀

**When to use what:**
- `themeStore.primaryColor` → Buttons, icons, brand highlights ✨
- `themeStore.secondaryColor` → Gradients, decorative accents 🎨
- `.secondary` → **ALL metadata text** (authors, publishers, dates, subtitles) 📝
- `.tertiary` → **Subtle hints** (placeholder text, less important info) 💭
- `.primary` → Headlines, titles, main body content 📰

**Files Updated (v1.12.0):** 13 Swift files, 130+ replacements, net -32 lines 🎉

## Documentation Structure

```
📁 Root Directory
├── 📄 CLAUDE.md                      ← Main development guide (this file, <1000 lines)
├── 📄 MCP_SETUP.md                   ← XcodeBuildMCP configuration & workflows
├── 📄 README.md                      ← Quick start & project overview
├── 📄 CHANGELOG.md                   ← Version history, debugging sagas, victories
├── 📄 FUTURE_ROADMAP.md             ← Aspirational features
├── 📁 docs/
│   ├── 📁 features/                  ← ✨ NEW: Detailed feature documentation
│   │   ├── 📄 BOOKSHELF_SCANNER.md  ← AI camera scanner architecture
│   │   └── 📄 CSV_IMPORT.md         ← CSV import & enrichment system
│   ├── 📄 API.md                     ← Comprehensive API contract & RPC docs
│   ├── 📄 CLOUDFLARE_DEBUGGING.md   ← Worker debugging & monitoring guide
│   ├── 📄 CONCURRENCY_GUIDE.md      ← Swift 6 concurrency patterns
│   ├── 📄 SWIFT6_COMPILER_BUG.md    ← Polling pattern debugging saga
│   ├── 📄 GITHUB_WORKFLOW.md        ← GitHub Issues workflow
│   ├── 📄 MIGRATION_RECORD.md       ← Historical migration notes
│   ├── 📁 architecture/
│   │   ├── 📄 SyncCoordinator-Architecture.md  ← Current coordinator pattern
│   │   └── 📄 2025-10-16-csv-coordinator-refactor-plan.md  ← CSV refactor plan
│   ├── 📁 plans/
│   │   ├── 📄 2025-10-16-issue-audit-report.md
│   │   └── 📄 2025-10-16-project-cleanup.md
│   └── 📁 archive/
│       ├── 📄 BOOKSHELF_SCANNER_DESIGN_PLAN.md (shipped)
│       ├── 📄 csvMoon-implementation-notes.md (implemented)
│       └── 📁 serena-memories/ (legacy context)
├── 📁 .claude/commands/              ← Custom slash commands
│   ├── 📄 gogo.md                    ← App Store validation pipeline
│   ├── 📄 build.md, test.md, device-deploy.md, sim.md
└── 📁 cloudflare-workers/
    ├── 📄 README.md                  ← Backend architecture
    └── 📄 SERVICE_BINDING_ARCHITECTURE.md ← RPC technical docs
```

**Documentation Philosophy:**
- **CLAUDE.md:** Current development standards and patterns (<1000 lines, quick reference)
- **docs/features/:** Deep dives on major features (architecture, testing, lessons learned)
- **CHANGELOG.md:** Historical achievements, debugging sagas, victory stories
- **docs/archive/:** Completed plans and historical references
- **GitHub Issues:** Active tasks and implementation plans

**Implementation Plans & Future Work:**
- **GitHub Issues**: Active tasks tracked at https://github.com/users/jukasdrj/projects/2
- **Labels**: type/plan, type/feature, type/decision, status/backlog, priority/high/medium/low
- **Active Issues**: ~12-15 (down from 42 after Oct 2025 cleanup)

## Key Business Logic

### Reading Status Workflow

**Status Progression:**
1. **Wishlist**: Want to read → `.wishlist` status, no edition required
2. **Owned**: Have physical/digital copy → `.toRead`, `.reading`, `.read` with edition
3. **Progress**: Page-based tracking with automatic completion detection

**Status Transitions:**
```swift
// Add to wishlist
let entry = UserLibraryEntry.createWishlistEntry(for: work)

// Mark as owned
entry.status = .toRead
entry.edition = ownedEdition
entry.acquisitionDate = Date()

// Track progress
entry.currentPage = 150
entry.status = .reading

// Complete
entry.status = .read
entry.completionDate = Date()
```

### Cultural Diversity Tracking

**Author Metadata:**
- **AuthorGender**: female, male, nonBinary, other, unknown
- **CulturalRegion**: africa, asia, europe, northAmerica, southAmerica, middleEast, oceania
- **Marginalized Voice**: Automatic detection for underrepresented authors

**Usage:**
```swift
let diversityStats = library.calculateDiversityMetrics()
// Returns: gender distribution, regional representation, marginalized voice %
```

## 🎨 Recent Development Highlights

**See CHANGELOG.md for detailed victory stories!** This section provides quick reference for current features.

**Major Milestones (October 2025):**
- ✅ App Store Launch (v3.0.0) - Zero warnings, production-ready
- ✅ API Migration - Specialized endpoints, 168x cache improvement
- ✅ Accessibility - WCAG AA compliance across all themes
- ✅ CSV Import - 1500+ books in minutes with enrichment
- ✅ Live Activity - Lock Screen progress (deprecated - see Enrichment Banner)

**Current Focus:** Bookshelf scanner production deployment (Build 46+), reusable component extraction, API documentation

## Performance Optimizations

**Current Status (v1.9+):**
- **Parallel Provider Execution**: 3-5x speed improvement (concurrent API calls)
- **Popular Author Cache**: Pre-warmed 29+ popular authors (Stephen King, J.K. Rowling)
- **Smart Pagination**: Infinite scroll with on-demand loading
- **Provider Success Rate**: 95%+ reliability
- **Advanced Search Filtering**: Backend-driven, no client-side hacks
- **WCAG AA Compliance**: 4.5:1+ contrast across all themes

**Key Metrics:**
| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Popular Authors | 15-20s | <1s | 20x faster |
| Parallel Searches | 6-9s | <2s | 3-5x faster |
| Cache Hit Rate | 30-40% | 85%+ | 2x better |
| Contrast Ratio | 2.1:1 | 4.5:1+ | WCAG AA ✅ |
| Advanced Search | Client filter | Backend | Architecture win |
| CSV Import | Manual entry | 100 books/min | Bulk import! ✅ |
| Import Memory | N/A | <200MB (1500+ books) | Efficient 🔥 |

---

**Build Status:** ✅ Zero warnings, zero errors
**HIG Compliance:** 100% iOS 26 standards
**Swift 6:** Full concurrency compliance
**Accessibility:** WCAG AA compliant contrast
