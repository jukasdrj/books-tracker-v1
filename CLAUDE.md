# 📚 CLAUDE.md
```
    ██████╗  ██████╗  ██████╗ ██╗  ██╗███████╗
    ██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝██╔════╝
    ██████╔╝██║   ██║██║   ██║█████╔╝ ███████╗
    ██╔══██╗██║   ██║██║   ██║██╔═██╗ ╚════██║
    ██████╔╝╚██████╔╝╚██████╔╝██║  ██╗███████║
    ╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝
    ████████╗██████╗  █████╗  ██████╗██╗  ██╗███████╗██████╗
    ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
       ██║   ██████╔╝███████║██║     █████╔╝ █████╗  ██████╔╝
       ██║   ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
       ██║   ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║
       ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
```

Hey there! 👋 Welcome to the BooksTracker project docs. This file is your friendly guide to working with Claude Code in this codebase. Think of it as your trusty companion for navigating this Swift wonderland! ✨

## Project Overview

This is a **BooksTracker** iOS application built with **Swift 6.1+** and **SwiftUI**, targeting **iOS 26.0+**. The app tracks personal book libraries with cultural diversity insights. It uses a **workspace + Swift Package Manager (SPM)** architecture for clean separation between the app shell and feature code.

### Core Technologies
- **SwiftUI** for UI with native state management (@State, @Observable, @Environment)
- **SwiftData** for persistence with CloudKit sync enabled
- **Swift Concurrency** (async/await, @MainActor) with strict mode
- **Swift Testing** framework (not XCTest) with @Test macros and #expect assertions
- **iOS 26 Liquid Glass** design system (forward-compatible with iOS 18+)

### Project Structure
```
BooksTracker/
├── BooksTracker.xcworkspace/              # ✅ Open this in Xcode
├── BooksTracker.xcodeproj/                # App shell project
├── BooksTracker/                          # App target (minimal entry point)
│   ├── BooksTrackerApp.swift              # @main app entry, SwiftData setup
│   └── Assets.xcassets/                   # App-level assets
├── BooksTrackerPackage/                   # 🚀 PRIMARY DEVELOPMENT AREA
│   ├── Package.swift                      # SPM configuration
│   ├── Sources/BooksTrackerFeature/       # All feature code goes here
│   └── Tests/BooksTrackerFeatureTests/    # Swift Testing tests
├── cloudflare-workers/                    # 🌩️ Backend API & cache system
│   ├── books-api-proxy/                   # Multi-provider book search API
│   ├── personal-library-cache-warmer/     # Intelligent cache warming
│   └── isbndb-biography-worker/           # Author biography service
├── Config/                                # Build configuration
│   ├── Shared.xcconfig                    # Bundle ID, versions, deployment target
│   └── BooksTracker.entitlements          # App capabilities (CloudKit enabled)
├── Scripts/                               # 🛠️ Build & release automation
│   ├── update_version.sh                  # Smart version management
│   ├── release.sh                         # One-click releases
│   ├── setup_hooks.sh                     # Git hook installer
│   └── pre_build_version.sh               # Auto-version on build
├── .githooks/                             # 🪝 Git automation hooks
│   └── pre-commit                         # Auto-updates build numbers
└── BooksTrackerUITests/                   # UI automation tests
```

## Versioning & Release Management

### 🤖 Automated Versioning System
The project now has some seriously slick automation! 🎯 No more manual version bumping or forgetting to update build numbers:

```bash
# Quick version updates
./Scripts/update_version.sh patch          # 1.0.0 → 1.0.1
./Scripts/update_version.sh minor          # 1.0.0 → 1.1.0
./Scripts/update_version.sh major          # 1.0.0 → 2.0.0
./Scripts/update_version.sh build          # Update build number only
./Scripts/update_version.sh auto           # Auto-detect from git tags

# Complete release workflow
./Scripts/release.sh patch "Bug fixes"     # Creates tag, commits, ready to push
./Scripts/release.sh minor "New features"  # Major.Minor.Patch release

# Setup automated hooks (run once & forget!)
./Scripts/setup_hooks.sh                   # Auto-updates build on commits 🪝
```

**Version Configuration**: All versions are managed in `Config/Shared.xcconfig`:
- `MARKETING_VERSION`: User-facing version (1.2.3)
- `CURRENT_PROJECT_VERSION`: Build number (auto-generated from git) ✨

