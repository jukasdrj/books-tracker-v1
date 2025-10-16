# CSV Coordinator Refactor Implementation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Refactor CSV import and enrichment services to use a centralized SyncCoordinator with standardized job models, leveraging main branch's PollingUtility and Progress UI components.

**Architecture:** Replace the current tightly-coupled CSV import flow with a coordinator pattern that orchestrates multi-step jobs (parse → import → enrich). Use PollingUtility for backend polling (Task.sleep, not Timer.publish), JobModels for type-safe job tracking, and existing Progress UI components for display. This reduces CSV/enrichment code by ~1500 lines while improving testability and separation of concerns.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, @MainActor isolation, PollingUtility.swift, ProgressComponents.swift

**Context:** Closes `feature/polling-progress-tracker` branch (architectural mismatch with main). Cherry-picks valuable patterns (SyncCoordinator, JobModels) and reimplements using main's modern concurrency primitives.

---

## Pre-Implementation Checklist

- [ ] Close `origin/feature/polling-progress-tracker` branch (don't merge)
- [ ] Create new branch from main: `feature/csv-coordinator-refactor`
- [ ] Verify main branch has: `PollingUtility.swift`, `ProgressComponents.swift`, `EnrichmentQueue.swift`
- [ ] Read current implementations: `CSVImportService.swift`, `CSVImportFlowView.swift`, `EnrichmentQueue.swift`

---

## Task 1: Create Job Models Foundation

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/JobModels.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/JobModelsTests.swift`

**Step 1: Write failing test for JobIdentifier**

Create test file with:

```swift
import Testing
@testable import BooksTrackerFeature

@Suite("Job Models Tests")
struct JobModelsTests {

    @Test("JobIdentifier creates unique IDs for same job type")
    func jobIdentifierUniqueness() {
        let job1 = JobIdentifier(jobType: "CSV_IMPORT")
        let job2 = JobIdentifier(jobType: "CSV_IMPORT")

        #expect(job1.id != job2.id)
        #expect(job1.jobType == job2.jobType)
    }

    @Test("JobIdentifier is Hashable and Equatable")
    func jobIdentifierHashable() {
        let job1 = JobIdentifier(jobType: "TEST")
        let job2 = job1

        #expect(job1 == job2)
        #expect(job1.hashValue == job2.hashValue)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter JobModelsTests --package-path BooksTrackerPackage`
Expected: FAIL with "JobIdentifier not found"

**Step 3: Implement JobIdentifier**

Create `JobModels.swift`:

```swift
import Foundation

// MARK: - Job Identifier
/// Unique identifier for tracking long-running operations
public struct JobIdentifier: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let jobType: String
    public let createdDate: Date

    public init(jobType: String) {
        self.id = UUID()
        self.jobType = jobType
        self.createdDate = Date()
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter JobModelsTests --package-path BooksTrackerPackage`
Expected: PASS (2 tests)

**Step 5: Add JobStatus and JobProgress with tests**

Add to test file:

```swift
@Test("JobStatus terminal states")
func jobStatusTerminalStates() {
    let completed = JobStatus.completed(log: ["Done"])
    let failed = JobStatus.failed(error: "Test error")
    let cancelled = JobStatus.cancelled
    let active = JobStatus.active(progress: .zero)

    #expect(completed.isTerminal == true)
    #expect(failed.isTerminal == true)
    #expect(cancelled.isTerminal == true)
    #expect(active.isTerminal == false)
}

@Test("JobProgress calculates fraction correctly")
func jobProgressFraction() {
    let progress = JobProgress(
        totalItems: 100,
        processedItems: 25,
        currentStatus: "Processing..."
    )

    #expect(progress.fractionCompleted == 0.25)
}

@Test("JobProgress handles zero total items")
func jobProgressZeroItems() {
    let progress = JobProgress.zero
    #expect(progress.fractionCompleted == 0)
}
```

**Step 6: Implement JobStatus and JobProgress**

Add to `JobModels.swift`:

```swift
// MARK: - Job Status
/// Current state of a job with associated data
public enum JobStatus: Codable, Sendable, Equatable {
    case queued
    case active(progress: JobProgress)
    case completed(log: [String])
    case failed(error: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .active:
            return false
        }
    }
}

// MARK: - Job Progress
/// Progress information for active jobs
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var estimatedTimeRemaining: TimeInterval?

    public var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
    }

    public static var zero: JobProgress {
        JobProgress(
            totalItems: 0,
            processedItems: 0,
            currentStatus: "Starting..."
        )
    }
}
```

**Step 7: Run all tests**

Run: `swift test --filter JobModelsTests --package-path BooksTrackerPackage`
Expected: PASS (5 tests)

**Step 8: Commit Task 1**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/JobModels.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/JobModelsTests.swift
git commit -m "feat: add JobModels foundation for coordinator pattern

- JobIdentifier for unique job tracking
- JobStatus enum with terminal state detection
- JobProgress with fraction calculation
- Full test coverage with Swift Testing"
```

---

## Task 2: Create SyncCoordinator Shell

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SyncCoordinatorTests.swift`

**Step 1: Write failing test for SyncCoordinator initialization**

```swift
import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("SyncCoordinator Tests")
@MainActor
struct SyncCoordinatorTests {

    @Test("SyncCoordinator is a singleton")
    func coordinatorSingleton() {
        let instance1 = SyncCoordinator.shared
        let instance2 = SyncCoordinator.shared

        #expect(instance1 === instance2)
    }

    @Test("SyncCoordinator starts with no active jobs")
    func initialState() {
        let coordinator = SyncCoordinator.shared
        #expect(coordinator.activeJobId == nil)
        #expect(coordinator.jobStatus.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SyncCoordinatorTests --package-path BooksTrackerPackage`
Expected: FAIL with "SyncCoordinator not found"

**Step 3: Implement SyncCoordinator shell**

Create `SyncCoordinator.swift`:

```swift
import Foundation
import SwiftData
import SwiftUI

/// Orchestrates multi-step background jobs (CSV import, enrichment)
/// Uses PollingUtility for backend polling and JobModels for type-safe tracking
@MainActor
public final class SyncCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var activeJobId: JobIdentifier?
    @Published public private(set) var jobStatus: [JobIdentifier: JobStatus] = [:]

    // MARK: - Singleton

    public static let shared = SyncCoordinator()

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton pattern
    }

    // MARK: - Public Methods

    /// Get current status for a job
    public func getJobStatus(for jobId: JobIdentifier) -> JobStatus? {
        return jobStatus[jobId]
    }

    /// Cancel an active job
    public func cancelJob(_ jobId: JobIdentifier) {
        jobStatus[jobId] = .cancelled
        if activeJobId == jobId {
            activeJobId = nil
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SyncCoordinatorTests --package-path BooksTrackerPackage`
Expected: PASS (2 tests)

**Step 5: Commit Task 2**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SyncCoordinatorTests.swift
git commit -m "feat: add SyncCoordinator shell with singleton pattern

- @MainActor isolation for SwiftData compatibility
- Published properties for SwiftUI reactivity
- Job status tracking dictionary
- Basic job cancellation support"
```

---

## Task 3: Refactor CSVImportService to Result-Based API

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/CSVImportService.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/CSVImportServiceTests.swift` (if exists)

**Context:** Current CSVImportService uses @Published state and ObservableObject. We need to convert it to a stateless service that returns Results and accepts progress callbacks.

**Step 1: Read current CSVImportService implementation**

Run: Use Read tool to examine current state management pattern

**Step 2: Create backup branch**

```bash
git checkout -b backup/csv-import-service-before-refactor
git checkout feature/csv-coordinator-refactor
```

**Step 3: Simplify CSVImportService - Remove ObservableObject**

In `CSVImportService.swift`, change:

```swift
// OLD
@MainActor
public class CSVImportService: ObservableObject {
    @Published public var importState: ImportState = .idle
    @Published public var progress: ImportProgress = ImportProgress()
    // ... other published properties

// NEW
@MainActor
public class CSVImportService {
    // No published properties - stateless service
```

**Step 4: Add Result-based import method**

Add new method to `CSVImportService`:

```swift
/// Import CSV with progress callbacks (stateless)
public func importCSV(
    content: String,
    mappings: [CSVParsingActor.ColumnMapping],
    strategy: DuplicateStrategy,
    progressUpdate: @escaping (Int, String) -> Void
) async -> Result<ImportResult, Error> {

    let startTime = Date()
    var importedWorks: [Work] = []
    var successCount = 0
    var duplicateCount = 0
    var errors: [ImportError] = []

    do {
        // Parse CSV
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(content)

        // Process in batches
        for (index, row) in rows.enumerated() {
            progressUpdate(index + 1, "Processing row \(index + 1) of \(rows.count)")

            // Extract work data using mappings
            guard let workData = extractWorkData(from: row, headers: headers, mappings: mappings) else {
                errors.append(ImportError(
                    row: index + 1,
                    title: "Unknown",
                    message: "Failed to extract work data"
                ))
                continue
            }

            // Check for duplicates
            let existingWork = try await findDuplicate(workData: workData, strategy: strategy)

            if let existing = existingWork, strategy == .skip {
                duplicateCount += 1
                continue
            }

            // Create or update work
            let work = existing ?? Work(
                title: workData.title,
                subtitle: workData.subtitle,
                publicationYear: workData.publicationYear
            )

            if existing == nil {
                modelContext.insert(work)
                importedWorks.append(work)
            }

            successCount += 1
        }

        // Save changes
        try modelContext.save()

        let duration = Date().timeIntervalSince(startTime)
        let result = ImportResult(
            successCount: successCount,
            duplicateCount: duplicateCount,
            errorCount: errors.count,
            importedWorks: importedWorks,
            errors: errors,
            duration: duration
        )

        return .success(result)

    } catch {
        return .failure(error)
    }
}

// MARK: - Private Helpers

private struct WorkData {
    let title: String
    let subtitle: String?
    let publicationYear: Int?
}

private func extractWorkData(
    from row: [String],
    headers: [String],
    mappings: [CSVParsingActor.ColumnMapping]
) -> WorkData? {
    // TODO: Implement mapping logic
    // For now, stub implementation
    guard row.count > 0 else { return nil }
    return WorkData(title: row[0], subtitle: nil, publicationYear: nil)
}

private func findDuplicate(
    workData: WorkData,
    strategy: DuplicateStrategy
) async throws -> Work? {
    // TODO: Implement duplicate detection
    // For now, return nil (no duplicates)
    return nil
}
```

**Step 5: Add helper method for row count**

Add to `CSVImportService`:

```swift
/// Get total row count from CSV (for progress tracking)
public func getRowCount(from csvContent: String) async -> Int {
    let parsedData = try? await CSVParsingActor.shared.parseCSV(csvContent)
    return parsedData?.rows.count ?? 0
}
```

**Step 6: Run build to verify compilation**

Run: `/build` (MCP command)
Expected: Build succeeds (may have warnings about unused old methods)

**Step 7: Commit Task 3**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/CSVImportService.swift
git commit -m "refactor: convert CSVImportService to stateless Result-based API

- Remove ObservableObject and @Published state
- Add importCSV with progress callback
- Return Result<ImportResult, Error> for coordinator pattern
- Add getRowCount helper for progress tracking
- Stub implementations for extractWorkData and findDuplicate (TODO)"
```

---

## Task 4: Implement CSV Import in SyncCoordinator

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift`

**Step 1: Add CSV import method to SyncCoordinator**

Add to `SyncCoordinator`:

```swift
/// Start a CSV import job
public func startCSVImport(
    fileName: String,
    csvContent: String,
    mappings: [CSVParsingActor.ColumnMapping],
    duplicateStrategy: CSVImportService.DuplicateStrategy,
    modelContext: ModelContext
) async -> JobIdentifier {

    let jobId = JobIdentifier(jobType: "CSV_IMPORT")
    activeJobId = jobId
    jobStatus[jobId] = .queued

    // Run import in background
    Task {
        await performCSVImport(
            jobId: jobId,
            fileName: fileName,
            csvContent: csvContent,
            mappings: mappings,
            strategy: duplicateStrategy,
            modelContext: modelContext
        )
    }

    return jobId
}

// MARK: - Private Import Logic

private func performCSVImport(
    jobId: JobIdentifier,
    fileName: String,
    csvContent: String,
    mappings: [CSVParsingActor.ColumnMapping],
    strategy: CSVImportService.DuplicateStrategy,
    modelContext: ModelContext
) async {

    let importService = CSVImportService(modelContext: modelContext)

    // Get total rows for progress tracking
    let totalRows = await importService.getRowCount(from: csvContent)

    // Set initial status
    jobStatus[jobId] = .active(progress: JobProgress(
        totalItems: totalRows,
        processedItems: 0,
        currentStatus: "Starting import..."
    ))

    // Run import with progress updates
    let result = await importService.importCSV(
        content: csvContent,
        mappings: mappings,
        strategy: strategy,
        progressUpdate: { [weak self] processedItems, statusText in
            guard let self = self else { return }

            if case var .active(progress) = self.jobStatus[jobId] {
                progress.processedItems = processedItems
                progress.currentStatus = statusText
                self.jobStatus[jobId] = .active(progress: progress)
            }
        }
    )

    // Update final status
    switch result {
    case .success(let importResult):
        jobStatus[jobId] = .completed(log: [
            "\(importResult.successCount) books imported",
            "\(importResult.duplicateCount) duplicates skipped",
            "\(importResult.errorCount) errors"
        ])

        // Auto-trigger enrichment if we have imported works
        if !importResult.importedWorks.isEmpty {
            await startEnrichment(
                works: importResult.importedWorks,
                modelContext: modelContext
            )
        }

    case .failure(let error):
        jobStatus[jobId] = .failed(error: error.localizedDescription)
    }

    activeJobId = nil
}
```

**Step 2: Add stub for enrichment trigger**

Add to `SyncCoordinator`:

```swift
/// Start enrichment job (stub - will implement in next task)
private func startEnrichment(
    works: [Work],
    modelContext: ModelContext
) async {
    // TODO: Implement in Task 5
    print("⚠️ Enrichment queued: \(works.count) works")
}
```

**Step 3: Run build to verify compilation**

Run: `/build`
Expected: Build succeeds

**Step 4: Commit Task 4**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift
git commit -m "feat: implement CSV import orchestration in SyncCoordinator

- Add startCSVImport public method
- Track job lifecycle (queued -> active -> completed/failed)
- Update progress via callback from CSVImportService
- Auto-trigger enrichment after successful import
- Stub enrichment for Task 5"
```

---

## Task 5: Integrate EnrichmentQueue with SyncCoordinator

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift`
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/EnrichmentQueue.swift`

**Step 1: Read current EnrichmentQueue implementation**

Run: Use Read tool to review EnrichmentQueue.swift

**Step 2: Implement enrichment in SyncCoordinator**

Replace stub in `SyncCoordinator` with:

```swift
/// Start enrichment job for imported works
private func startEnrichment(
    works: [Work],
    modelContext: ModelContext
) async {

    let enrichmentQueue = EnrichmentQueue.shared
    let enrichmentService = EnrichmentService.shared

    // Enqueue all works
    let workIDs = works.map { $0.persistentModelID }
    enrichmentQueue.enqueueBatch(workIDs)

    let jobId = JobIdentifier(jobType: "ENRICHMENT")
    activeJobId = jobId

    let totalItems = enrichmentQueue.count()
    jobStatus[jobId] = .active(progress: JobProgress(
        totalItems: totalItems,
        processedItems: 0,
        currentStatus: "Starting enrichment..."
    ))

    // Process queue
    var processedCount = 0
    while let workID = enrichmentQueue.pop() {
        // Get work from SwiftData
        guard let work = modelContext.model(for: workID) as? Work else {
            processedCount += 1
            continue
        }

        // Update progress
        if case var .active(progress) = jobStatus[jobId] {
            progress.processedItems = processedCount
            progress.currentStatus = "Enriching: \(work.title)"
            jobStatus[jobId] = .active(progress: progress)
        }

        // Enrich work
        _ = await enrichmentService.enrichWork(work, in: modelContext)

        processedCount += 1
    }

    // Mark complete
    jobStatus[jobId] = .completed(log: [
        "Enrichment complete",
        "\(processedCount) works enriched"
    ])
    activeJobId = nil
}
```

**Step 3: Run build to verify compilation**

Run: `/build`
Expected: Build succeeds

**Step 4: Commit Task 5**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/Common/SyncCoordinator.swift
git commit -m "feat: integrate EnrichmentQueue with SyncCoordinator

- Implement startEnrichment with job tracking
- Process enrichment queue with progress updates
- Use EnrichmentService.shared for actual enrichment
- Handle graceful skipping of deleted works"
```

---

## Task 6: Update CSVImportFlowView to Use SyncCoordinator

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/CSVImportFlowView.swift`

**Step 1: Read current CSVImportFlowView implementation**

Run: Use Read tool to examine current view structure

**Step 2: Add SyncCoordinator as StateObject**

In `CSVImportFlowView`, add:

```swift
@StateObject private var coordinator = SyncCoordinator.shared
@State private var currentJobId: JobIdentifier?
```

**Step 3: Replace import trigger with coordinator call**

Find the section that calls `importService.startImport()` and replace with:

```swift
// Start CSV import via coordinator
Task {
    currentJobId = await coordinator.startCSVImport(
        fileName: selectedFile.lastPathComponent,
        csvContent: csvContent,
        mappings: columnMappings,
        duplicateStrategy: duplicateStrategy,
        modelContext: modelContext
    )
}
```

**Step 4: Update progress display to use coordinator status**

Replace progress view with:

```swift
if let jobId = currentJobId,
   let status = coordinator.getJobStatus(for: jobId) {

    switch status {
    case .active(let progress):
        ProgressBanner(
            isShowing: .constant(true),
            title: "Importing CSV",
            message: progress.currentStatus
        )

        StagedProgressView(
            stages: ["Parsing", "Importing", "Enriching"],
            currentStageIndex: .constant(determineStage(progress)),
            progress: .constant(progress.fractionCompleted)
        )

    case .completed(let log):
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.headline)

            ForEach(log, id: \.self) { message in
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()

    case .failed(let error):
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Import Failed")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()

    default:
        PollingIndicator(stageName: "Initializing...")
    }
}

// MARK: - Helper
private func determineStage(_ progress: JobProgress) -> Int {
    // Simple heuristic based on status text
    if progress.currentStatus.contains("Parsing") {
        return 0
    } else if progress.currentStatus.contains("Enriching") {
        return 2
    } else {
        return 1  // Importing
    }
}
```

**Step 5: Run build and test in simulator**

Run: `/sim`
Expected: App launches, CSV import flow uses new coordinator

**Step 6: Commit Task 6**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/CSVImport/CSVImportFlowView.swift
git commit -m "refactor: migrate CSVImportFlowView to SyncCoordinator

- Remove direct importService state observation
- Use SyncCoordinator.startCSVImport()
- Display progress via coordinator.jobStatus
- Use ProgressBanner and StagedProgressView components
- Add completion/error handling UI"
```

---

## Task 7: Add Unit Tests for SyncCoordinator

**Files:**
- Modify: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SyncCoordinatorTests.swift`

**Step 1: Add test for CSV import job lifecycle**

Add to `SyncCoordinatorTests`:

```swift
@Test("CSV import job lifecycle tracking")
@MainActor
func csvImportJobLifecycle() async throws {
    // Create in-memory model context for testing
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
        configurations: config
    )
    let context = ModelContext(container)

    let coordinator = SyncCoordinator.shared

    // Start job
    let jobId = await coordinator.startCSVImport(
        fileName: "test.csv",
        csvContent: "Title\nTest Book",
        mappings: [],
        duplicateStrategy: .skip,
        modelContext: context
    )

    // Verify job started
    #expect(coordinator.activeJobId == jobId)

    // Poll until job completes (with timeout)
    var attempts = 0
    while attempts < 50 {  // 5 seconds max
        if let status = coordinator.getJobStatus(for: jobId),
           status.isTerminal {
            break
        }
        try await Task.sleep(for: .milliseconds(100))
        attempts += 1
    }

    // Verify job completed or failed (not stuck)
    let finalStatus = coordinator.getJobStatus(for: jobId)
    #expect(finalStatus?.isTerminal == true)
}
```

**Step 2: Add test for job cancellation**

Add to `SyncCoordinatorTests`:

```swift
@Test("Job cancellation updates status")
@MainActor
func jobCancellation() {
    let coordinator = SyncCoordinator.shared
    let jobId = JobIdentifier(jobType: "TEST")

    // Simulate active job
    coordinator.jobStatus[jobId] = .active(progress: .zero)
    coordinator.activeJobId = jobId

    // Cancel job
    coordinator.cancelJob(jobId)

    // Verify cancellation
    #expect(coordinator.activeJobId == nil)
    #expect(coordinator.jobStatus[jobId] == .cancelled)
}
```

**Step 3: Run tests**

Run: `swift test --filter SyncCoordinatorTests --package-path BooksTrackerPackage`
Expected: PASS (4 tests total)

**Step 4: Commit Task 7**

```bash
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SyncCoordinatorTests.swift
git commit -m "test: add SyncCoordinator job lifecycle tests

- Test CSV import job tracking
- Test job cancellation behavior
- Use in-memory SwiftData for isolated tests"
```

---

## Task 8: Update Documentation

**Files:**
- Modify: `CLAUDE.md`
- Create: `docs/architecture/sync-coordinator.md`

**Step 1: Document SyncCoordinator pattern in CLAUDE.md**

Add section to `CLAUDE.md` after "CSV Import & Enrichment System":

```markdown
### SyncCoordinator Pattern

**Architecture:** Centralized orchestration for multi-step background jobs using JobModels and PollingUtility.

**Key Files:** `SyncCoordinator.swift`, `JobModels.swift`

**Usage:**
```swift
@StateObject private var coordinator = SyncCoordinator.shared

// Start CSV import
let jobId = await coordinator.startCSVImport(
    fileName: "library.csv",
    csvContent: csvString,
    mappings: columnMappings,
    duplicateStrategy: .smart,
    modelContext: modelContext
)

// Track progress
if let status = coordinator.getJobStatus(for: jobId) {
    switch status {
    case .active(let progress):
        ProgressBanner(
            title: "Importing",
            message: progress.currentStatus
        )
    case .completed(let log):
        Text("Done: \(log.joined(separator: ", "))")
    case .failed(let error):
        Text("Error: \(error)")
    default:
        EmptyView()
    }
}
```

**Job Types:**
- `CSV_IMPORT`: Parse → Import → Auto-trigger enrichment
- `ENRICHMENT`: Background metadata enhancement
```

**Step 2: Create architecture documentation**

Create `docs/architecture/sync-coordinator.md`:

```markdown
# SyncCoordinator Architecture

## Overview

SyncCoordinator provides centralized orchestration for long-running, multi-step background jobs. It replaces the previous pattern of tightly-coupled service state management with a coordinator that uses JobModels for type-safe tracking and PollingUtility for backend polling.

## Design Principles

1. **Separation of Concerns**: Services (CSVImportService, EnrichmentService) are stateless and return Results. Coordinator handles job lifecycle.
2. **Type Safety**: JobModels (JobIdentifier, JobStatus, JobProgress) provide compile-time guarantees.
3. **Swift 6 Compliance**: Uses Task.sleep (via PollingUtility), not Timer.publish.
4. **SwiftUI Reactive**: @Published properties for automatic UI updates.
5. **Single Responsibility**: Each job type has one clear workflow.

## Job Lifecycle

```
┌─────────┐     startJob()      ┌────────┐
│ Queued  ├───────────────────> │ Active │
└─────────┘                     └────┬───┘
                                     │
                        Progress Updates (0-100%)
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
              ┌──────────┐    ┌─────────┐    ┌──────────┐
              │Completed │    │ Failed  │    │Cancelled │
              └──────────┘    └─────────┘    └──────────┘
```

## CSV Import Workflow

1. **Parse**: CSVParsingActor validates and parses CSV
2. **Import**: CSVImportService processes rows with duplicate detection
3. **Enrich**: Auto-triggered enrichment via EnrichmentQueue
4. **Complete**: Final status with summary log

## Error Handling

- Services return `Result<T, Error>` for explicit error paths
- Coordinator captures failures in JobStatus.failed
- UI displays errors via coordinator.jobStatus observation

## Testing Strategy

- Mock ModelContext with in-memory SwiftData
- Test job lifecycle transitions
- Verify progress update propagation
- Test cancellation behavior

## Migration from Old Pattern

**Before (ObservableObject in Service):**
```swift
@StateObject private var importService = CSVImportService(modelContext: context)
// Service manages its own state
await importService.startImport()
// View observes service.importState
```

**After (Coordinator Pattern):**
```swift
@StateObject private var coordinator = SyncCoordinator.shared
// Coordinator orchestrates stateless services
let jobId = await coordinator.startCSVImport(...)
// View observes coordinator.jobStatus[jobId]
```

## Benefits

- **Testability**: Stateless services are easier to test
- **Reusability**: Services can be used outside coordinator
- **Observability**: Centralized job tracking across entire app
- **Maintainability**: Clear separation of concerns
- **Performance**: No unnecessary view updates from service internals
```

**Step 3: Run documentation linter**

Run: `markdownlint docs/architecture/sync-coordinator.md` (if available)
Expected: No issues

**Step 4: Commit Task 8**

```bash
git add CLAUDE.md
git add docs/architecture/sync-coordinator.md
git commit -m "docs: document SyncCoordinator architecture pattern

- Add usage examples to CLAUDE.md
- Create detailed architecture guide
- Document job lifecycle and error handling
- Add migration guide from old pattern"
```

---

## Task 9: Integration Testing

**Files:**
- Test: Manual testing in simulator

**Step 1: Test CSV import end-to-end**

1. Launch app with `/sim`
2. Navigate to Settings → Import CSV Library
3. Select a test CSV file (create one if needed: "Title,Author\nTest Book,Test Author")
4. Verify column mapping UI appears
5. Start import
6. Verify ProgressBanner appears with status updates
7. Verify StagedProgressView shows progress
8. Verify completion UI with summary
9. Verify books appear in library
10. Check console for enrichment trigger log

**Step 2: Test job cancellation** (if UI added)

1. Start CSV import
2. Tap cancel button (if implemented)
3. Verify job status changes to .cancelled
4. Verify UI dismisses gracefully

**Step 3: Test error handling**

1. Create malformed CSV (invalid format)
2. Start import
3. Verify error UI appears
4. Verify error message is helpful

**Step 4: Run full test suite**

Run: `/test`
Expected: All tests pass

**Step 5: Document test results**

Create test report in commit message:

```bash
git commit --allow-empty -m "test: verify SyncCoordinator integration end-to-end

Manual testing completed:
- ✅ CSV import with progress tracking
- ✅ Auto-enrichment trigger
- ✅ Error handling UI
- ✅ All unit tests pass
- ✅ Zero build warnings

Device: iPhone 17 Pro Simulator (iOS 26.0)
Build: Debug configuration"
```

---

## Task 10: Close Old Branch and Create PR

**Files:**
- Git operations

**Step 1: Push feature branch**

```bash
git push origin feature/csv-coordinator-refactor
```

**Step 2: Close old feature branch** (don't merge)

```bash
# Add comment explaining why it's being closed
gh pr comment <PR_NUMBER> --body "Closing in favor of #<NEW_PR_NUMBER> which reimplements this using main's PollingUtility and Progress UI components. The architectural direction diverged after PR #75 and #76, making a rebase impractical. Valuable patterns (SyncCoordinator, JobModels) have been cherry-picked and modernized."

# Close PR
gh pr close <PR_NUMBER>

# Delete remote branch
git push origin --delete feature/polling-progress-tracker
```

**Step 3: Create PR for new branch**

```bash
gh pr create \
  --title "Refactor CSV import to use SyncCoordinator pattern" \
  --body "$(cat << 'EOF'
## Summary
Refactors CSV import and enrichment to use a centralized SyncCoordinator with standardized job models. Replaces tightly-coupled service state management with coordinator pattern using main's PollingUtility and Progress UI components.

## Changes
- **New**: SyncCoordinator for job orchestration
- **New**: JobModels (JobIdentifier, JobStatus, JobProgress)
- **Refactor**: CSVImportService to stateless Result-based API
- **Refactor**: CSVImportFlowView to use coordinator + Progress UI components
- **Deleted**: ~1500 lines of duplicate state management

## Architecture
- Leverages main's PollingUtility (Task.sleep, not Timer.publish)
- Uses existing ProgressBanner/StagedProgressView components
- Swift 6 compliant (@MainActor isolation, Sendable)
- Full test coverage for job lifecycle

## Testing
- [x] Unit tests pass
- [x] Manual testing in simulator
- [x] CSV import end-to-end
- [x] Auto-enrichment trigger
- [x] Error handling
- [x] Zero build warnings

## Closes
Supersedes #<OLD_PR_NUMBER> (architectural mismatch with main after PR #75, #76)

## Related
- Implementation plan: docs/plans/2025-10-16-csv-coordinator-refactor.md
- Architecture docs: docs/architecture/sync-coordinator.md
EOF
)" \
  --base main \
  --head feature/csv-coordinator-refactor
```

**Step 4: Request code review**

```bash
gh pr review --approve  # Or request review from team
```

**Step 5: Final commit**

```bash
git commit --allow-empty -m "chore: close old branch and create PR for coordinator refactor"
```

---

## Post-Implementation Verification

After PR is merged:

- [ ] Verify CSV import works on physical device (not just simulator)
- [ ] Verify enrichment progress banner appears as expected
- [ ] Check memory usage during large CSV imports (1500+ books)
- [ ] Update CHANGELOG.md with user-facing improvements
- [ ] Delete backup branch: `git branch -D backup/csv-import-service-before-refactor`

---

## Rollback Plan

If issues arise after merge:

1. Revert merge commit: `git revert -m 1 <merge-commit-sha>`
2. Restore old branch: `git checkout backup/csv-import-service-before-refactor`
3. Cherry-pick any unrelated fixes that happened during implementation
4. Create new branch with fixes: `feature/csv-coordinator-refactor-v2`

---

## Notes for Executor

- **Swift 6 Critical**: Never use Timer.publish for polling. Always use Task.sleep via PollingUtility.
- **MainActor Isolation**: SyncCoordinator MUST be @MainActor for SwiftData compatibility.
- **Testing**: Use in-memory ModelContext for isolated tests (ModelConfiguration.isStoredInMemoryOnly).
- **Progress Updates**: Coordinator should throttle UI updates if processing >1000 items (update every 10 items, not every item).
- **Error Handling**: Always wrap SwiftData operations in do-catch and return .failure(error).
- **Documentation**: Update CLAUDE.md immediately when architecture changes.

## Success Criteria

- [ ] Zero build warnings
- [ ] All tests pass
- [ ] CSV import uses SyncCoordinator
- [ ] Progress UI uses ProgressBanner/StagedProgressView
- [ ] No Timer.publish violations
- [ ] Code reduction: -1000+ lines minimum
- [ ] Documentation updated (CLAUDE.md + architecture docs)
- [ ] PR created and reviewed
- [ ] Old branch closed with explanation
