# 📚 BooksTrack by oooe - Claude Code Guide

**Version 3.0.0 (Build 45)** | **iOS 26.0+** | **Swift 6.1+** | **Updated: October 12, 2025**

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
- `/search/advanced` - Multi-field filtering (title+author)
- `/search/author` - Author bibliography

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

- **Rule:** Never use `Timer.publish` for polling or delays inside an `actor`.
- **Reason:** `Timer.publish` is a Combine framework feature that does not integrate well with Swift 6's strict actor isolation, leading to compiler errors and unpredictable behavior. It is not `Sendable` and can cause data races.
- **Solution:** Always use `await Task.sleep(for:)` for delays and polling loops within any actor. This is the modern, concurrency-safe approach.
- **For SwiftUI Views:** `Timer.publish` may still be used in `@MainActor`-isolated views if absolutely necessary, but `Task.sleep` is still preferred.

**🎯 POLLING PATTERN (Swift 6.2 - Oct 2025):**

```
   ╔══════════════════════════════════════════════════════╗
   ║  ⚡ THE GREAT POLLING BREAKTHROUGH OF '25 ⚡        ║
   ║                                                      ║
   ║  Problem: TaskGroup + Timer.publish + @MainActor    ║
   ║           = Compiler bug that blocked us for 8hrs   ║
   ║                                                      ║
   ║  Solution: Task + Task.sleep = Pure 🔥 Magic 🔥     ║
   ╚══════════════════════════════════════════════════════╝
```

**❌ DON'T: Mix isolation domains in TaskGroup**
```swift
// This pattern BREAKS Swift 6 region isolation checker!
return try await withThrowingTaskGroup(of: Result?.self) { group in
    group.addTask { @MainActor [self] in  // ← COMPILER BUG!
        for await _ in Timer.publish(...).values {
            let data = self.fetchData()  // Actor method
            updateUI(data)               // MainActor callback
        }
    }
}
```

**✅ DO: Use Task.detached with Task.sleep**
```swift
// Separation of concerns = Swift 6 happiness! 🎉
Task.detached {
    while !Task.isCancelled {
        let data = await actor.fetchData()        // Background work
        await MainActor.run { updateUI(data) }    // UI updates
        try await Task.sleep(for: .milliseconds(100))  // ← Key!
    }
}
```

**🏆 Best Practice: PollingProgressTracker**
```swift
// Reusable component for all long-running operations
@State private var tracker = PollingProgressTracker<MyJob>()

let result = try await tracker.start(
    job: myJob,
    strategy: AdaptivePollingStrategy(),  // Battery-optimized!
    timeout: 90
)

// Or use SwiftUI modifier:
.pollingProgressSheet(
    isPresented: $isProcessing,
    tracker: tracker,
    title: "Processing..."
)
```

**Lesson Learned (Oct 2025):**
> "Don't fight Swift 6 isolation. Let `await` boundaries handle
> actor → MainActor transitions naturally. Timer.publish is Combine,
> not structured concurrency. Task.sleep is your friend! 🤝"

**See:** `docs/SWIFT6_COMPILER_BUG.md` for the full debugging saga 📖

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

**Swift Testing:**
```swift
@Test func userCanAddBookToLibrary() async throws {
    let work = Work(title: "Test Book")
    let entry = UserLibraryEntry.createWishlistEntry(for: work)
    #expect(entry.readingStatus == .wishlist)
}
```

**Pull Request Checklist:**
- [ ] **Swift 6 Concurrency:** All new `actor` and `@MainActor` code adheres to isolation rules.
- [ ] **No `Timer.publish` in actors:** `Task.sleep` is used for all polling and delays in actor contexts.
- [ ] **SwiftData Reactivity:** `@Bindable` is used for all SwiftData models passed to child views.
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

**Key Files:**
- `ISBNValidator.swift` - ISBN-10/13 validation with checksum
- `CameraManager.swift` - Actor-isolated camera management
- `BarcodeDetectionService.swift` - AsyncStream detection
- `ModernBarcodeScannerView.swift` - Complete scanner UI
- `ModernCameraPreview.swift` - UIKit camera preview layer

**Usage:**
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