**Git Integration**: Build numbers auto-increment based on commit count, ensuring unique builds for every commit. The pre-commit hook automatically updates build numbers so you never have to think about it! 🧠

## Development Commands

### Building and Running
Use XcodeBuildMCP tools for all build operations:

```javascript
// List available simulators
list_sims({})

// Build for simulator
build_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 17 Pro"
})

// Build and run in one step
build_run_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 17 Pro"
})

// Clean build
clean({
    workspacePath: "/path/to/BooksTracker.xcworkspace"
})
```

### Testing
```javascript
// Run Swift Package tests
swift_package_test({
    packagePath: "/path/to/BooksTrackerPackage"
})

// Run full test suite on simulator
test_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 17 Pro"
})
```

### Device Testing
```javascript
// List connected devices
list_devices()

// Build for device
build_device({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker"
})

// Install and run on device
install_app_device({
    deviceId: "DEVICE_UUID",
    appPath: "/path/to/BooksTracker.app"
})
```

### Cloudflare Workers (Backend)
The backend system is managed through npm scripts and Wrangler CLI:

```bash
# 🚀 Quick start - all workers
npm run dev              # Start local development
npm run deploy           # Deploy all workers to production
npm run test             # Run worker tests

# 📊 Individual worker management
cd cloudflare-workers/books-api-proxy
wrangler tail --format pretty           # Real-time logs
wrangler publish                        # Deploy this worker

cd cloudflare-workers/personal-library-cache-warmer
wrangler tail --search "Processing author"  # Monitor cache warming
wrangler publish                            # Deploy cache warmer

# 🔍 Monitoring & debugging
wrangler kv:namespace list               # Check KV stores
wrangler r2 bucket list                  # Check R2 storage
```

**Pro tip**: The cache system runs automatically, but you can monitor it in real-time with `wrangler tail`! 👀

## Architecture & Data Models

### Core Data Models (SwiftData)
The app uses a **properly normalized** SwiftData schema with four main entities:

- **Work**: Represents a creative work (book/novel) with title, authors, publication year
- **Edition**: Specific published editions of a work (ISBN, publisher, format, page count)
- **Author**: Author information with cultural diversity metadata (gender, region)
- **UserLibraryEntry**: User's relationship to a work (reading status, progress, ratings)

### 🚀 Recent Implementation Updates (v1.1+)

#### Edition Metadata System
- **EditionMetadataView**: iOS 26 Liquid Glass metadata card with interactive components
- **WorkDetailView**: Immersive book detail screen with blurred cover background
- **Navigation Integration**: NavigationLink wrapping for all library layouts
- **Context Menus**: Rich interaction with status change submenus and quick rating

#### Key Components Added
- **StarRatingView**: Interactive 5-star rating with haptic feedback ⭐
- **ReadingStatusPicker**: Modal picker for reading status changes
- **NotesEditorView**: Full-screen notes editing with TextEditor 📝
- **Enhanced Context Menus**: Status changes, rating, and library management

#### 🛠️ DevOps & Automation (Latest!)
- **Complete Build Automation**: Smart versioning scripts that Just Work™
- **Git Hooks**: Auto-updating build numbers on every commit
- **Release Scripts**: One-command releases with tagging and changelog support
- **Version Management**: Semantic versioning with git-based build numbers

### Key Relationships
```
Work 1:many Edition (Work can have multiple editions)
Work many:many Author (Works can have multiple authors, authors can write multiple works)
Work 1:many UserLibraryEntry (User can have multiple entries per work - owned + wishlist)
UserLibraryEntry many:1 Edition (Entry links to specific edition when owned)
```

### Cultural Diversity Features
The app tracks cultural diversity in reading habits:
- **AuthorGender**: female, male, nonBinary, other, unknown
- **CulturalRegion**: africa, asia, europe, northAmerica, southAmerica, oceania, middleEast, caribbean, centralAsia, indigenous, international
- **Marginalized Voice Detection**: Built-in logic to identify underrepresented authors

## SwiftUI Architecture Pattern

### Pure SwiftUI State Management (No ViewModels)
The app follows modern SwiftUI patterns without ViewModels:

- **@State**: For view-specific state and model objects
- **@Observable**: For making model classes observable (replaces ObservableObject)
- **@Environment**: For dependency injection (ThemeStore, ModelContext)
- **@Binding**: For two-way data flow between parent/child views

