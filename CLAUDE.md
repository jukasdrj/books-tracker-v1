# 📚 BooksTracker - Claude Code Guide

**Version 1.9+** | **iOS 26.0+** | **Swift 6.1+** | **Updated: October 2025**

This is a personal book tracking iOS app with cultural diversity insights, built with SwiftUI, SwiftData, and a Cloudflare Workers backend.

## Quick Start

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

**iOS Development:**
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

**API Endpoint:** `https://books-api-proxy.jukasdrj.workers.dev/search/auto`

**Architecture Rule:** Workers communicate via RPC service bindings - **never** direct API calls from proxy worker. Always orchestrate through specialized workers.

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

### iOS 26 HIG Compliance

**Search Pattern (100% HIG Compliant):**
```swift
.searchable(
    text: $searchModel.searchText,
    placement: .navigationBarDrawer(displayMode: .always),
    prompt: "Search books, authors, or ISBN"
)
.searchScopes($searchScope) {
    ForEach(SearchScope.allCases) { scope in
        Text(scope.rawValue).tag(scope)
    }
}
.focused($isSearchFocused)  // Explicit keyboard control
```

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

### Barcode Scanning Integration

**Key Files:**
- `ISBNValidator.swift` - ISBN-10/13 validation with checksum
- `CameraManager.swift` - Actor-isolated camera management
- `BarcodeDetectionService.swift` - AsyncStream detection
- `ModernBarcodeScannerView.swift` - Complete scanner UI

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

**❌ WRONG - Custom "Accessible" Colors (Don't do this!):**
```swift
// These custom colors DON'T adapt to glass backgrounds!
Text("Author Name")
    .foregroundColor(themeStore.accessibleSecondaryText)  // White with opacity = invisible!
```

**✅ CORRECT - System Semantic Colors:**
```swift
// System colors automatically adapt to backgrounds
Text("Author Name")
    .foregroundColor(.secondary)  // Auto-adapts to glass material ✨

Text("Publisher")
    .foregroundColor(.secondary)  // Always readable!

Text("Page Count")
    .foregroundColor(.secondary)  // WCAG AA compliant!
```

**The Hard-Learned Lesson:**
- Custom theme colors are great for accents and primary UI
- **But secondary/tertiary text should ALWAYS use system semantic colors**
- `.secondary` adapts to `.ultraThinMaterial` glass backgrounds
- Custom opacity values (0.75, 0.85) create illegible text on light glass
- Don't reinvent the wheel - Apple's got this covered! 🍎

**When to use what:**
- `themeStore.primaryColor` → Buttons, icons, highlights
- `themeStore.secondaryColor` → Gradients, subtle accents
- `.secondary` → **ALL metadata text** (authors, publishers, dates, etc.)
- `.primary` → Headlines, titles, main content

## Documentation Structure

```
📁 Root Directory
├── 📄 CLAUDE.md                      ← Main development guide (this file)
├── 📄 README.md                      ← Quick start & project overview
├── 📄 CHANGELOG.md                   ← Version history & releases
├── 📄 cache3.md                      ← Cache strategy (implemented)
├── 📄 FUTURE_ROADMAP.md             ← Aspirational features
├── 📄 ARCHIVE_PHASE1_AUDIT_REPORT.md ← Historical audit (resolved)
└── 📁 cloudflare-workers/
    ├── 📄 README.md                  ← Backend architecture
    └── 📄 SERVICE_BINDING_ARCHITECTURE.md ← RPC technical docs
```

**Documentation Philosophy:**
- CLAUDE.md: Current development standards and patterns
- CHANGELOG.md: Historical achievements and version notes
- FUTURE_ROADMAP.md: Clearly marked as aspirational
- Keep active docs under 500 lines - move history to CHANGELOG

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

## 🎨 Recent Victories

### **✨ The Accessibility Revolution (Oct 2025)**

```
╔═══════════════════════════════════════════════════════════╗
║  🌈 FROM WCAG VIOLATIONS TO PERFECT CONTRAST! 🎯        ║
║                                                           ║
║  📊 Phase 1: Critical Fixes (4 files, 30 instances)     ║
║     ✅ EditionMetadataView.swift (Book Details!)         ║
║     ✅ iOS26AdaptiveBookCard.swift                       ║
║     ✅ iOS26LiquidListRow.swift                          ║
║                                                           ║
║  📊 Phase 2: Moderate Fixes (7 files, 44 instances)     ║
║     ✅ SearchView.swift                                  ║
║     ✅ AdvancedSearchView.swift                          ║
║     ✅ SettingsView.swift                                ║
║     ✅ ContentView.swift + CloudKitHelpView + more       ║
║                                                           ║
║  🎯 Result: 2.1:1 contrast → 4.5:1+ WCAG AA! ✨         ║
╚═══════════════════════════════════════════════════════════╝
```

**The Problem:** Gray text (`.secondary`) gave 2.1-2.8:1 contrast on warm themes - barely readable! 😱

**The Solution:**
- Added `accessiblePrimaryText`, `accessibleSecondaryText`, `accessibleTertiaryText` to iOS26ThemeSystem
- Dynamic opacity based on theme warmth (85% for warm, 75% for cool)
- Fixed 74 instances across 11 files

**Lesson Learned:** When you only need to check existence, use `if userEntry != nil`, not `if let userEntry = userEntry` - Swift's being smart about unused bindings! 🧠

### **🔍 The Advanced Search Awakening (Oct 2025)**

```
   ╔══════════════════════════════════════════════════════╗
   ║  🚀 FROM CLIENT CHAOS TO BACKEND BRILLIANCE! 🎯    ║
   ║                                                      ║
   ║  ❌ Before: Foreign languages, book sets, chaos    ║
   ║  ✅ After:  Clean, filtered, precise results       ║
   ║                                                      ║
   ║  Architecture: Pure Worker Orchestration            ║
   ╚══════════════════════════════════════════════════════╝
```

**The Journey:**
1. **User reports:** "Andy Weir" advanced search returning wrong languages! 😬
2. **First attempt:** Client-side filtering (wrong approach!)
3. **User wisdom:** "Backend has good filtering - USE IT!" 💡
4. **The Fix:** New `/search/advanced` endpoint with proper RPC

**What We Built:**
- **Backend Endpoint:** `/search/advanced` with multi-field filtering
- **Smart Routing:** ISBN > Author+Title > Single field searches
- **iOS Integration:** `BookSearchAPIService.advancedSearch()` method
- **Clean Architecture:** Zero direct API calls, pure worker orchestration

**Code Pattern:**
```javascript
// Backend filters at the source!
const authorResults = await handleAuthorSearch(authorName, { maxResults: 40 });
const filtered = authorResults.filter(item =>
    item.title.toLowerCase().includes(titleLower)
);
```

**The Wisdom:** When you build a beautiful orchestration system, TRUST IT and USE IT! Don't bypass your own architecture! 🏗️

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

---

**Build Status:** ✅ Zero warnings, zero errors
**HIG Compliance:** 100% iOS 26 standards
**Swift 6:** Full concurrency compliance
**Accessibility:** WCAG AA compliant contrast
