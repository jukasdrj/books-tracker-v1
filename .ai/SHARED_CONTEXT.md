# 📚 BooksTracker - Shared AI Context

This document contains project-wide context for all AI development tools.

## Core Stack
- SwiftUI + @Observable + SwiftData + CloudKit sync
- Swift 6.1 concurrency (@MainActor, actors, typed throws)
- Swift Testing (@Test, #expect, parameterized tests)
- iOS 26 Liquid Glass design system
- Cloudflare Workers (RPC service bindings, Durable Objects, KV/R2)

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

**🚨 CRITICAL: SwiftData Persistent Identifier Lifecycle**

SwiftData objects go through two ID states:
1. **Temporary ID** - Assigned by `modelContext.insert()` (in-memory only)
2. **Permanent ID** - Assigned by `modelContext.save()` (persisted to disk)

**NEVER use `persistentModelID` before calling `save()`!**

```swift
// ❌ WRONG: Using ID before save() - CRASH!
let work = Work(title: "...")
modelContext.insert(work)  // Assigns TEMPORARY ID
let id = work.persistentModelID  // ❌ Still temporary!
// Later when enrichment tries to use this ID:
// Fatal error: "Illegal attempt to create a full future for a temporary identifier"

// ✅ CORRECT: Save BEFORE capturing IDs
let work = Work(title: "...")
modelContext.insert(work)
work.authors = [author]  // Relationships use temporary IDs (OK)
try modelContext.save()  // IDs become PERMANENT
let id = work.persistentModelID  // ✅ Now safe to use!
```

**Insert-Before-Relate Rule:**
```swift
// ❌ WRONG: Setting relationship during initialization
let work = Work(title: "...", authors: [author])  // Crash!
modelContext.insert(work)

// ✅ CORRECT: Insert BEFORE setting relationships
let author = Author(name: "...")
modelContext.insert(author)

let work = Work(title: "...", authors: [])
modelContext.insert(work)
work.authors = [author]  // Set relationship AFTER both are inserted
```

**Rules:**
1. Always `insert()` immediately after creating models
2. Set relationships AFTER both objects are inserted
3. Call `save()` before using `persistentModelID` for anything (enrichment queue, notifications, etc.)
4. Temporary IDs cannot be used for futures, deduplication, or background tasks

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

### Swift 6.2 Concurrency

**Actor Isolation:**
- `@MainActor` - UI components, SwiftUI views
- `@CameraSessionActor` - Camera/AVFoundation
- `nonisolated` - Pure functions, initialization

**🚨 BAN `Timer.publish` in Actors:**
- Use `await Task.sleep(for:)` instead
- Combine doesn't integrate with Swift 6 actor isolation

### Backend Architecture

**Worker:** `api-worker` (Cloudflare Worker monolith)

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