### Example State Management
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
        .task {  // ✅ Use .task for async work - auto-cancels
            await dataService.loadData()
        }
    }
}
```

## iOS 26 Liquid Glass Design System

The app implements forward-compatible **iOS 26 Liquid Glass** effects that gracefully degrade on iOS 17-25:

### Theme System
- **iOS26ThemeStore**: @Observable class managing app-wide theming
- **5 Built-in Themes**: liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver
- **Cultural Color Mapping**: Theme-aware colors for different cultural regions
- **Glass Effects**: Themed glass tinting with cultural variants

### Key Components
- **GlassEffectContainer**: Base container with glass effects
- **iOS26AdaptiveBookCard**: Book cards with liquid glass styling
- **iOS26FluidGridSystem**: Responsive grid layouts
- **Theme-aware Modifiers**: `.themedBackground()`, `.themedGlass()`, `.culturalGlass()`

## Code Quality Standards

### Swift Conventions
- **Naming**: UpperCamelCase for types, lowerCamelCase for properties/functions
- **Optionals**: Use `guard let`/`if let` - avoid force unwrapping
- **Early Returns**: Prefer early return over nested conditionals
- **Value Types**: Use `struct` for models, `class` only for reference semantics

### Concurrency Requirements
- **@MainActor**: All UI updates must use @MainActor isolation
- **Swift Concurrency Only**: No GCD usage - use async/await, actors, Task
- **.task Modifier**: Always use `.task {}` on views for async operations (auto-cancels)
- **Sendable Conformance**: All types crossing concurrency boundaries must be Sendable

### Testing with Swift Testing
```swift
import Testing
@testable import BooksTrackerFeature

@Test func userCanAddBookToLibrary() async throws {
    let work = Work(title: "Test Book")
    let entry = UserLibraryEntry.createWishlistEntry(for: work)

    #expect(entry.readingStatus == .wishlist)
    #expect(entry.work?.title == "Test Book")
}

@Test("User can track reading progress")
func trackingProgress() async throws {
    // Test implementation
}
```
## Adding New Features

### Development Workflow
1. **Work in BooksTrackerPackage**: All feature development happens in `BooksTrackerPackage/Sources/BooksTrackerFeature/`
2. **Public API**: Types exposed to app target need `public` access and `public init()`
3. **Add Dependencies**: Edit `BooksTrackerPackage/Package.swift` for SPM dependencies
4. **Write Tests**: Add Swift Testing tests in `BooksTrackerPackage/Tests/`

### Adding App Capabilities
Edit `Config/BooksTracker.entitlements` to add capabilities:
```xml
<!-- Enable HealthKit -->
<key>com.apple.developer.healthkit</key>
<true/>

<!-- Enable Push Notifications -->
<key>aps-environment</key>
<string>development</string>
```

### SwiftData Model Changes
When modifying models:
1. Update the model class with @Model
2. Add to schema in `BooksTrackerApp.swift`:
```swift
let schema = Schema([
    Work.self,
    Edition.self,
    Author.self,
    UserLibraryEntry.self,
    // Add new model here
])
```

## Key Business Logic

### Reading Status Workflow
- **Wishlist**: Want to read but don't own → `.wishlist` status, no edition
- **Owned**: Have specific edition → `.toRead`, `.reading`, `.read` status with edition
- **Progress Tracking**: Page-based progress with automatic completion
- **Status Transitions**: Built-in validation and state management

### Cultural Diversity Tracking
- Authors have `representsMarginalizedVoices()` and `representsIndigenousVoices()` methods
- Cultural regions map to theme colors for visual diversity representation
- Reading analytics can be built on cultural metadata

## Architecture Decisions

### Why No ViewModels
The app follows pure SwiftUI patterns because:
- SwiftUI's built-in state management is sufficient for most use cases
- @Observable provides better performance than @Published
- Reduces architectural complexity and testing surface area
- Views remain lightweight and disposable

### Why SwiftData over CoreData
- Type-safe, modern Swift API
- Seamless SwiftUI integration with @Query
- Built-in CloudKit sync with minimal configuration
- Better async/await support

### Why Package-based Architecture
- Clean separation between app shell and business logic
- Improved build times and modularity
- Easier testing of individual components
- Future-proofs for potential multi-target expansion

## 🌩️ Backend System & Recent Victories

### Cloudflare Workers Architecture
The app now includes a robust **multi-worker backend system** that's been battle-tested and is working beautifully! 🎉

```
    🔥 CLOUDFLARE WORKERS ECOSYSTEM 🔥
    ┌─────────────────────────────────────┐
    │  books-api-proxy (The Brain 🧠)     │
    │  ├─ ISBNdb integration             │
    │  ├─ Open Library fallback          │
    │  ├─ Google Books backup            │
    │  └─ NEW: API identifier extraction │
    └─────────────────────────────────────┘
              ↕️ (Service Bindings)
    ┌─────────────────────────────────────┐
    │  personal-library-cache-warmer      │
    │  ├─ Intelligent cache warming       │
    │  ├─ Cron jobs every 15 minutes ⏰   │
    │  └─ Processing 364+ authors! 📚     │
    └─────────────────────────────────────┘
              ↕️ (Service Bindings)
    ┌─────────────────────────────────────┐
    │  isbndb-biography-worker            │
    │  ├─ Author biography enrichment     │
    │  └─ Cultural metadata extraction    │
    └─────────────────────────────────────┘
