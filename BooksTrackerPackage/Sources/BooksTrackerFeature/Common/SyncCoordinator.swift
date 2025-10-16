//
//  SyncCoordinator.swift
//  BooksTracker
//
//  Created by Jules on 10/16/25.
//

import Foundation
import SwiftData

@MainActor
public class SyncCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var activeJobId: JobIdentifier?
    @Published public private(set) var jobResult: CSVImportService.ImportResult?

    // MARK: - Public Properties

    public static let shared = SyncCoordinator()

    // MARK: - Private Properties

    private let progressTracker = PollingProgressTracker.shared
    private let enrichmentService = EnrichmentService.shared
    private let enrichmentQueue = EnrichmentQueue.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    public func startCsvImport(
        fileName: String,
        csvContent: String,
        mappings: [CSVParsingActor.ColumnMapping],
        duplicateStrategy: CSVImportService.DuplicateStrategy,
        modelContext: ModelContext
    ) -> JobIdentifier {
        let jobId = JobIdentifier(jobType: "CSV_IMPORT")
        activeJobId = jobId

        Task {
            let importService = CSVImportService(modelContext: modelContext)
            let totalRows = await importService.getRowCount(from: csvContent)
            progressTracker.startJob(jobId: jobId, totalItems: totalRows)

            let result = await importService.importCsv(
                content: csvContent,
                mappings: mappings,
                strategy: duplicateStrategy,
                progressUpdate: { processed, status in
                    self.progressTracker.updateProgress(jobId: jobId, processedItems: processed, statusText: status)
                }
            )

            switch result {
            case .success(let importResult):
                self.jobResult = importResult
                self.progressTracker.completeJob(jobId: jobId, log: ["\(importResult.successCount) books imported."])
                if !importResult.importedWorks.isEmpty {
                    self.startEnrichment(works: importResult.importedWorks, modelContext: modelContext)
                }
            case .failure(let error):
                self.progressTracker.failJob(jobId: jobId, error: error.localizedDescription)
            }
        }

        return jobId
    }

    public func startEnrichment(works: [Work], modelContext: ModelContext) {
        let workIDs = works.map { $0.persistentModelID }
        enrichmentQueue.enqueueBatch(workIDs)

        let jobId = JobIdentifier(jobType: "ENRICHMENT")
        activeJobId = jobId

        Task {
            let totalItems = enrichmentQueue.count()
            progressTracker.startJob(jobId: jobId, totalItems: totalItems)

            var processedCount = 0
            while let workId = enrichmentQueue.pop() {
                guard let work = modelContext.model(for: workId) as? Work else { continue }

                _ = await enrichmentService.enrichWork(work, in: modelContext)
                processedCount += 1
                progressTracker.updateProgress(jobId: jobId, processedItems: processedCount, statusText: "Enriching: \(work.title)")
            }

            progressTracker.completeJob(jobId: jobId, log: ["Enrichment complete."])
        }
    }

    public func getJobStatus(for jobId: JobIdentifier) -> JobStatus? {
        return progressTracker.getStatus(for: jobId)
    }
}