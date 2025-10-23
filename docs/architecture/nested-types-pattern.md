# Nested Types Pattern

**Created:** October 22, 2025
**Status:** Active Standard
**Context:** CSV Import Build Failures Fix

---

## Principle

Supporting types that belong to a specific service or feature should be nested inside their primary class to establish clear ownership, prevent namespace pollution, and make concurrency boundaries explicit.

---

## The Problem This Solves

### Before: Module-Level Type Chaos

```swift
// DuplicateStrategy.swift
public enum DuplicateStrategy: Sendable {
    case skip, update, addNew, smart
}

// ImportResult.swift
public struct ImportResult: Sendable {  // ❌ VIOLATION!
    let importedWorks: [Work]  // Work is @Model (reference type)
}

// CSVImportService.swift
public class CSVImportService {
    func importCSV(strategy: DuplicateStrategy) {
        // Which DuplicateStrategy? (ambiguous if multiple exist)
    }
}

// Usage site confusion:
let strategy: DuplicateStrategy = .smart
// ❌ Compiler: 'DuplicateStrategy' is ambiguous
// Is this CSV's strategy? JSON's? XML's?

// References expect nested type:
let service = CSVImportService()
let result: CSVImportService.ImportResult = ...
// ❌ Compiler error: 'ImportResult' is not a member type of 'CSVImportService'
```

**Issues:**
1. **Namespace Pollution**: Every type competes in the global module namespace
2. **Ambiguous References**: Multiple features might define similar types (ImportResult, DuplicateStrategy, etc.)
3. **Unclear Ownership**: No way to know which service uses which types
4. **Type Mismatch Errors**: Compiler expects nested types when you reference `ServiceName.TypeName`

### After: Clear Ownership with Nested Types

```swift
@MainActor
public class CSVImportService {
    public func importCSV(
        strategy: DuplicateStrategy,  // Unambiguous - nested type
        onProgress: (ImportProgress) -> Void
    ) async -> ImportResult {
        // Implementation...
    }

    // MARK: - Supporting Types

    public enum DuplicateStrategy: Sendable {
        case skip, update, addNew, smart
    }

    public struct ImportResult {  // ✅ No Sendable - contains @Model
        let successCount: Int
        let importedWorks: [Work]  // Work is SwiftData @Model
    }

    public struct ImportProgress: Sendable {
        let current: Int
        let total: Int
    }
}

// Usage site clarity:
let strategy: CSVImportService.DuplicateStrategy = .smart  // ✅ Clear ownership
let result: CSVImportService.ImportResult = ...            // ✅ Exact match
```

**Benefits:**
1. **Clear Ownership**: `CSVImportService.DuplicateStrategy` shows relationship at call site
2. **No Namespace Conflicts**: Each service has its own type namespace
3. **Discoverability**: Xcode autocomplete shows types when typing `CSVImportService.`
4. **Compiler Safety**: Type references match definition location exactly

---

## Examples

### ✅ Good: Nested Types

```swift
public class SearchService {
    public func search(scope: SearchScope) async -> SearchResult {
        // Implementation...
    }

    // MARK: - Supporting Types

    public enum SearchScope: String, Sendable, CaseIterable {
        case all = "All"
        case title = "Title"
        case author = "Author"
        case isbn = "ISBN"
    }

    public struct SearchResult {
        let query: String
        let items: [SearchResultItem]
        let hasMorePages: Bool
    }

    public struct SearchResultItem: Identifiable {
        let id: UUID
        let title: String
        let authors: [String]
    }
}

// Usage:
let scope: SearchService.SearchScope = .title
let result: SearchService.SearchResult = await service.search(scope: scope)
```

### ❌ Bad: Module-Level Types

```swift
// SearchScope.swift (separate file)
public enum SearchScope: String, CaseIterable {
    case all, title, author, isbn
}

// SearchResult.swift (separate file)
public struct SearchResult {
    let items: [SearchResultItem]
}

// SearchService.swift
public class SearchService {
    func search(scope: SearchScope) -> SearchResult {
        // Which SearchScope? (ambiguous if JSON search also has SearchScope)
        // Which SearchResult? (ambiguous if CSV export has SearchResult)
    }
}
```

