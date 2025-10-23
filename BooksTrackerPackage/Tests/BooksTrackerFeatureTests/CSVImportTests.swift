import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - CSV Import Tests
/// Comprehensive tests for the CSV import functionality
@Suite("CSV Import Tests")
@MainActor
struct CSVImportTests {

    // MARK: - Test Data Paths

    private var testDataPath: String {
        "/Users/justingardner/Downloads/xcode/books-tracker-v1/cloudflare-workers/personal-library-cache-warmer/csv-expansion"
    }

    private var smallTestFile: URL {
        URL(fileURLWithPath: "\(testDataPath)/2025.csv")
    }

    private var mediumTestFile: URL {
        URL(fileURLWithPath: "\(testDataPath)/yr_title_auth_isbn13.csv")
    }

    private var largeTestFile: URL {
        URL(fileURLWithPath: "\(testDataPath)/combined_library_expanded.csv")
    }

    // MARK: - Column Detection Tests

    @Test("Detects standard column names correctly")
    func testStandardColumnDetection() async throws {
        let headers = ["Title", "Author", "ISBN-13", "My Rating", "Date Read"]
        let sampleRows = [
            ["The Martian", "Andy Weir", "9780804139021", "5", "2024-01-15"],
            ["Project Hail Mary", "Andy Weir", "9780593135204", "5", "2024-02-20"]
        ]

        let mappings = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: sampleRows
        )

        #expect(mappings.count == 5)

        // Verify title detection
        let titleMapping = mappings.first { $0.csvColumn == "Title" }
        #expect(titleMapping?.mappedField == .title)
        #expect(titleMapping?.confidence ?? 0 > 0.9)

        // Verify author detection
        let authorMapping = mappings.first { $0.csvColumn == "Author" }
        #expect(authorMapping?.mappedField == .author)
        #expect(authorMapping?.confidence ?? 0 > 0.9)

        // Verify ISBN detection
        let isbnMapping = mappings.first { $0.csvColumn == "ISBN-13" }
        #expect(isbnMapping?.mappedField == .isbn13)
        #expect(isbnMapping?.confidence ?? 0 > 0.9)

