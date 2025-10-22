# SyncCoordinator Architecture

**Version:** 1.0.0
**Date:** October 16, 2025
**Status:** ✅ Implemented

## Overview

SyncCoordinator is a centralized job orchestrator for managing multi-step background operations in BooksTrack. It provides type-safe progress tracking, unified state management, and clean separation of concerns between UI and business logic.

## Problem Statement

**Before SyncCoordinator:**
- CSV import service tightly coupled @Published state with business logic
- Progress tracking scattered across multiple services
- No unified way to track multi-step operations (import → enrichment)
- UI directly observing service implementation details
- Difficult to add new background jobs consistently

**After SyncCoordinator:**
- Centralized job orchestration with @Published job status
- Type-safe progress tracking with JobModels
- Services provide stateless Result-based APIs
- UI observes coordinator state, not service internals
- Easy to add new job types with consistent patterns

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                    SyncCoordinator                      │
│  (@MainActor, ObservableObject, Singleton)              │
│                                                          │
│  @Published activeJobId: JobIdentifier?                 │
│  @Published jobStatus: [JobIdentifier: JobStatus]       │
│                                                          │
│  + startCSVImport(...) async -> JobIdentifier          │
│  + startEnrichment(...) async -> JobIdentifier         │
│  + getJobStatus(for:) -> JobStatus?                    │
│  + cancelJob(_:)                                       │
└─────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┴──────────────┐
                │                            │
        ┌───────▼───────┐          ┌───────▼────────┐
        │               │          │                │
        │ JobModels     │          │ Services       │
        │               │          │                │
        │ • JobIdentifier│         │ • CSV Import   │
        │ • JobStatus    │         │ • Enrichment   │
        │ • JobProgress  │         │ (Stateless)    │
        │               │          │                │
        └───────────────┘          └────────────────┘
```

### Job Models

**JobIdentifier**
```swift
public struct JobIdentifier: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let jobType: String  // "csv_import", "enrichment"
    public let createdDate: Date
}
```

**JobStatus**
```swift
public enum JobStatus: Codable, Sendable, Equatable {
    case queued
    case active(progress: JobProgress)
    case completed(log: [String])
    case failed(error: String)
    case cancelled

    public var isTerminal: Bool  // true for completed/failed/cancelled
}
```

**JobProgress**
```swift
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var estimatedTimeRemaining: TimeInterval?

    public var fractionCompleted: Double  // 0.0 to 1.0
}
```

### Service Integration Pattern

Services expose **stateless Result-based APIs**:

```swift
// CSV Import Service
public func importCSV(
    content: String,
    mappings: [CSVParsingActor.ColumnMapping],
    strategy: DuplicateStrategy,
    progressUpdate: @escaping (Int, String) -> Void
) async -> Result<ImportResult, Error>

// Enrichment Queue
public func startProcessing(
    in modelContext: ModelContext,
    progressHandler: @escaping (Int, Int, String) -> Void
)
```

SyncCoordinator wraps these APIs with job tracking:

```swift
public func startCSVImport(...) async -> JobIdentifier {
    let jobId = JobIdentifier(jobType: "csv_import")

    // Create initial progress
    jobStatus[jobId] = .active(progress: .zero)

    // Execute service with progress callbacks
    let result = await service.importCSV(...) { processed, status in
        // Update progress in real-time
        progress.processedItems = processed
        progress.currentStatus = status
        jobStatus[jobId] = .active(progress: progress)
    }

    // Update final status
    switch result {
    case .success(let data):
        jobStatus[jobId] = .completed(log: [...])
    case .failure(let error):
        jobStatus[jobId] = .failed(error: error.localizedDescription)
    }

    return jobId
}
```

## Usage Examples

### Starting a CSV Import

```swift
@StateObject private var coordinator = SyncCoordinator.shared
@State private var currentJobId: JobIdentifier?