**🎯 CRITICAL: Single CameraManager Instance Pattern**

```
   ╔════════════════════════════════════════════════════════╗
   ║  📹 THE CAMERA RACE CONDITION FIX (v3.0.1) 🎥        ║
   ║                                                        ║
   ║  ❌ Problem: Two CameraManager instances fighting!   ║
   ║     • ModernBarcodeScannerView creates one           ║
   ║     • ModernCameraPreview creates another            ║
   ║     • Result: Race condition → CRASH! 💥            ║
   ║                                                        ║
   ║  ✅ Solution: Single-instance dependency injection   ║
   ╚════════════════════════════════════════════════════════╝
```

**Architecture Pattern:**
```swift
// ✅ CORRECT: ModernBarcodeScannerView owns CameraManager
struct ModernBarcodeScannerView: View {
    @State private var cameraManager: CameraManager?

    var body: some View {
        if let cameraManager = cameraManager {
            // Pass shared instance to preview
            ModernCameraPreview(
                cameraManager: cameraManager,
                configuration: cameraConfiguration,
                detectionConfiguration: detectionConfiguration
            )
        }
    }

    private func handleISBNDetectionStream() async {
        // Create CameraManager ONCE if nil
        if cameraManager == nil {
            cameraManager = await CameraManager()
        }

        // Reuse existing instance
        guard let manager = cameraManager else { return }

        // Use shared manager for detection
        let detectionService = await BarcodeDetectionService(...)
        for await isbn in await detectionService.isbnDetectionStream(
            cameraManager: manager
        ) {
            handleISBNDetected(isbn)
        }
    }

    private func cleanup() {
        // Proper teardown
        isbnDetectionTask?.cancel()
        if let manager = cameraManager {
            await manager.stopSession()
        }
        cameraManager = nil
    }
}

// ✅ CORRECT: ModernCameraPreview receives CameraManager
struct ModernCameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager  // Required parameter

    init(
        cameraManager: CameraManager,  // No optional, no @StateObject
        configuration: CameraConfiguration,
        detectionConfiguration: BarcodeDetectionConfiguration,
        onError: @escaping (CameraError) -> Void
    ) {
        self.cameraManager = cameraManager
        // ...
    }
}
```

**Key Principles:**
1. **Single Ownership**: `ModernBarcodeScannerView` creates and owns the `CameraManager`
2. **Dependency Injection**: Pass shared instance to child views (no @StateObject!)
3. **Lifecycle Management**: Create once, reuse throughout view lifecycle, cleanup on dismiss
4. **Swift 6 Compliance**: Respects @CameraSessionActor isolation boundaries

**Why This Matters:**
- Camera hardware can only have ONE active session
- Multiple AVCaptureSession instances = undefined behavior
- Swift 6 actor isolation prevents data races, but doesn't prevent resource conflicts
- Dependency injection makes ownership explicit

**Lesson Learned (Oct 2025):**
> "When working with exclusive hardware resources (camera, microphone, GPS),
> treat them like singletons within your view hierarchy. One owner,
> explicit passing, clean lifecycle. Trust Swift 6 actors for thread safety,
> but YOU handle resource exclusivity!" 🎯

### Bookshelf AI Camera Scanner (NEW - Build 46! 📸)

**Key Files:**
- **Camera:** `BookshelfCameraSessionManager.swift`, `BookshelfCameraViewModel.swift`, `BookshelfCameraPreview.swift`, `BookshelfCameraView.swift`
- **API:** `BookshelfAIService.swift`
- **UI:** `BookshelfScannerView.swift`, `ScanResultsView.swift`

**Quick Start:**
```swift
// SettingsView - Experimental Features
Button("Scan Bookshelf (Beta)") { showingBookshelfScanner = true }
    .sheet(isPresented: $showingBookshelfScanner) {
        BookshelfScannerView()  // Now with working camera! 🎉
    }
```

**Architecture: Swift 6.1 Global Actor Pattern** 🏆

