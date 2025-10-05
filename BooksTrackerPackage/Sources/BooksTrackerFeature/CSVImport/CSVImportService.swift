import Foundation
import SwiftData
import SwiftUI

// MARK: - CSV Import Service
/// Main service for orchestrating CSV imports with duplicate detection and batch processing
@MainActor
public class CSVImportService: ObservableObject {

    // MARK: - Published State

    @Published public var importState: ImportState = .idle
    @Published public var progress: ImportProgress = ImportProgress()
    @Published public var mappings: [CSVParsingActor.ColumnMapping] = []
    @Published public var duplicateStrategy: DuplicateStrategy = .smart

    // MARK: - State Management

    public enum ImportState: Equatable {
        case idle
        case analyzingFile
        case mappingColumns
        case importing
        case completed(ImportResult)
        case failed(String)
    }

    public struct ImportProgress {
        var totalRows: Int = 0
        var processedRows: Int = 0
        var successfulImports: Int = 0
        var skippedDuplicates: Int = 0
        var failedImports: Int = 0
        var currentBook: String = ""
        var startTime: Date?
        var errors: [ImportError] = []

        var percentComplete: Double {
            guard totalRows > 0 else { return 0 }
            return Double(processedRows) / Double(totalRows)
        }

        var estimatedTimeRemaining: TimeInterval? {
            guard let startTime = startTime, processedRows > 0 else { return nil }
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = elapsed / Double(processedRows)
            let remaining = Double(totalRows - processedRows) * rate
            return remaining
        }
    }

    public enum DuplicateStrategy {
        case skip
        case update
        case addNew
        case smart // Uses ISBN match for skip, title+author for update
    }

    public struct ImportError: Identifiable, Equatable {
        public let id = UUID()
        public let row: Int
        public let title: String
        public let message: String

        public static func == (lhs: ImportError, rhs: ImportError) -> Bool {
            lhs.row == rhs.row &&
            lhs.title == rhs.title &&
            lhs.message == rhs.message
        }
    }

    public struct ImportResult: Equatable {
        let successCount: Int
        let duplicateCount: Int
        let errorCount: Int
        let importedWorks: [Work]
        let errors: [ImportError]
        let duration: TimeInterval

        public static func == (lhs: ImportResult, rhs: ImportResult) -> Bool {
            lhs.successCount == rhs.successCount &&
            lhs.duplicateCount == rhs.duplicateCount &&
            lhs.errorCount == rhs.errorCount &&
            lhs.duration == rhs.duration &&
            lhs.importedWorks.count == rhs.importedWorks.count
        }
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let batchSize = 50
    private var csvContent: String = ""
    private var parsedData: (headers: [String], rows: [[String]]) = ([], [])
    private var fileName: String = ""
    private var updateCounter: Int = 0 // For throttling Live Activity updates

    // MARK: - Initialization

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - File Processing

    public func loadFile(at url: URL) async {
        importState = .analyzingFile

        // Store filename for Live Activity
        fileName = url.lastPathComponent

        do {
            // Access security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw ImportServiceError.accessDenied
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Read file content
            csvContent = try String(contentsOf: url, encoding: .utf8)

            // Parse CSV
            parsedData = try await CSVParsingActor.shared.parseCSV(csvContent)

            // Detect columns
            let sampleRows = Array(parsedData.rows.prefix(10))
            mappings = await CSVParsingActor.shared.detectColumns(
                headers: parsedData.headers,
                sampleRows: sampleRows
            )

            // Update progress
            progress.totalRows = parsedData.rows.count

            // Move to mapping state
            importState = .mappingColumns

        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Import Execution

    public func startImport() async {
        guard !parsedData.rows.isEmpty else {
            importState = .failed("No data to import")
            return
        }

        importState = .importing
        progress.startTime = Date()
        progress.errors = []

        // Start Live Activity
        if #available(iOS 16.2, *) {
            do {
                try await CSVImportActivityManager.shared.startActivity(
                    fileName: fileName,
                    totalBooks: parsedData.rows.count
                )
            } catch {
                print("⚠️ Failed to start Live Activity: \(error)")
                // Continue import even if Live Activity fails
            }
        }

        var importedWorks: [Work] = []

        // Process in batches for memory efficiency
        for batchStart in stride(from: 0, to: parsedData.rows.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, parsedData.rows.count)
            let batch = Array(parsedData.rows[batchStart..<batchEnd])

            // Process batch
            let batchResults = await processBatch(
                batch,
                startingRowNumber: batchStart + 2 // +2 for header and 0-based index
            )

            importedWorks.append(contentsOf: batchResults)

            // Save periodically to avoid memory pressure
            if batchEnd % 200 == 0 || batchEnd == parsedData.rows.count {
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save batch: \(error)")
                }
            }

            // Allow UI to update
            await Task.yield()
        }

