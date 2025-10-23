import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - CSV Import Scale Tests
/// Scale tests to verify performance with 1500+ books as per PRD requirements
@Suite("CSV Import Scale Tests - 1500+ Books")
@MainActor
struct CSVImportScaleTests {

    // MARK: - Test Data Generation

    /// Generates a CSV with the specified number of books
    private func generateTestCSV(bookCount: Int) -> String {
        var csv = "Title,Author,ISBN-13,Rating,Status,Year,Publisher,Notes\n"

        // Popular authors for realistic data
        let authors = [
            "Stephen King", "J.K. Rowling", "George R.R. Martin", "Brandon Sanderson",
            "Neil Gaiman", "Terry Pratchett", "Isaac Asimov", "Arthur C. Clarke",
            "Agatha Christie", "Jane Austen", "Charles Dickens", "Mark Twain",
            "Ernest Hemingway", "Virginia Woolf", "James Joyce", "F. Scott Fitzgerald",
            "Harper Lee", "Maya Angelou", "Toni Morrison", "Gabriel García Márquez",
            "Isabel Allende", "Paulo Coelho", "Haruki Murakami", "Kazuo Ishiguro",
            "Salman Rushdie", "Arundhati Roy", "Chimamanda Ngozi Adichie", "Octavia Butler",
            "N.K. Jemisin", "Liu Cixin", "Ken Liu", "Andy Weir", "Martha Wells",
            "Becky Chambers", "John Scalzi", "Patrick Rothfuss", "Joe Abercrombie",
            "Mark Lawrence", "Robin Hobb", "Ursula K. Le Guin"
        ]

        let publishers = [
            "Penguin Random House", "HarperCollins", "Macmillan", "Simon & Schuster",
            "Hachette", "Tor Books", "Del Rey", "Orbit", "Ace Books", "DAW Books",
            "Baen Books", "Angry Robot", "Saga Press", "Subterranean Press"
        ]

        let statuses = ["read", "reading", "toRead", "wishlist"]

        let bookPrefixes = [
            "The", "A", "An", "Tales of", "Chronicles of", "Adventures of",
            "Journey to", "Return to", "Beyond", "Under", "Above", "Within"
        ]

        let bookSuffixes = [
            "Shadow", "Light", "Darkness", "Dawn", "Twilight", "Storm",
            "Fire", "Ice", "Wind", "Earth", "Sky", "Sea", "Mountain", "Valley",
            "Kingdom", "Empire", "Republic", "City", "World", "Universe",
            "Dream", "Nightmare", "Memory", "Future", "Past", "Present"
        ]

        let genres = [
            "Fantasy", "Science Fiction", "Mystery", "Thriller", "Romance",
            "Historical Fiction", "Literary Fiction", "Horror", "Adventure"
        ]

        for i in 1...bookCount {
            // Generate varied but realistic book data
            let prefix = bookPrefixes.randomElement()!
            let suffix1 = bookSuffixes.randomElement()!
            let suffix2 = bookSuffixes.randomElement()!
            let genre = genres.randomElement()!

            let title = "\(prefix) \(suffix1) \(suffix2) (\(genre) #\(i))"
            let author = authors.randomElement()!

            // Generate ISBN (simplified - not real check digits)
            let isbn = "978\(String(format: "%010d", i))"

            let rating = Int.random(in: 1...5)
            let status = statuses.randomElement()!
            let year = Int.random(in: 1950...2024)
            let publisher = publishers.randomElement()!

            // Some books have notes, some don't
            let notes = i % 3 == 0 ? "Great \(genre.lowercased()) book, highly recommended!" : ""

            // Handle quotes in fields
            let escapedTitle = title.contains("\"") ? title.replacingOccurrences(of: "\"", with: "\"\"") : title
            let quotedTitle = title.contains(",") ? "\"\(escapedTitle)\"" : escapedTitle
            let quotedNotes = notes.isEmpty ? "" : "\"\(notes)\""

            csv += "\(quotedTitle),\(author),\(isbn),\(rating),\(status),\(year),\(publisher),\(quotedNotes)\n"
        }

        return csv
    }

