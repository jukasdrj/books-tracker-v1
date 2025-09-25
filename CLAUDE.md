# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **BooksTracker** iOS application built with **Swift 6.1+** and **SwiftUI**, targeting **iOS 17.0+**. The app tracks personal book libraries with cultural diversity insights. It uses a **workspace + Swift Package Manager (SPM)** architecture for clean separation between the app shell and feature code.

### Core Technologies
- **SwiftUI** for UI with native state management (@State, @Observable, @Environment)
- **SwiftData** for persistence with CloudKit sync enabled
- **Swift Concurrency** (async/await, @MainActor) with strict mode
- **Swift Testing** framework (not XCTest) with @Test macros and #expect assertions
- **iOS 26 Liquid Glass** design system (forward-compatible with iOS 17+)

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
├── Config/                                # Build configuration
│   ├── Shared.xcconfig                    # Bundle ID, versions, deployment target
│   └── BooksTracker.entitlements          # App capabilities (CloudKit enabled)
└── BooksTrackerUITests/                   # UI automation tests
```

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
    simulatorName: "iPhone 16"
})

// Build and run in one step
build_run_sim({
    workspacePath: "/path/to/BooksTracker.xcworkspace",
    scheme: "BooksTracker",
    simulatorName: "iPhone 16"
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
    simulatorName: "iPhone 16"
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

## Architecture & Data Models

### Core Data Models (SwiftData)
The app uses a **properly normalized** SwiftData schema with four main entities:

- **Work**: Represents a creative work (book/novel) with title, authors, publication year
- **Edition**: Specific published editions of a work (ISBN, publisher, format, page count)
- **Author**: Author information with cultural diversity metadata (gender, region)
- **UserLibraryEntry**: User's relationship to a work (reading status, progress, ratings)

### Recent Implementation Updates (v1.1)

#### Edition Metadata System
- **EditionMetadataView**: iOS 26 Liquid Glass metadata card with interactive components
- **WorkDetailView**: Immersive book detail screen with blurred cover background
- **Navigation Integration**: NavigationLink wrapping for all library layouts
- **Context Menus**: Rich interaction with status change submenus and quick rating

#### Key Components Added
- **StarRatingView**: Interactive 5-star rating with haptic feedback
- **ReadingStatusPicker**: Modal picker for reading status changes
- **NotesEditorView**: Full-screen notes editing with TextEditor
- **Enhanced Context Menus**: Status changes, rating, and library management

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

## Known Issues & Troubleshooting

### Navigation Issues (v1.1)
- **Book Card Navigation**: NavigationLink taps from book cards to WorkDetailView not triggering
- **Context Menus**: Working correctly with proper haptic feedback
- **Symptoms**: Taps on book cards don't navigate, but long-press context menus function
- **Status**: Under investigation - may be related to button layering or gesture conflicts

### Debugging Commands
```javascript
// Test app with logs
launch_app_logs_sim({
    simulatorUuid: "SIMULATOR_UUID",
    bundleId: "com.bookstrack.BooksTracker"
})

// Capture UI hierarchy for debugging
describe_ui({ simulatorUuid: "SIMULATOR_UUID" })
```