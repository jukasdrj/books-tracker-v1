import Foundation
import SwiftData
import SwiftUI

@MainActor
public class CSVImportService {

    // MARK: - State Management

    public enum DuplicateStrategy {
        case skip
        case update
        case addNew
        case smart
    }

    public struct ImportError: Identifiable, Equatable {
        public let id = UUID()
        public let row: Int
        public let title: String
        public let message: String
    }

    public struct ImportResult {
        let successCount: Int
        let duplicateCount: Int
        let errorCount: Int
        let importedWorks: [Work]
        let errors: [ImportError]
        let duration: TimeInterval
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let batchSize = 50

    // MARK: - Initialization

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    public func getRowCount(from csvContent: String) async -> Int {
        let parsedData = try? await CSVParsingActor.shared.parseCSV(csvContent)
        return parsedData?.rows.count ?? 0
    }

    public func importCsv(
        content: String,
        mappings: [CSVParsingActor.ColumnMapping],
        strategy: DuplicateStrategy,
        progressUpdate: @escaping (Int, String) -> Void
    ) async -> Result<ImportResult, Error> {

        let startTime = Date()
        var errors: [ImportError] = []
        var importedWorks: [Work] = []
        var successfulImports = 0
        var skippedDuplicates = 0
        var failedImports = 0

        do {
            let parsedData = try await CSVParsingActor.shared.parseCSV(content)
            let rows = parsedData.rows

            for (index, row) in rows.enumerated() {
                let rowNumber = index + 2

                guard let parsedRow = await CSVParsingActor.shared.processRow(values: row, mappings: mappings) else {
                    failedImports += 1
                    errors.append(ImportError(row: rowNumber, title: row.first ?? "Unknown", message: "Missing required fields"))
                    continue
                }

                progressUpdate(index + 1, "Importing: \(parsedRow.title)")

                if let existingWork = await findExistingWork(parsedRow) {
                    switch strategy {
                    case .skip:
                        skippedDuplicates += 1
                    case .update:
                        await updateExistingWork(existingWork, with: parsedRow)
                        successfulImports += 1
                        importedWorks.append(existingWork)
                    case .addNew:
                        if let newWork = await createNewWork(from: parsedRow) {
                            successfulImports += 1
                            importedWorks.append(newWork)
                        } else {
                            failedImports += 1
                        }
                    case .smart:
                        if parsedRow.isbn != nil {
                            skippedDuplicates += 1
                        } else {
                            await updateExistingWork(existingWork, with: parsedRow)
                            successfulImports += 1
                            importedWorks.append(existingWork)
                        }
                    }
                } else {
                    if let newWork = await createNewWork(from: parsedRow) {
                        successfulImports += 1
                        importedWorks.append(newWork)
                    } else {
                        failedImports += 1
                        errors.append(ImportError(row: rowNumber, title: parsedRow.title, message: "Failed to create work"))
                    }
                }
            }

            try modelContext.save()

            let duration = Date().timeIntervalSince(startTime)
            let result = ImportResult(
                successCount: successfulImports,
                duplicateCount: skippedDuplicates,
                errorCount: failedImports,
                importedWorks: importedWorks,
                errors: errors,
                duration: duration
            )

            return .success(result)

        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private Methods

    private func findExistingWork(_ row: CSVParsingActor.ParsedRow) async -> Work? {
        if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
            let descriptor = FetchDescriptor<Edition>()
            if let editions = try? modelContext.fetch(descriptor) {
                for edition in editions where edition.isbn == isbn || edition.isbns.contains(isbn) {
                    return edition.work
                }
            }
        }

        let titleLower = row.title.lowercased()
        let authorLower = row.author.lowercased()

        let descriptor = FetchDescriptor<Work>()
        if let works = try? modelContext.fetch(descriptor) {
            for work in works where work.title.lowercased() == titleLower {
                if let authors = work.authors {
                    for author in authors where author.name.lowercased() == authorLower {
                        return work
                    }
                }
            }
        }

        return nil
    }

    private func createNewWork(from row: CSVParsingActor.ParsedRow) async -> Work? {
        let author = findOrCreateAuthor(name: row.author)
        let work = Work(title: row.title, authors: [author], firstPublicationYear: row.publicationYear)
        modelContext.insert(work)

        if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
            let edition = Edition(isbn: isbn, publisher: row.publisher, format: .paperback, work: work)
            modelContext.insert(edition)

            let status = ReadingStatus.from(string: row.readStatus) ?? .wishlist
            let entry = UserLibraryEntry.createOwnedEntry(for: work, edition: edition, status: status)
            entry.dateStarted = row.dateStarted
            entry.dateCompleted = row.dateFinished ?? row.dateRead
            if let rating = row.rating, rating >= 1.0 && rating <= 5.0 {
                entry.personalRating = rating
            }
            if let notes = row.notes {
                entry.notes = notes
            }
            modelContext.insert(entry)
        } else {
            let entry = UserLibraryEntry.createWishlistEntry(for: work)
            if let statusString = row.readStatus {
                entry.readingStatus = ReadingStatus.from(string: statusString) ?? .wishlist
            }
            modelContext.insert(entry)
        }

        return work
    }

    private func updateExistingWork(_ work: Work, with row: CSVParsingActor.ParsedRow) async {
        if let entry = work.userLibraryEntries?.first {
            if let rating = row.rating, rating >= 1.0 && rating <= 5.0 { entry.personalRating = rating }
            if let statusString = row.readStatus { entry.readingStatus = ReadingStatus.from(string: statusString) ?? entry.readingStatus }
            if let startDate = row.dateStarted { entry.dateStarted = startDate }
            if let finishDate = row.dateFinished ?? row.dateRead { entry.dateCompleted = finishDate }
            if let notes = row.notes, !notes.isEmpty { entry.notes = notes }
        } else {
            let status = ReadingStatus.from(string: row.readStatus) ?? .wishlist
            var edition: Edition?
            if let isbn = row.isbn13 ?? row.isbn ?? row.isbn10 {
                if let editions = work.editions {
                    edition = editions.first { $0.isbn == isbn || $0.isbns.contains(isbn) }
                }
                if edition == nil {
                    edition = Edition(isbn: isbn, publisher: row.publisher, format: .paperback, work: work)
                    modelContext.insert(edition!)
                }
            }
            let entry = edition != nil ? UserLibraryEntry.createOwnedEntry(for: work, edition: edition!, status: status) : UserLibraryEntry.createWishlistEntry(for: work)
            entry.dateStarted = row.dateStarted
            entry.dateCompleted = row.dateFinished ?? row.dateRead
            if let rating = row.rating, rating >= 1.0 && rating <= 5.0 { entry.personalRating = rating }
            if let notes = row.notes { entry.notes = notes }
            modelContext.insert(entry)
        }
    }

    private func findOrCreateAuthor(name: String) -> Author {
        let nameLower = name.lowercased()
        let descriptor = FetchDescriptor<Author>()
        if let authors = try? modelContext.fetch(descriptor), let existing = authors.first(where: { $0.name.lowercased() == nameLower }) {
            return existing
        }
        let author = Author(name: name, gender: .unknown, culturalRegion: nil)
        modelContext.insert(author)
        return author
    }
}

enum ImportServiceError: LocalizedError {
    case accessDenied
    case invalidFile
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Unable to access the selected file"
        case .invalidFile: return "The selected file is not a valid CSV"
        case .parsingFailed: return "Failed to parse CSV content"
        }
    }
}