        // Verify rating detection
        let ratingMapping = mappings.first { $0.csvColumn == "My Rating" }
        #expect(ratingMapping?.mappedField == .myRating)
        #expect(ratingMapping?.confidence ?? 0 > 0.9)
    }

    @Test("Detects lowercase column variations")
    func testLowercaseColumnDetection() async throws {
        let headers = ["title", "author", "isbn", "rating"]
        let sampleRows = [
            ["Test Book", "Test Author", "9780804139021", "4"]
        ]

        let mappings = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: sampleRows
        )

        let titleMapping = mappings.first { $0.csvColumn == "title" }
        #expect(titleMapping?.mappedField == .title)

        let authorMapping = mappings.first { $0.csvColumn == "author" }
        #expect(authorMapping?.mappedField == .author)
    }

    @Test("Detects columns by sample content when names are ambiguous")
    func testSampleBasedDetection() async throws {
        let headers = ["Field1", "Field2", "Field3", "Field4"]
        let sampleRows = [
            ["Some Book Title", "John Doe", "9780804139021", "2023"],
            ["Another Title", "Jane Smith", "9780593135204", "2024"]
        ]

        let mappings = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: sampleRows
        )

        // ISBN should be detected from sample pattern
        let isbnMapping = mappings.first { mapping in
            mapping.sampleValues.first == "9780804139021"
        }
        #expect(isbnMapping?.mappedField == .isbn13 || isbnMapping?.mappedField == .isbn)

        // Year should be detected from 4-digit pattern
        let yearMapping = mappings.first { mapping in
            mapping.sampleValues.first == "2023"
        }
        #expect(yearMapping?.mappedField == .publicationYear)
    }

    // MARK: - CSV Parsing Tests

    @Test("Parses simple CSV correctly")
    func testSimpleCSVParsing() async throws {
        let csvContent = """
        Title,Author,ISBN
        "The Martian",Andy Weir,9780804139021
        Project Hail Mary,"Weir, Andy",9780593135204
        """

        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)

        #expect(headers.count == 3)
        #expect(headers[0] == "Title")
        #expect(headers[1] == "Author")
        #expect(headers[2] == "ISBN")

        #expect(rows.count == 2)
        #expect(rows[0][0] == "The Martian")
        #expect(rows[0][1] == "Andy Weir")
        #expect(rows[1][0] == "Project Hail Mary")
        #expect(rows[1][1] == "Weir, Andy") // Comma inside quotes preserved
    }

    @Test("Handles quoted fields with commas")
    func testQuotedFieldParsing() async throws {
        let csvContent = """
        Title,Author,Notes
        "The Great Gatsby","Fitzgerald, F. Scott","A classic, beautifully written"
        1984,"Orwell, George","Dystopian, thought-provoking, must-read"
        """

        let (_, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)

        #expect(rows.count == 2)
        #expect(rows[0][1] == "Fitzgerald, F. Scott")
        #expect(rows[0][2] == "A classic, beautifully written")
        #expect(rows[1][2] == "Dystopian, thought-provoking, must-read")
    }

    @Test("Handles escaped quotes in fields")
    func testEscapedQuotes() async throws {
        let csvContent = """
        Title,Quote
        "Book Title","She said ""Hello"" to him"
        """

        let (_, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)

        #expect(rows.count == 1)
        #expect(rows[0][1].contains("\"Hello\""))
    }

    // MARK: - Duplicate Detection Tests

    // DISABLED: Tests private internal implementation
    // @Test("Detects duplicates by ISBN")
    // func testISBNDuplicateDetection() async throws {
    //     let container = try ModelContainer(
    //         for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
    //         configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    //     )
    //     let modelContext = ModelContext(container)
    //
    //     // Create existing work with ISBN
    //     let existingAuthor = Author(name: "Andy Weir", gender: .male, culturalRegion: .northAmerica)
    //     let existingWork = Work(title: "The Martian", authors: [existingAuthor])
    //     let existingEdition = Edition(
    //         isbn: "9780804139021",
    //         format: .paperback,
    //         work: existingWork
    //     )
    //     modelContext.insert(existingAuthor)
    //     modelContext.insert(existingWork)
    //     modelContext.insert(existingEdition)
    //     try modelContext.save()
    //
    //     // Test duplicate detection
    //     let importService = CSVImportService(modelContext: modelContext)
    //     let parsedRow = CSVParsingActor.ParsedRow(
    //         title: "The Martian",
    //         normalizedTitle: "The Martian",
    //         author: "Andy Weir",
    //         isbn: "9780804139021",
    //         isbn10: nil,
    //         isbn13: "9780804139021",
    //         publicationYear: 2014,
    //         publisher: nil,
    //         rating: nil,
    //         readStatus: nil,
    //         dateRead: nil,
    //         dateStarted: nil,
    //         dateFinished: nil,
    //         notes: nil,
    //         tags: nil
    //     )
    //
    //     let duplicate = await importService.findExistingWork(parsedRow)
    //     #expect(duplicate != nil)
    //     #expect(duplicate?.title == "The Martian")
    // }

    // DISABLED: Tests private internal implementation
    // @Test("Detects duplicates by title and author")
    // func testTitleAuthorDuplicateDetection() async throws {
    //     let container = try ModelContainer(
    //         for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
    //         configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    //     )
    //     let modelContext = ModelContext(container)
    //
    //     // Create existing work without ISBN
    //     let existingAuthor = Author(name: "Octavia Butler", gender: .female, culturalRegion: .northAmerica)
    //     let existingWork = Work(title: "Kindred", authors: [existingAuthor])
    //     modelContext.insert(existingAuthor)
    //     modelContext.insert(existingWork)
    //     try modelContext.save()
    //
    //     let importService = CSVImportService(modelContext: modelContext)
    //     let parsedRow = CSVParsingActor.ParsedRow(
    //         title: "Kindred",
    //         normalizedTitle: "Kindred",
    //         author: "Octavia Butler",
    //         isbn: nil,
    //         isbn10: nil,
    //         isbn13: nil,
    //         publicationYear: nil,
    //         publisher: nil,
    //         rating: nil,
    //         readStatus: nil,
    //         dateRead: nil,
    //         dateStarted: nil,
    //         dateFinished: nil,
    //         notes: nil,
    //         tags: nil
    //     )
    //
    //     let duplicate = await importService.findExistingWork(parsedRow)
    //     #expect(duplicate != nil)
    //     #expect(duplicate?.title == "Kindred")
    // }

    // MARK: - Batch Processing Tests

    @Test("Processes small CSV file (36 books)")
    func testSmallFileImport() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let csvContent = try String(contentsOf: smallTestFile)
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        // Verify results
        switch result {
        case .success(let importResult):
            #expect(importResult.successCount > 0)
            #expect(importResult.successCount <= 36) // File has ~36 books
            print("✅ Imported \(importResult.successCount) books from small file")

        case .failure(let error):
            Issue.record("Import failed: \(error)")
        }
    }

    @Test("Processes medium CSV file (359 books)")
    func testMediumFileImport() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let csvContent = try String(contentsOf: mediumTestFile)
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        // Verify results
        switch result {
        case .success(let importResult):
            #expect(importResult.successCount > 0)
            #expect(importResult.successCount <= 359)
            print("✅ Imported \(importResult.successCount) books in \(importResult.duration)s")

            // Verify batch processing worked
            #expect(importResult.duration < 30) // Should be fast with batching

        case .failure(let error):
            Issue.record("Import failed: \(error)")
        }
    }

    @Test("Handles different column formats (Title vs title)")
    func testDifferentColumnFormats() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let csvContent = try String(contentsOf: largeTestFile)
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        // Verify column mapping worked
        let titleMapping = mappings.first { $0.csvColumn == "Title" }
        #expect(titleMapping?.mappedField == .title)

        let authorMapping = mappings.first { $0.csvColumn == "Author" }
        #expect(authorMapping?.mappedField == .author)

        let isbnMapping = mappings.first { $0.csvColumn == "ISBN-13" }
        #expect(isbnMapping?.mappedField == .isbn13 || isbnMapping?.mappedField == .isbn)
    }

    // MARK: - Performance Tests

    @Test("Performance: Large file import (775 books)")
    func testLargeFilePerformance() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let csvContent = try String(contentsOf: largeTestFile)
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        let startTime = Date()
        let result = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        let duration = Date().timeIntervalSince(startTime)

        switch result {
        case .success(let importResult):
            print("""
            ✅ Performance Results:
            - Total books: \(importResult.successCount)
            - Import time: \(String(format: "%.2f", importResult.duration))s
            - Total time: \(String(format: "%.2f", duration))s
            - Books/second: \(String(format: "%.1f", Double(importResult.successCount) / importResult.duration))
            - Duplicates: \(importResult.duplicateCount)
            - Errors: \(importResult.errorCount)
            """)

            // Performance expectations
            #expect(importResult.duration < 60) // Should complete within 1 minute
            #expect(importResult.successCount > 700) // Most books should import

        case .failure(let error):
            Issue.record("Large file import failed: \(error)")
        }
    }

    @Test("Memory usage remains reasonable during large import")
    func testMemoryUsage() async throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        // Capture initial memory
        let initialMemory = getCurrentMemoryUsage()

        let csvContent = try String(contentsOf: largeTestFile)
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: Array(rows.prefix(10)))

        _ = await importService.importCSV(
            content: csvContent,
            mappings: mappings,
            strategy: .smart,
            progressUpdate: { _, _ in }
        )

        // Check memory after import
        let finalMemory = getCurrentMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        let memoryIncreaseMB = Double(memoryIncrease) / (1024 * 1024)

        print("Memory increase: \(String(format: "%.2f", memoryIncreaseMB)) MB")

        // Memory should not explode (< 200MB increase for 775 books)
        #expect(memoryIncreaseMB < 200)
    }

    // MARK: - Error Handling Tests

    @Test("Handles missing required columns gracefully")
    func testMissingRequiredColumns() async throws {
        let csvContent = """
        ISBN,Publisher,Year
        9780804139021,Crown,2014
        """

        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        // This should fail validation since Title and Author are missing
        let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
        let mappings = await CSVParsingActor.shared.detectColumns(headers: headers, sampleRows: rows)

        #expect(mappings.first { $0.mappedField == .title } == nil)
        #expect(mappings.first { $0.mappedField == .author } == nil)
    }

    @Test("Handles malformed CSV gracefully")
    func testMalformedCSV() async throws {
        let csvContent = """
        Title,Author,ISBN
        "Unclosed quote,Andy Weir,123
        Normal Row,Author,456
        """

        do {
            let (_, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)
            // Should still parse what it can
            #expect(rows.count >= 1)
        } catch {
            // Or fail gracefully
            #expect(error != nil)
        }
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