**Why This Is Bad:**
- No clear ownership (who owns SearchScope? SearchService? SearchView? Both?)
- Namespace pollution (every feature competes for type names)
- Discoverability issues (can't find types via service autocomplete)
- Ambiguity errors when multiple features use similar names

---

## When to Use Nested Types

### ✅ Nest These:

1. **Service-Specific Enums**
   ```swift
   class CSVImportService {
       enum DuplicateStrategy { ... }  // Only CSV import uses this
       enum ValidationError { ... }    // CSV-specific errors
   }
   ```

2. **Operation-Specific Result Types**
   ```swift
   class BookshelfScanService {
       struct ScanResult { ... }       // Only scanning produces this
       struct DetectedBook { ... }     // Scan-specific data
   }
   ```

3. **Service Configuration**
   ```swift
   class CacheService {
       struct CacheConfig { ... }      // Cache-specific settings
       enum CachePolicy { ... }        // Cache-specific behavior
   }
   ```

4. **Progress/Status Types**
   ```swift
   class EnrichmentService {
       struct EnrichmentProgress { ... }
       enum EnrichmentStatus { ... }
   }
   ```

### ❌ Don't Nest These:

1. **Domain Models** (used across entire app)
   ```swift
   // ✅ GOOD: Module-level (used by many features)
   @Model public class Work { ... }
   @Model public class Edition { ... }
   @Model public class Author { ... }
   ```

2. **Shared Protocols** (meant for broad adoption)
   ```swift
   // ✅ GOOD: Module-level (many types conform)
   public protocol Identifiable { ... }
   public protocol Cacheable { ... }
   ```

3. **Cross-Feature Types** (used by multiple unrelated features)
   ```swift
   // ✅ GOOD: Module-level (CSV, JSON, XML all use this)
   public enum ImportFormat {
       case csv, json, xml
   }
   ```

4. **Extension Targets** (types you want others to extend)
   ```swift
   // ✅ GOOD: Module-level (extensions can't extend nested types easily)
   public struct ISBN {
       var value: String
   }

   extension ISBN: Codable { ... }  // Easy to extend
   ```

---

## Swift 6 Sendable Considerations

### Rule: Sendable Depends on Contents

```swift
public class DataService {
    // ✅ Sendable: Contains only value types
    public struct Config: Sendable {
        let timeout: Int
        let retryCount: Int
        let baseURL: URL
    }

    // ✅ NOT Sendable: Contains SwiftData @Model (reference type)
    public struct Result {  // No Sendable conformance
        let items: [Work]   // Work is @Model
        let total: Int
    }

    // ⚠️ @unchecked: Requires documentation
    /// SAFETY: SearchResult is immutable after creation and only consumed on @MainActor.
    /// Work/Edition/Author references are read-only from SearchResult's perspective.
    public struct SearchResult: @unchecked Sendable {
        let work: Work
        let editions: [Edition]
        let authors: [Author]
    }
}
```

### SwiftData + Sendable Violations

**The Rule:** SwiftData @Model classes are reference types and NOT Sendable. Never claim Sendable for types containing them.

```swift
// ❌ BAD: Sendable violation
public struct ImportResult: Sendable {
    let importedWorks: [Work]  // Work is @Model (reference type)
    // Compiler error: Stored property 'importedWorks' of 'Sendable'-conforming
    // struct 'ImportResult' has non-sendable type '[Work]'
}

// ✅ GOOD: No Sendable - use @MainActor instead
@MainActor
public class CSVImportService {
    public struct ImportResult {  // No Sendable
        let importedWorks: [Work]
        // Safe: Only used on @MainActor
    }
}
```

**Why This Matters:**
- SwiftData models are classes (reference types) managed by `ModelContext`
- `ModelContext` is NOT thread-safe (MainActor-only)
- Claiming Sendable would allow cross-actor passing → data races
- Use `@MainActor` isolation instead for UI-bound types

### When to Use @unchecked Sendable

Only use `@unchecked Sendable` when:

1. **Immutable After Creation**: Object never mutates after initialization
2. **MainActor Consumption**: Only accessed on MainActor (UI layer)
3. **Read-Only References**: Reference types are read-only from consumer's perspective
4. **Documented Safety**: Add comment explaining why it's safe

```swift
/// SAFETY: @unchecked Sendable because search results are immutable after creation
/// and only consumed on @MainActor. Work/Edition/Author references are read-only
/// from the perspective of SearchResult consumers. The underlying SwiftData models
/// are accessed via ModelContext on MainActor.
public struct SearchResult: Identifiable, Hashable, @unchecked Sendable {
    public let work: Work
    public let editions: [Edition]
    public let authors: [Author]
}
```

**Documentation Template:**
```swift
/// SAFETY: @unchecked Sendable because:
/// 1. [Why immutable or thread-safe]
/// 2. [Where/how it's consumed]
/// 3. [Why reference types are safe in this context]
```

---

## Migration Checklist

When moving module-level types to nested types:

- [ ] **Move types inside class** (after methods, before closing brace)
- [ ] **Add `// MARK: - Supporting Types`** section comment
- [ ] **Update all references** to use nested syntax (`ServiceName.TypeName`)
- [ ] **Remove Sendable** from types containing @Model objects
- [ ] **Add @MainActor** to class if types are UI-bound
- [ ] **Document @unchecked Sendable** with safety rationale if needed
- [ ] **Update tests** with type aliases or full paths
- [ ] **Verify build** succeeds with zero warnings
- [ ] **Run test suite** to catch reference errors

### Example Migration

**Before:**
```swift
// DuplicateStrategy.swift
public enum DuplicateStrategy: Sendable { ... }

// ImportResult.swift
public struct ImportResult: Sendable {
    let importedWorks: [Work]
}

// CSVImportService.swift
public class CSVImportService {
    func importCSV(strategy: DuplicateStrategy) -> ImportResult { ... }
}
```

**After:**
```swift
// CSVImportService.swift
@MainActor
public class CSVImportService {
    public func importCSV(strategy: DuplicateStrategy) -> ImportResult { ... }

    // MARK: - Supporting Types

    public enum DuplicateStrategy: Sendable {
        case skip, update, addNew, smart
    }

    public struct ImportResult {  // Removed Sendable
        let successCount: Int
        let importedWorks: [Work]
    }
}

// Tests: Add type aliases for convenience
typealias DuplicateStrategy = CSVImportService.DuplicateStrategy
typealias ImportResult = CSVImportService.ImportResult
```

---

## Real-World Example: CSV Import Fix (October 2025)

### The Bug

**Symptoms:**
- 15 compilation errors in `CSVImportFlowView.swift`
- Error: `'DuplicateStrategy' is not a member type of 'CSVImportService'`
- Error: `'ImportResult' is ambiguous without more context`

**Root Cause:**
1. Types defined at module level (after class closing brace)
2. References used nested syntax (`CSVImportService.DuplicateStrategy`)
3. Compiler couldn't match module-level definitions to nested references
4. `ImportResult` claimed Sendable while containing non-Sendable `[Work]`

### The Fix

**Step 1: Move types inside class**
```swift
@MainActor
public class CSVImportService {
    // ... existing methods ...

    // MARK: - Supporting Types
    // (Moved from module level)

    public enum DuplicateStrategy: Sendable { ... }
    public struct ImportResult { ... }  // Removed Sendable
    public struct ImportError: Sendable { ... }
}
```

**Step 2: Update tests**
```swift
// CSVImportTests.swift
import BooksTrackerFeature

typealias DuplicateStrategy = CSVImportService.DuplicateStrategy
typealias ImportResult = CSVImportService.ImportResult

@Test func testSmartDuplicateStrategy() {
    let strategy: DuplicateStrategy = .smart  // ✅ Works!
}
```

**Step 3: Remove Sendable violations**
```swift
// Before:
public struct ImportResult: Sendable {  // ❌ Violation
    let importedWorks: [Work]
}

// After:
public struct ImportResult {  // ✅ Safe
    let importedWorks: [Work]  // @MainActor-only usage
}
```

### The Results

- **Build Errors**: 15 → 0
- **Warnings**: 0 (maintained zero warnings policy)
- **Tests**: All passing (3 test files updated)
- **Commits**: 3 (fix, audit, tests)

---

## Frequently Asked Questions

### Q: When should I create a separate file for a type?

**A:** Only when the type is:
1. Used by multiple unrelated features
2. A domain model (Work, Edition, Author)
3. A shared protocol or extension target
4. Large/complex enough to deserve its own file (100+ lines)

Otherwise, nest it inside the primary service/class.

### Q: Can I nest types multiple levels deep?

**A:** Technically yes, but avoid it. One level is usually sufficient.

```swift
// ✅ GOOD: One level
class CSVImportService {
    enum DuplicateStrategy { ... }
}

// ⚠️ AVOID: Multiple levels (hard to reference)
class CSVImportService {
    enum Options {
        enum DuplicateStrategy { ... }  // CSVImportService.Options.DuplicateStrategy
    }
}
```

### Q: How do I use nested types from tests?

**A:** Add type aliases at the top of your test file:

```swift
import BooksTrackerFeature

typealias DuplicateStrategy = CSVImportService.DuplicateStrategy
typealias ImportResult = CSVImportService.ImportResult

@Test func testImport() {
    let strategy: DuplicateStrategy = .smart  // ✅ Clean!
}
```

### Q: What about types used by both service and view?

**A:** Nest in the service. Views can reference via service name:

```swift
// Service:
class CSVImportService {
    enum DuplicateStrategy { ... }
}

// View:
struct CSVImportView: View {
    @State private var strategy: CSVImportService.DuplicateStrategy = .smart
}
```

### Q: Can extensions add nested types?

**A:** No. Nested types must be in the main type definition:

```swift
// ❌ Can't add nested types in extensions
extension CSVImportService {
    enum NewType { ... }  // Compiler error
}

// ✅ Add to main definition
class CSVImportService {
    enum NewType { ... }
}
```

---

## References

- **Original Issue**: CSV Import Build Failures (October 22, 2025)
- **Commits**:
  - `e2a89a0` - Move type definitions inside CSVImportService
  - `76d359c` - Sendable conformance audit
  - `84d3417` - Update tests for nested types
- **Related Docs**:
  - `/docs/CONCURRENCY_GUIDE.md` - Swift 6 actor isolation
  - `/docs/features/CSV_IMPORT.md` - CSV import architecture
  - `/docs/architecture/2025-10-22-sendable-audit.md` - Sendable audit report
- **Swift Documentation**:
  - [Nested Types](https://docs.swift.org/swift-book/LanguageGuide/NestedTypes.html)
  - [Sendable Protocol](https://developer.apple.com/documentation/swift/sendable)

---

## Next Review

**Q1 2026** or when adding new services/features that define supporting types.

**Review Criteria:**
- Are new services following nested types pattern?
- Any Sendable violations with SwiftData models?
- Test coverage adequate for nested type references?
- Documentation up to date with current practices?