```

### 🎯 Recent Fixes & Lessons Learned

#### **The Great Service Binding URL Mystery - SOLVED! ✅**
**What went wrong**: Manual cache warming was failing because service bindings were using relative URLs (`/author/andy%20weir`) instead of absolute URLs.

**The "Aha!" moment**: Cron jobs were working fine because they used a different function that correctly constructed absolute URLs! Classic case of "it works in production but not in testing" 😅

**The fix**: Updated API identifier extraction in `books-api-proxy` to include:
- `isbndbID`: From book.id/isbn13/isbn fields
- `openLibraryID`: From doc.key field
- `googleBooksVolumeID`: From item.id field

**Lesson learned**: Always check your service binding URL patterns - Cloudflare Workers are picky about absolute URLs! 🤓

#### **SwiftData Model Sync Enhancement**
The backend now properly extracts API identifiers that perfectly match our new SwiftData model fields:

```swift
// SwiftData model fields now have backend support! 🎉
var openLibraryID: String?      // ✅ Extracted from Open Library
var isbndbID: String?          // ✅ Extracted from ISBNdb
var googleBooksVolumeID: String? // ✅ Extracted from Google Books
```

### 📊 Current System Status
- **Cache entries**: Growing from 7→14+ (system is healthy! 💪)
- **Author processing**: 364 authors loaded and being processed
- **Cron jobs**: Running every 15 minutes like clockwork ⏰
- **API coverage**: 3 providers with intelligent fallbacks

**Pro tip**: The cache system is now self-healing and doesn't need babysitting! 🤖

## 🎉 Recent Achievements & Victory Lap!

### Latest Wins (December 2024)
Based on our recent commits, here's what we've been absolutely crushing lately:

#### **🧠 Super Smart Documentation Updates**
- **The Great Emoji-fication**: Spruced up all our docs with friendly banter and helpful emojis because life's too short for boring documentation! 📚✨
- **Automation Guide Excellence**: Created comprehensive guides for our build automation that actually make sense (revolutionary, we know!)
- **Version Target Updates**: Bumped from iOS 17→26 targeting because we're forward-thinking like that! 🚀

#### **🎯 Navigation Conflicts - CONQUERED!**
Here's the tea on our recent SwiftUI wrestling match:

**The Problem**: Navigation was being a drama queen across all our library layout views. Classic SwiftUI gesture confusion! 😤

**The Investigation**: Spent quality time debugging why our beautiful book cards weren't playing nice with NavigationLink. Turns out gesture recognizers were having territorial disputes.

**The Victory**:
- Fixed gesture conflicts in `iOS26FloatingBookCard` ✅
- Preserved all the fancy context menus and animations ✅
- Navigation now works flawlessly across ALL library views ✅
- User experience is now buttery smooth! 🧈

**Lesson Learned**: SwiftUI gestures need couples therapy sometimes. When in doubt, simplify the gesture stack! 🤝

#### **⚡ Backend Infrastructure Dominance**
Our Cloudflare Workers ecosystem is now running like a Swiss watch:

- **API Identifier Sync**: Perfect harmony between our SwiftData models and backend API extraction
- **Cache System Reliability**: From broken manual warming to rock-solid automation
- **Multi-Provider Resilience**: ISBNdb → Open Library → Google Books fallbacks working flawlessly
- **Real-time Monitoring**: `wrangler tail` gives us god-mode visibility into everything

**Current Stats That Make Us Happy**:
- 🏃‍♂️ Processing 364+ authors automatically
- 📈 Cache entries growing healthy (7→14+)
- ⏰ Cron jobs humming every 15 minutes
- 🛡️ Self-healing when things go sideways

#### **🛠️ Developer Experience Excellence**
We've basically become automation wizards:

- **One-Command Everything**: `./Scripts/release.sh` handles versioning, tagging, commits - chef's kiss! 👌
- **Git Hooks Magic**: Build numbers update automatically on every commit (set it and forget it!)
- **iPhone 17 Pro Ready**: Updated all our simulator examples because we stay current! 📱

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
        .task {  // ✅ Automatically cancels when view disappears
            await loadBooks()
        }
        .refreshable {  // ✅ Pull-to-refresh with async
            await refreshBooks()
        }
    }
}
```