```swift
@globalActor
actor BookshelfCameraActor {
    static let shared = BookshelfCameraActor()
}

@BookshelfCameraActor
final class BookshelfCameraSessionManager {
    // Trust Apple's thread-safety guarantee for read-only access
    nonisolated(unsafe) private let captureSession = AVCaptureSession()
    nonisolated init() {}  // Cross-actor instantiation

    func startSession() async -> AVCaptureSession {
        // Returns session for MainActor preview layer configuration
    }

    func capturePhoto(flashMode: FlashMode) async throws -> Data {
        // ✅ Returns Sendable Data (not UIImage!)
        // MainActor creates UIImage from Data
    }
}
```

**Critical Patterns:**

1. **Global Actor (not plain actor):** Required for cross-isolation access
2. **nonisolated(unsafe):** Trust AVCaptureSession thread-safety
3. **@preconcurrency import:** Suppress AVFoundation Sendable warnings
4. **Data Bridge:** Return Data from actor, create UIImage on MainActor
5. **Task Wrapper:** `Task { @BookshelfCameraActor in ... }.value` for calls

**AVFoundation Configuration Order** ⚠️ CRITICAL:
```swift
// ❌ WRONG: Crashes with activeFormat error
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
captureSession.addOutput(output)

// ✅ CORRECT: Add to session FIRST
captureSession.addOutput(output)
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
```

**User Journey:**
```
Settings → Scan Bookshelf → Camera Button
    ↓
Camera permissions (AVCaptureDevice.requestAccess)
    ↓
Live preview (AVCaptureVideoPreviewLayer)
    ↓
Capture → Review sheet → "Use Photo"
    ↓
Upload to Cloudflare Worker (bookshelf-ai-worker)
    ↓
Gemini 2.5 Flash AI analysis
    ↓
ScanResultsView → Add books to SwiftData
```

**Privacy:** Camera permission required. Photos uploaded to Cloudflare AI Worker for analysis (not stored). Requires `NSCameraUsageDescription` in Info.plist.

**Status:** ✅ SHIPPING (Build 46)! Swift 6.1 compliant, tested on iPhone 17 Pro (iOS 26.0.1). Zero warnings, zero data races.

**🎉 ENRICHMENT INTEGRATION (Build 49 - October 2025):**

Backend enrichment system (89.7% success rate) now fully integrated with iOS app:

**Response Model Updates (BookshelfAIService.swift):**
- Added `confidence: Double?` (direct field, replacing nested struct)
- Added `enrichmentStatus: String?` (tracks backend enrichment results)
- Added `coverUrl: String?` (enriched book cover URLs)
- Simplified model structure for better API alignment

**Conversion Logic Enhancement:**
- Maps enrichment status to detection states:
  - "ENRICHED"/"FOUND" → `.detected`
  - "UNCERTAIN"/"NEEDS_REVIEW" → `.uncertain`
  - "REJECTED" → `.rejected`
- Graceful fallback for missing enrichment data
- Uses direct confidence score from Gemini AI

**Timeout Optimization:**
- Increased from 60s → 70s to accommodate AI (25-40s) + enrichment (5-10s)
- Ensures reliable completion for full enrichment pipeline

**Swift 6.1 Concurrency Validation:**
- Actor isolation correct: `BookshelfAIService` remains `actor`
- Response models properly `Sendable` for cross-actor safety
- Conversion logic correctly `nonisolated` (pure function)
- Timeout as immutable `let` property (no data races)

**Architecture:** iOS app → Cloudflare Worker (Gemini 2.5 Flash) → books-api-proxy (RPC enrichment) → Single unified response with confidence scores + metadata

**Background Enrichment Queue:**
- All scanned books automatically queued for additional metadata enrichment
- Uses shared `EnrichmentQueue.shared` (same system as CSV import)
- Silent background processing with progress shown via `EnrichmentProgressBanner`
- See `ScanResultsView.addAllToLibrary()` lines 577-588 for implementation

**See Issue #16 for implementation details and iOS 26 HIG enhancement recommendations.**

**Suggestions Banner (Build 45+):**
- AI-generated or client-fallback actionable guidance
- 9 suggestion types: unreadable_books, low_confidence, edge_cutoff, blurry_image, glare_detected, distance_too_far, multiple_shelves, lighting_issues, angle_issues
- Unified banner UI with Liquid Glass + severity indicators
- Individual "Got it" dismissal pattern
- Templated messages for consistency and localization
- Hybrid approach: AI-first, client-side fallback for reliability

