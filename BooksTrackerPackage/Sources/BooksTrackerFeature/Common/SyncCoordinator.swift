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

    // MARK: - CSV Import Orchestration

    /// Start CSV import job with progress tracking
    /// - Parameters:
    ///   - csvContent: Raw CSV file content
    ///   - mappings: Column mappings for CSV parsing
    ///   - strategy: Duplicate handling strategy
    ///   - modelContext: SwiftData model context for persistence
    /// - Returns: Job identifier for tracking
    @discardableResult
    public func startCSVImport(
        csvContent: String,
        mappings: [CSVParsingActor.ColumnMapping],
        strategy: CSVImportService.DuplicateStrategy,
        modelContext: ModelContext
    ) async -> JobIdentifier {

        let jobId = JobIdentifier(jobType: "csv_import")
        activeJobId = jobId
        jobStatus[jobId] = .queued

        // Get total rows for progress tracking
        let importService = CSVImportService(modelContext: modelContext)
        let totalRows = await importService.getRowCount(from: csvContent)

        // Start with initial progress
        var progress = JobProgress(
            totalItems: totalRows,
            processedItems: 0,
            currentStatus: "Starting import..."
        )
        jobStatus[jobId] = .active(progress: progress)

        // Execute import with progress callbacks
        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: strategy,
            progressUpdate: { [weak self] processedItems, statusMessage in
                guard let self = self else { return }

                // Update progress
                progress.processedItems = processedItems
                progress.currentStatus = statusMessage
                self.jobStatus[jobId] = .active(progress: progress)
            }
        )

        // Update final status
        switch result {
        case .success(let importResult):
            let log = [
                "✅ Import completed successfully",
                "📊 Total rows: \(totalRows)",
                "✅ Successful imports: \(importResult.successCount)",
                "⏭️ Skipped duplicates: \(importResult.duplicateCount)",
                "❌ Failed imports: \(importResult.errorCount)",
                "⏱️ Duration: \(String(format: "%.1f", importResult.duration))s"
            ]
            jobStatus[jobId] = .completed(log: log)

        case .failure(let error):
            jobStatus[jobId] = .failed(error: error.localizedDescription)
        }

        // Clear active job
        if activeJobId == jobId {
            activeJobId = nil
        }

        return jobId
    }

    // MARK: - Enrichment Orchestration

    /// Start enrichment job for queued works
    /// - Parameters:
    ///   - modelContext: SwiftData model context for persistence
    ///   - enrichmentQueue: EnrichmentQueue instance (defaults to .shared)
    /// - Returns: Job identifier for tracking
    @discardableResult
    public func startEnrichment(
        modelContext: ModelContext,
        enrichmentQueue: EnrichmentQueue = .shared
    ) async -> JobIdentifier {

        let jobId = JobIdentifier(jobType: "enrichment")
        activeJobId = jobId
        jobStatus[jobId] = .queued

        // Get total items to enrich
        let totalItems = enrichmentQueue.count()

        // Start with initial progress
        var progress = JobProgress(
            totalItems: totalItems,
            processedItems: 0,
            currentStatus: "Starting enrichment..."
        )
        jobStatus[jobId] = .active(progress: progress)

        // Start enrichment with progress tracking
        enrichmentQueue.startProcessing(in: modelContext) { [weak self] processedCount, totalCount, currentTitle in
            guard let self = self else { return }

            // Update progress
            progress.processedItems = processedCount
            progress.currentStatus = "Enriching: \(currentTitle)"
            self.jobStatus[jobId] = .active(progress: progress)
        }

        // Wait for enrichment to complete
        // EnrichmentQueue runs in background Task, so we poll for completion
        while !enrichmentQueue.isEmpty() {
            try? await Task.sleep(for: .milliseconds(500))

            // Check if job was cancelled
            if let status = jobStatus[jobId], status == .cancelled {
                enrichmentQueue.stopProcessing()
                break
            }
        }

        // Update final status
        if let status = jobStatus[jobId], status == .cancelled {
            // Already cancelled
        } else {
            let log = [
                "✅ Enrichment completed successfully",
                "📊 Total items: \(totalItems)",
                "✅ Processed: \(progress.processedItems)"
            ]
            jobStatus[jobId] = .completed(log: log)
        }

        // Clear active job
        if activeJobId == jobId {
            activeJobId = nil
        }

        return jobId
    }
}