This architecture emphasizes simplicity, modern Swift patterns, and forward compatibility while maintaining clean separation of concerns through the SPM package structure.

## 🐛 Known Issues & Troubleshooting

### ✅ Resolved Issues (Hall of Fame!)

#### Navigation Fix (v1.1.1) - RESOLVED 🎉
- **Issue**: NavigationLink taps from book cards to WorkDetailView not triggering
- **Root Cause**: Conflicting gesture recognizers in iOS26FloatingBookCard (classic SwiftUI shenanigans!)
- **Solution**: Removed pressEvents modifier and moved press animations to BookCardButtonStyle
- **Result**: Navigation now works perfectly while preserving context menus and animations
- **Status**: ✅ **FIXED** - Both navigation and context menus working correctly
- **Lesson Learned**: SwiftUI gestures can be... particular about their friendships 🤝

#### Backend Cache System Fix (v1.2) - RESOLVED 🎉
- **Issue**: Manual cache warming failing, but cron jobs working fine (confusing AF!)
- **Root Cause**: Service bindings using relative URLs instead of absolute URLs for manual triggers
- **The Detective Work**: Cron jobs used `callISBNdbWorkerReliable` with correct absolute URLs, while manual warming used broken relative URL pattern
- **Solution**: Enhanced API identifier extraction in `books-api-proxy` to support new SwiftData model fields
- **Result**: Cache system now fully operational with 364+ authors being processed automatically
- **Status**: ✅ **FIXED** - Cache growing from 7→14+ entries, system is self-healing
- **Lesson Learned**: When Cloudflare Workers say they want absolute URLs, they REALLY mean it! 🌩️

### 🚀 Current Status
This project is absolutely crushing it! 💪 Navigation works flawlessly, backend cache system is humming along processing hundreds of authors, the automation scripts handle all version management, and the iOS 26 Liquid Glass theming looks stunning. Plus our multi-worker Cloudflare backend is now battle-tested and rock-solid!

**Pro tip**: If you run into any weird build issues, try the clean command first - it fixes 90% of Xcode's mood swings! 😅

### Debugging Commands

#### iOS App Debugging
```javascript
// Test app with logs
launch_app_logs_sim({
    simulatorUuid: "SIMULATOR_UUID",
    bundleId: "com.bookstrack.BooksTracker"
})

// Capture UI hierarchy for debugging
describe_ui({ simulatorUuid: "SIMULATOR_UUID" })
```

#### Backend System Debugging
```bash
# 📡 Real-time monitoring (the good stuff!)
cd cloudflare-workers/personal-library-cache-warmer
wrangler tail --format pretty --search "Processing author"  # Watch authors being processed
wrangler tail --format pretty --search "ERROR"              # Hunt down errors

cd cloudflare-workers/books-api-proxy
wrangler tail --format pretty                               # Monitor API requests

# 🔍 System health checks
curl "books-api-proxy.jukasdrj.workers.dev/health"         # API proxy health
curl "personal-library-cache-warmer.jukasdrj.workers.dev/health"  # Cache warmer health

# 📊 Cache inspection
wrangler kv:key list --namespace-id YOUR_KV_NAMESPACE      # See what's cached
```

**Debug like a pro**: Use `wrangler tail` with search filters to zero in on specific issues! 🎯