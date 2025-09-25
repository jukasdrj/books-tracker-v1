# BooksTracker Code Style & Conventions

## Swift Naming Conventions
- **Types**: UpperCamelCase (Work, ContentView, AuthorGender)
- **Properties/Functions**: lowerCamelCase (primaryAuthor, addAuthor(_:))
- **Constants**: lowerCamelCase (dateCreated, lastModified)

## SwiftUI Architecture Pattern - NO ViewModels
- **@State**: For view-specific state and model objects
- **@Observable**: For making model classes observable (replaces ObservableObject)
- **@Environment**: For dependency injection (ThemeStore, ModelContext)
- **@Binding**: For two-way data flow between parent/child views

## Concurrency Requirements
- **@MainActor**: ALL UI updates must use @MainActor isolation
- **Swift Concurrency Only**: NO GCD usage - use async/await, actors, Task
- **.task Modifier**: ALWAYS use `.task {}` on views for async operations (auto-cancels)
- **Sendable Conformance**: All types crossing concurrency boundaries must be Sendable

## SwiftData Model Patterns
- **@Model** annotation for data classes
- **@Relationship** with proper deleteRule and inverse relationships
- **Public init()** for types exposed to app target
- **Touch methods** for updating lastModified timestamps

## File Organization
- **Public Access**: Types exposed to app need `public` access and `public init()`
- **Helper Methods**: Group with `// MARK: - Section Name` comments
- **Extension Organization**: Related functionality in extensions

## Error Handling
- **Guard Statements**: Prefer `guard let`/`if let` over force unwrapping
- **Early Returns**: Prefer early return over nested conditionals
- **Optional Chaining**: Use safely rather than force unwrapping

## UI Patterns
- **Value Types**: Use `struct` for models, `class` only for reference semantics
- **Theme System**: Use iOS26ThemeStore for consistent theming
- **Glass Effects**: Apply themed glass modifiers for iOS 26 design