    // MARK: - Scale Tests

    @Test("Imports 1500 books successfully within performance targets")
    func test1500BookImport() async throws {
        // Generate test data
        let csvContent = generateTestCSV(bookCount: 1500)

        // Create in-memory container for testing
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_1500_books.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        let startTime = Date()

        // Load and process file
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        let totalTime = Date().timeIntervalSince(startTime)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Verify results
        switch result {
        case .success(let importResult):
            print("""
            ✅ 1500 Book Import Results:
            - Books imported: \(importResult.successCount)
            - Import time: \(String(format: "%.2f", importResult.duration))s
            - Total time: \(String(format: "%.2f", totalTime))s
            - Books/second: \(String(format: "%.1f", Double(importResult.successCount) / importResult.duration))
            - Errors: \(importResult.errorCount)
            """)

            // Performance requirements from PRD
            #expect(importResult.successCount >= 1450) // Allow for some duplicates/errors
            #expect(importResult.duration < 120) // Should complete within 2 minutes
            #expect(totalTime < 150) // Total including UI updates < 2.5 minutes

            // Verify data integrity
            let works = try modelContext.fetch(FetchDescriptor<Work>())
            #expect(works.count > 0)

            // Verify batch processing worked (no memory issues)
            let memoryUsage = getCurrentMemoryUsage()
            let memoryUsageMB = Double(memoryUsage) / (1024 * 1024)
            print("Memory usage after 1500 books: \(String(format: "%.2f", memoryUsageMB)) MB")
            #expect(memoryUsageMB < 500) // Should stay under 500MB

        case .failure(let error):
            Issue.record("1500 book import failed: \(error)")
        }
    }

    @Test("Imports 3000 books to test extreme scale")
    func test3000BookImport() async throws {
        // Generate test data
        let csvContent = generateTestCSV(bookCount: 3000)

        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_3000_books.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        let startTime = Date()

        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        let totalTime = Date().timeIntervalSince(startTime)

        try? FileManager.default.removeItem(at: tempURL)

        switch result {
        case .success(let importResult):
            print("""
            ✅ 3000 Book Import Results:
            - Books imported: \(importResult.successCount)
            - Import time: \(String(format: "%.2f", importResult.duration))s
            - Books/second: \(String(format: "%.1f", Double(importResult.successCount) / importResult.duration))
            """)

            // Should still complete reasonably fast
            #expect(importResult.duration < 240) // Within 4 minutes
            #expect(importResult.successCount >= 2900)

        case .failure(let error):
            Issue.record("3000 book import failed: \(error)")
        }
    }

    @Test("Handles duplicate detection efficiently at scale")
    func testDuplicateDetectionAtScale() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        // First import: 500 unique books
        let firstCSV = generateTestCSV(bookCount: 500)
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("first_import.csv")
        try firstCSV.write(to: firstURL, atomically: true, encoding: .utf8)

        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(firstCSV)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let firstResult = await importService.importCSV(
            content: firstCSV,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        guard case .success(let firstImportResult) = firstResult else {
            Issue.record("First import failed")
            return
        }

        print("First import: \(firstImportResult.successCount) books")

        // Second import: Same 500 books (should be detected as duplicates)
        let secondResult = await importService.importCSV(
            content: firstCSV,
            mappings: mappings,
            strategy: .skip,
            progressUpdate: { _, _ in }
        )

        guard case .success(let secondImportResult) = secondResult else {
            Issue.record("Second import failed")
            return
        }

        print("""
        Duplicate detection results:
        - Imported: \(secondImportResult.successCount)
        - Duplicates skipped: \(secondImportResult.duplicateCount)
        """)

        // Most should be detected as duplicates
        #expect(secondImportResult.duplicateCount >= 450)
        #expect(secondImportResult.successCount < 50)

        try? FileManager.default.removeItem(at: firstURL)
    }

    // MARK: - Helper Functions

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         pointer,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}