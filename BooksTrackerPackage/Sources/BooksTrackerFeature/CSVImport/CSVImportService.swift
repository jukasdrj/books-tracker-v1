import Foundation
import SwiftData
import SwiftUI

// MARK: - CSV Import Service
/// Dual-mode service supporting both legacy ObservableObject pattern and new Result-based API
/// - Legacy: @Published state for existing views (backward compatibility)
/// - Modern: Result-based API for SyncCoordinator integration
@MainActor
public class CSVImportService {

    private let modelContext: ModelContext

    // MARK: - Initialization

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Stateless Result-Based API (for SyncCoordinator)

    /// Import CSV with progress callbacks (stateless - no @Published state)
    /// This is the new API that SyncCoordinator should use
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
        var errorCount = 0
        var errors: [ImportError] = []

        do {
            // Parse CSV
            let (_, rows) = try await CSVParsingActor.shared.parseCSV(content)

            // Process in batches
            for (index, row) in rows.enumerated() {
                progressUpdate(index + 1, "Processing row \(index + 1) of \(rows.count)")

                // Parse row
                guard let parsedRow = await CSVParsingActor.shared.processRow(
                    values: row,
                    mappings: mappings
                ) else {
                    errorCount += 1
                    errors.append(ImportError(
                        row: index + 2, // +2 for header and 0-based index
                        title: row.first ?? "Unknown",
                        message: "Missing required fields"
                    ))
                    continue
                }

                // Check for duplicates
                if let existingWork = await findExistingWork(parsedRow) {
                    switch strategy {
                    case .skip:
                        duplicateCount += 1
                        continue

                    case .update:
                        await updateExistingWork(existingWork, with: parsedRow)
                        successCount += 1
                        importedWorks.append(existingWork)

                    case .addNew:
                        if let newWork = await createNewWork(from: parsedRow) {
                            successCount += 1
                            importedWorks.append(newWork)
                        } else {
                            errorCount += 1
                        }

                    case .smart:
                        if parsedRow.isbn != nil {
                            // ISBN match - skip duplicate
                            duplicateCount += 1
                        } else {
                            // Title+Author match - update
                            await updateExistingWork(existingWork, with: parsedRow)
                            successCount += 1
                            importedWorks.append(existingWork)
                        }
                    }
                } else {
                    // Create new work
                    if let newWork = await createNewWork(from: parsedRow) {
                        successCount += 1
                        importedWorks.append(newWork)
                    } else {
                        errorCount += 1
                        errors.append(ImportError(
                            row: index + 2,
                            title: parsedRow.title,
                            message: "Failed to create work"
                        ))
                    }
                }

                // Save periodically
                if (index + 1) % 50 == 0 {
                    try modelContext.save()
                }
            }

            // Final save
            try modelContext.save()

            let duration = Date().timeIntervalSince(startTime)
            let result = ImportResult(
                successCount: successCount,
                duplicateCount: duplicateCount,
                errorCount: errorCount,
                importedWorks: importedWorks,
                errors: errors,
                duration: duration
            )

            return .success(result)

        } catch {
            return .failure(error)
        }
    }

    /// Get total row count from CSV (for progress tracking)
    public func getRowCount(from csvContent: String) async -> Int {
        let parsedData = try? await CSVParsingActor.shared.parseCSV(csvContent)
        return parsedData?.rows.count ?? 0
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

        // Store original title from CSV for display and user library
        // Normalized title (row.normalizedTitle) is used only during enrichment search
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

    // MARK: - Background Enrichment

    private func queueWorksForEnrichment(_ works: [Work]) async {
        // Extract persistent IDs for enrichment queue
        let workIDs = works.compactMap { work in
            work.persistentModelID
        }

        // Add to enrichment queue
        EnrichmentQueue.shared.enqueueBatch(workIDs)

        print("📚 Queued \(workIDs.count) books for background enrichment")

        // Start processing immediately in background with Live Activity updates
        // Use regular Task (not detached) since EnrichmentQueue is @MainActor isolated
        // Capture modelContext explicitly for Swift 6 concurrency
        let context = self.modelContext
        Task(priority: .utility) {
            EnrichmentQueue.shared.startProcessing(in: context) { processed, total, currentTitle in
                // Console logging
                print("📖 Enrichment progress: \(processed)/\(total)")

                // Update Live Activity
                if #available(iOS 16.2, *) {
                    Task {
                        await CSVImportActivityManager.shared.updateEnrichmentProgress(
                            enrichedBooks: processed,
                            totalBooks: total,
                            currentBookTitle: currentTitle
                        )
                    }
                }

                // End Live Activity when enrichment completes
                if processed >= total {
                    if #available(iOS 16.2, *) {
                        Task {
                            await CSVImportActivityManager.shared.endActivity(
                                finalMessage: "Enrichment complete! \(processed) books enriched",
                                dismissAfter: 4.0
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Supporting Types

    /// Strategy for handling duplicate entries during CSV import.
    public enum DuplicateStrategy: String, Sendable, CaseIterable, Identifiable {
        /// Skip any rows that match an existing book.
        case skip = "Skip Duplicates"

        /// Update existing book data with information from the CSV.
        case update = "Update Existing"

        /// Create a new entry, even if it duplicates an existing book.
        case addNew = "Add as New"

        /// Smartly decide whether to skip or update based on data quality.
        case smart = "Smart Update"

        public var id: String { self.rawValue }
    }

    /// Represents the result of a CSV import operation.
    /// Note: NOT Sendable because it contains SwiftData models (Work)
    /// which are reference types. This is consumed only on @MainActor.
    public struct ImportResult {
        /// The number of successfully imported books.
        public let successCount: Int

        /// The number of rows skipped as duplicates.
        public let duplicateCount: Int

        /// The number of rows that resulted in an error.
        public let errorCount: Int

        /// An array of the Work objects that were successfully imported.
        public let importedWorks: [Work]

        /// A list of errors encountered during the import.
        public let errors: [ImportError]

        /// The total duration of the import operation in seconds.
        public let duration: TimeInterval
    }

    /// Represents a single error during the CSV import process.
    public struct ImportError: Sendable, Identifiable, Error {
        public var id = UUID()

        /// The row number in the CSV file where the error occurred.
        public let row: Int

        /// The title of the book associated with the error, if available.
        public let title: String

        /// A message describing the error.
        public let message: String
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