**Key Files:**
- `SuggestionGenerator.swift` - Client-side fallback logic
- `SuggestionViewModel.swift` - Display logic and templated messages
- `ScanResultsView.swift:suggestionsBanner()` - Banner UI component

**Testing Suggestions Banner:**
- Test image with issues: `docs/testImages/IMG_0014.jpeg` (2 unreadable books)
- Should trigger "unreadable_books" suggestion
- Test image quality: Clear image → no suggestions

### CSV Import & Enrichment System

**Key Files:** `CSVParsingActor.swift`, `CSVImportService.swift`, `EnrichmentService.swift`, `EnrichmentQueue.swift`, `CSVImportFlowView.swift`

**Quick Start:**
```swift
// SettingsView
Button("Import CSV Library") { showingCSVImport = true }
    .sheet(isPresented: $showingCSVImport) { CSVImportFlowView() }
```

**Performance:** 100 books/min, <200MB memory (1500+ books), 95%+ duplicate detection, 90%+ enrichment success

**Format Support:** Goodreads, LibraryThing, StoryGraph (auto-detects columns)

**Architecture:** CSV → `CSVParsingActor` (@globalActor) → `CSVImportService` → SwiftData → `EnrichmentQueue` (@MainActor) → `EnrichmentService` → Cloudflare Worker

**🎉 Enrichment Progress Banner (Build 45+):**
- NotificationCenter-based (NO Live Activity entitlements!)
- Real-time progress: "Enriching Metadata... 15/100 (15%)"
- Theme-aware gradient, pulsing icon, WCAG AA compliant
- Files: `ContentView.swift` (lines 9-12, 65-96, 272-365), `EnrichmentQueue.swift` (lines 174-179, 210-219, 235-239)

**Queue Self-Cleaning:**
- Startup validation removes stale persistent IDs
- Graceful handling skips deleted works
- See `docs/archive/csvMoon-implementation-notes.md` for details

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
├── 📄 CLAUDE.md                      ← Main development guide (this file)
├── 📄 MCP_SETUP.md                   ← XcodeBuildMCP configuration & workflows
├── 📄 README.md                      ← Quick start & project overview
├── 📄 CHANGELOG.md                   ← Version history & releases
├── 📄 APIcall.md                     ← API endpoint migration guide
├── 📄 REALDEVICE_FIXES.md            ← Real device debugging notes (Oct 2025)
├── 📄 FUTURE_ROADMAP.md             ← Aspirational features
├── 📁 docs/archive/
│   ├── 📄 cache3-openlibrary-migration.md     ← Cache strategy (implemented)
│   ├── 📄 csvMoon-implementation-notes.md     ← CSV import roadmap
│   └── 📄 ARCHIVE_PHASE1_AUDIT_REPORT.md      ← Historical audit (resolved)
├── 📁 .claude/commands/              ← Custom slash commands
│   ├── 📄 gogo.md                    ← App Store validation pipeline (MCP-powered)
│   ├── 📄 build.md                   ← Quick build check
│   ├── 📄 test.md                    ← Swift test suite runner
│   ├── 📄 device-deploy.md           ← Physical device deployment
│   └── 📄 sim.md                     ← Simulator launch & debug
└── 📁 cloudflare-workers/
    ├── 📄 README.md                  ← Backend architecture
    └── 📄 SERVICE_BINDING_ARCHITECTURE.md ← RPC technical docs
```

**Documentation Philosophy:**
- CLAUDE.md: Current development standards and patterns
- CHANGELOG.md: Historical achievements and version notes
- FUTURE_ROADMAP.md: Clearly marked as aspirational
- Keep active docs under 500 lines - move history to CHANGELOG

**Implementation Plans & Future Work:**
- **GitHub Issues**: Active tasks tracked at https://github.com/users/jukasdrj/projects/2
- **Labels**: type/plan, type/feature, type/decision, status/backlog, status/archived
- **Migration Note**: Former docs/plans/ content migrated to GitHub Issues (Oct 2025)

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

**Current Focus:** Real device validation, bookshelf scanner beta testing

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