// Start import
Task {
    currentJobId = await coordinator.startCSVImport(
        csvContent: csvContent,
        mappings: mappings,
        strategy: .smart,
        modelContext: modelContext
    )
}

// Monitor progress
if let jobId = currentJobId,
   let status = coordinator.getJobStatus(for: jobId) {

    switch status {
    case .active(let progress):
        ProgressView(value: progress.fractionCompleted)
        Text(progress.currentStatus)

    case .completed(let log):
        Text("✅ Import Complete")
        ForEach(log, id: \.self) { Text($0) }

    case .failed(let error):
        Text("❌ Import Failed: \(error)")

    default:
        ProgressView()
    }
}
```

### Starting Enrichment

```swift
// Enqueue works first
EnrichmentQueue.shared.enqueueBatch(workIDs)

// Start enrichment job
Task {
    let jobId = await coordinator.startEnrichment(
        modelContext: modelContext,
        enrichmentQueue: .shared
    )
}
```

### Cancelling a Job

```swift
coordinator.cancelJob(jobId)
// Job status → .cancelled
// Active job cleared
// Background work stopped
```

## Swift 6 Concurrency Compliance

**Actor Isolation:**
- `SyncCoordinator`: `@MainActor` (UI state, published properties)
- `JobModels`: All `Sendable` (safe cross-actor transfer)
- Services: Async methods with `@Sendable` closures

**Progress Callbacks:**
```swift
progressUpdate: @escaping @Sendable (Int, String) -> Void
```

**No Data Races:**
- All mutations happen on `@MainActor`
- Callbacks properly isolated
- No shared mutable state

## Benefits

### 1. Separation of Concerns
- **UI**: Observes coordinator state
- **Coordinator**: Orchestrates jobs
- **Services**: Execute business logic

### 2. Type Safety
- Compile-time job type checking
- No magic strings for status
- Guaranteed Sendable conformance

### 3. Testability
- Services return `Result` (easy to test)
- Coordinator state observable
- No hidden side effects

### 4. Extensibility
Add new job types in 3 steps:
1. Add `start<JobType>()` method to coordinator
2. Create `JobIdentifier(jobType: "...")`
3. Update service to use Result-based API

### 5. Backward Compatibility
- Legacy CSVImportService still has `@Published` state
- Existing views continue working
- Gradual migration path

## Migration Status

### ✅ Fully Implemented (October 21, 2025)
- [x] JobModels foundation (JobIdentifier, JobStatus, JobProgress)
- [x] SyncCoordinator shell with singleton pattern
- [x] CSVImportService Result-based API
- [x] CSV import orchestration in coordinator
- [x] Enrichment orchestration in coordinator
- [x] **CSVImportFlowView migrated to SyncCoordinator** ✨ NEW
- [x] Unit tests for JobModels and SyncCoordinator
- [x] Swift 6 concurrency compliance
- [x] Zero-warning builds
- [x] Production deployment

### 📝 Future Enhancements
- [ ] Add PollingUtility integration for backend polling jobs
- [ ] Add SwiftUI modifiers for job progress display
- [ ] Deprecate legacy CSVImportService @Published API
- [ ] Add analytics for job completion rates
- [ ] Add job history/audit log

## Files Modified

### Created
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/JobModels.swift`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift`
- `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SyncCoordinatorTests.swift`

### Modified
- `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/CSVImportService.swift`
  - Added Result-based `importCSV()` method
  - Added `getRowCount()` helper
  - Kept `ObservableObject` for backward compatibility

## Related Documentation

- [CSV Import Flow](../archive/csvMoon-implementation-notes.md)
- [Enrichment Queue](../../BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentQueue.swift)
- [Swift 6 Concurrency Guide](../../Config/Shared.xcconfig)
- [Implementation Plan](./2025-10-16-csv-coordinator-refactor-plan.md)

## Version History

- **1.0.0** (October 16, 2025) - Initial implementation
  - JobModels foundation
  - SyncCoordinator with CSV + Enrichment orchestration
  - Unit tests and documentation