        // Final save
        do {
            try modelContext.save()
        } catch {
            progress.errors.append(ImportError(
                row: 0,
                title: "Save Failed",
                message: error.localizedDescription
            ))
        }

        // Calculate final results
        let duration = Date().timeIntervalSince(progress.startTime ?? Date())
        let result = ImportResult(
            successCount: progress.successfulImports,
            duplicateCount: progress.skippedDuplicates,
            errorCount: progress.failedImports,
            importedWorks: importedWorks,
            errors: progress.errors,
            duration: duration
        )

        // Queue imported works for background enrichment
        await queueWorksForEnrichment(importedWorks)

        // End Live Activity
        if #available(iOS 16.2, *) {
            let finalMessage = progress.failedImports > 0
                ? "Completed with \(progress.failedImports) errors"
                : "Successfully imported \(progress.successfulImports) books"

            await CSVImportActivityManager.shared.endActivity(finalMessage: finalMessage)
        }

        importState = .completed(result)
    }

    // MARK: - Batch Processing

    private func processBatch(_ rows: [[String]], startingRowNumber: Int) async -> [Work] {
        var importedWorks: [Work] = []

        for (index, row) in rows.enumerated() {
            let rowNumber = startingRowNumber + index

            // Update progress
            progress.processedRows += 1

            // Parse row
            guard let parsedRow = await CSVParsingActor.shared.processRow(
                values: row,
                mappings: mappings
            ) else {
                progress.failedImports += 1
                progress.errors.append(ImportError(
                    row: rowNumber,
                    title: row.first ?? "Unknown",
                    message: "Missing required fields"
                ))
                continue
            }

            progress.currentBook = parsedRow.title

            // Update Live Activity (throttled to every 10 books)
            updateCounter += 1
            if updateCounter % 10 == 0 {
                if #available(iOS 16.2, *) {
                    await CSVImportActivityManager.shared.updateActivity(
                        processedBooks: progress.processedRows,
                        successfulImports: progress.successfulImports,
                        skippedDuplicates: progress.skippedDuplicates,
                        failedImports: progress.failedImports,
                        currentBookTitle: parsedRow.title,
                        estimatedTimeRemaining: progress.estimatedTimeRemaining
                    )
                }
            }

            // Check for duplicates
            if let existingWork = await findExistingWork(parsedRow) {
                switch duplicateStrategy {
                case .skip:
                    progress.skippedDuplicates += 1
                    continue

                case .update:
                    await updateExistingWork(existingWork, with: parsedRow)
                    progress.successfulImports += 1
                    importedWorks.append(existingWork)

                case .addNew:
                    if let newWork = await createNewWork(from: parsedRow) {
                        progress.successfulImports += 1
                        importedWorks.append(newWork)
                    } else {
                        progress.failedImports += 1
                    }

                case .smart:
                    if parsedRow.isbn != nil {
                        // ISBN match - skip duplicate
                        progress.skippedDuplicates += 1
                    } else {
                        // Title+Author match - update
                        await updateExistingWork(existingWork, with: parsedRow)
                        progress.successfulImports += 1
                        importedWorks.append(existingWork)
                    }
                }
            } else {
                // Create new work
                if let newWork = await createNewWork(from: parsedRow) {
                    progress.successfulImports += 1
                    importedWorks.append(newWork)
                } else {
                    progress.failedImports += 1
                    progress.errors.append(ImportError(
                        row: rowNumber,
                        title: parsedRow.title,
                        message: "Failed to create work"
                    ))
                }
            }
        }

        return importedWorks
    }

    // MARK: - Duplicate Detection

    private func findExistingWork(_ row: CSVParsingActor.ParsedRow) async -> Work? {
        // First try ISBN match (highest confidence)
        if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
            // Fetch all editions and filter in memory
            let descriptor = FetchDescriptor<Edition>()
            if let editions = try? modelContext.fetch(descriptor) {
                for edition in editions {
                    // Check both primary ISBN and isbns array
                    if edition.isbn == isbn || edition.isbns.contains(isbn) {
                        return edition.work
                    }
                }
            }
        }

        // Fallback to title + author match
        let titleLower = row.title.lowercased()
        let authorLower = row.author.lowercased()

        // Fetch all works and filter in memory
        let descriptor = FetchDescriptor<Work>()
        if let works = try? modelContext.fetch(descriptor) {
            for work in works where work.title.lowercased() == titleLower {
                if let authors = work.authors {
                    for author in authors {
                        if author.name.lowercased() == authorLower {
                            return work
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Work Creation/Update

    private func createNewWork(from row: CSVParsingActor.ParsedRow) async -> Work? {
        // Create or find author
        let author = findOrCreateAuthor(name: row.author)

        // Create work
        let work = Work(
            title: row.title,
            authors: [author],
            firstPublicationYear: row.publicationYear
        )
        modelContext.insert(work)

        // Create edition if ISBN is provided
        if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
            let edition = Edition(
                isbn: isbn,
                publisher: row.publisher,
                format: .paperback,
                work: work
            )
            modelContext.insert(edition)

            // Create library entry with edition
            let status = ReadingStatus.from(string: row.readStatus) ?? .wishlist
            let entry = UserLibraryEntry.createOwnedEntry(
                for: work,
                edition: edition,
                status: status
            )

            // Add dates if available
            entry.dateStarted = row.dateStarted
            entry.dateCompleted = row.dateFinished ?? row.dateRead

            // Add rating if provided
            if let rating = row.rating,
               rating >= 1.0 && rating <= 5.0 {
                entry.personalRating = rating
            }

            // Add notes if provided
            if let notes = row.notes {
                entry.notes = notes
            }

            modelContext.insert(entry)
        } else {
            // Create wishlist entry without edition
            let entry = UserLibraryEntry.createWishlistEntry(for: work)

            // Update status if provided
            if let statusString = row.readStatus {
                entry.readingStatus = ReadingStatus.from(string: statusString) ?? .wishlist
            }

            modelContext.insert(entry)
        }

        return work
    }

    private func updateExistingWork(_ work: Work, with row: CSVParsingActor.ParsedRow) async {
        // Check if user already has this work in their library
        let existingEntry = work.userLibraryEntries?.first

        if let entry = existingEntry {
            // Update existing entry
            if let rating = row.rating, rating >= 1.0 && rating <= 5.0 {
                entry.personalRating = rating
            }

            if let statusString = row.readStatus {
                entry.readingStatus = ReadingStatus.from(string: statusString) ?? entry.readingStatus
            }

            if let startDate = row.dateStarted {
                entry.dateStarted = startDate
            }

            if let finishDate = row.dateFinished ?? row.dateRead {
                entry.dateCompleted = finishDate
            }

            if let notes = row.notes, !notes.isEmpty {
                entry.notes = notes
            }
        } else {
            // Create new library entry
            let status = ReadingStatus.from(string: row.readStatus) ?? .wishlist

            // Find or create edition if ISBN provided
            var edition: Edition?
            if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
                // Check existing editions for matching ISBN
                if let editions = work.editions {
                    edition = editions.first { $0.isbn == isbn || $0.isbns.contains(isbn) }
                }

                if edition == nil {
                    edition = Edition(
                        isbn: isbn,
                        publisher: row.publisher,
                        format: .paperback,
                        work: work
                    )
                    modelContext.insert(edition!)
                }
            }

            let entry = edition != nil
                ? UserLibraryEntry.createOwnedEntry(for: work, edition: edition!, status: status)
                : UserLibraryEntry.createWishlistEntry(for: work)

            // Set metadata
            entry.dateStarted = row.dateStarted
            entry.dateCompleted = row.dateFinished ?? row.dateRead

            if let rating = row.rating, rating >= 1.0 && rating <= 5.0 {
                entry.personalRating = rating
            }

            if let notes = row.notes {
                entry.notes = notes
            }

            modelContext.insert(entry)
        }
    }

    private func findOrCreateAuthor(name: String) -> Author {
        let nameLower = name.lowercased()

        // Fetch all authors and filter in memory
        let descriptor = FetchDescriptor<Author>()
        if let authors = try? modelContext.fetch(descriptor) {
            if let existing = authors.first(where: { $0.name.lowercased() == nameLower }) {
                return existing
            }
        }

        let author = Author(name: name, gender: .unknown, culturalRegion: nil)
        modelContext.insert(author)
        return author
    }

    // MARK: - Column Mapping

    public func updateMapping(for column: String, to field: CSVParsingActor.ColumnMapping.BookField?) {
        if let index = mappings.firstIndex(where: { $0.csvColumn == column }) {
            mappings[index].mappedField = field
        }
    }

    public func canProceedWithImport() -> Bool {
        // Check that required fields are mapped
        let hasTitle = mappings.contains { $0.mappedField == .title }
        let hasAuthor = mappings.contains { $0.mappedField == .author }
        return hasTitle && hasAuthor
    }

    // MARK: - Background Enrichment

    private func queueWorksForEnrichment(_ works: [Work]) async {
        // Extract persistent IDs for enrichment queue
        let workIDs = works.compactMap { work in
            work.persistentModelID
        }

        // Add to enrichment queue
        await EnrichmentQueue.shared.enqueueBatch(workIDs)

        print("📚 Queued \(workIDs.count) books for background enrichment")

        // Optionally start processing immediately (can be moved to background)
        // await EnrichmentQueue.shared.startProcessing(in: modelContext) { processed, total in
        //     print("Enrichment progress: \(processed)/\(total)")
        // }
    }
}

// MARK: - Import Service Errors

enum ImportServiceError: LocalizedError {
    case accessDenied
    case invalidFile
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Unable to access the selected file"
        case .invalidFile:
            return "The selected file is not a valid CSV"
        case .parsingFailed:
            return "Failed to parse CSV content"
        }
    }
}