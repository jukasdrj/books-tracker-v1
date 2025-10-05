import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - CSV Import Scale Tests
/// Scale tests to verify performance with 1500+ books as per PRD requirements
@Suite("CSV Import Scale Tests - 1500+ Books")
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
        await importService.loadFile(at: tempURL)

        // Verify column detection worked
        #expect(importService.canProceedWithImport())

        // Start import
        await importService.startImport()

        let totalTime = Date().timeIntervalSince(startTime)

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        // Verify results
        switch importService.importState {
        case .completed(let result):
            print("""
            ✅ 1500 Book Import Results:
            - Books imported: \(result.successCount)
            - Import time: \(String(format: "%.2f", result.duration))s
            - Total time: \(String(format: "%.2f", totalTime))s
            - Books/second: \(String(format: "%.1f", Double(result.successCount) / result.duration))
            - Errors: \(result.errorCount)
            """)

            // Performance requirements from PRD
            #expect(result.successCount >= 1450) // Allow for some duplicates/errors
            #expect(result.duration < 120) // Should complete within 2 minutes
            #expect(totalTime < 150) // Total including UI updates < 2.5 minutes

            // Verify data integrity
            let works = try modelContext.fetch(FetchDescriptor<Work>())
            #expect(works.count > 0)

            // Verify batch processing worked (no memory issues)
            let memoryUsage = getCurrentMemoryUsage()
            let memoryUsageMB = Double(memoryUsage) / (1024 * 1024)
            print("Memory usage after 1500 books: \(String(format: "%.2f", memoryUsageMB)) MB")
            #expect(memoryUsageMB < 500) // Should stay under 500MB

        case .failed(let error):
            Issue.record("1500 book import failed: \(error)")

        default:
            Issue.record("Unexpected import state")
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

        await importService.loadFile(at: tempURL)
        await importService.startImport()

        let totalTime = Date().timeIntervalSince(startTime)

        try? FileManager.default.removeItem(at: tempURL)

        switch importService.importState {
        case .completed(let result):
            print("""
            ✅ 3000 Book Import Results:
            - Books imported: \(result.successCount)
            - Import time: \(String(format: "%.2f", result.duration))s
            - Books/second: \(String(format: "%.1f", Double(result.successCount) / result.duration))
            """)

            // Should still complete reasonably fast
            #expect(result.duration < 240) // Within 4 minutes
            #expect(result.successCount >= 2900)

        case .failed(let error):
            Issue.record("3000 book import failed: \(error)")

        default:
            Issue.record("Unexpected state")
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

        await importService.loadFile(at: firstURL)
        await importService.startImport()

        guard case .completed(let firstResult) = importService.importState else {
            Issue.record("First import failed")
            return
        }

        print("First import: \(firstResult.successCount) books")

        // Second import: Same 500 books (should be detected as duplicates)
        importService.importState = .idle // Reset state
        importService.duplicateStrategy = .skip

        await importService.loadFile(at: firstURL)
        await importService.startImport()

        guard case .completed(let secondResult) = importService.importState else {
            Issue.record("Second import failed")
            return
        }

        print("""
        Duplicate detection results:
        - Imported: \(secondResult.successCount)
        - Duplicates skipped: \(secondResult.duplicateCount)
        """)

        // Most should be detected as duplicates
        #expect(secondResult.duplicateCount >= 450)
        #expect(secondResult.successCount < 50)

        try? FileManager.default.removeItem(at: firstURL)
    }

    @Test("Progress tracking remains responsive during large imports")
    func testProgressTracking() async throws {
        let csvContent = generateTestCSV(bookCount: 1000)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress_test.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        await importService.loadFile(at: tempURL)

        // Track progress updates
        var progressUpdates: [Double] = []
        var lastProgress: Double = 0

        // Start import and monitor progress
        Task {
            await importService.startImport()
        }

        // Monitor progress for up to 60 seconds
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(500))

            let currentProgress = importService.progress.percentComplete
            if currentProgress != lastProgress {
                progressUpdates.append(currentProgress)
                lastProgress = currentProgress

                print("Progress: \(String(format: "%.1f", currentProgress * 100))% - \(importService.progress.currentBook)")
            }

            if case .completed = importService.importState {
                break
            }
        }

        // Verify progress was updated regularly
        #expect(progressUpdates.count > 10) // Should have many progress updates
        #expect(progressUpdates.last ?? 0 >= 0.95) // Should reach near 100%

        // Verify progress was incremental
        for i in 1..<progressUpdates.count {
            #expect(progressUpdates[i] >= progressUpdates[i-1]) // Progress should never go backwards
        }

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - UI Responsiveness Test

    @Test("UI remains responsive during import")
    @MainActor
    func testUIResponsiveness() async throws {
        let csvContent = generateTestCSV(bookCount: 500)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = ModelContext(container)
        let importService = CSVImportService(modelContext: modelContext)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui_test.csv")
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

        await importService.loadFile(at: tempURL)

        // Track main thread blocks
        var maxBlockTime: TimeInterval = 0
        let blockCheckTask = Task { @MainActor in
            while true {
                let start = Date()
                try await Task.sleep(for: .milliseconds(16)) // 60fps frame time

                let elapsed = Date().timeIntervalSince(start)
                if elapsed > 0.033 { // More than 2 frames
                    maxBlockTime = max(maxBlockTime, elapsed)
                }

                if case .completed = importService.importState {
                    break
                }
            }
        }

        await importService.startImport()
        blockCheckTask.cancel()

        print("Max main thread block: \(String(format: "%.3f", maxBlockTime))s")

        // Main thread should never be blocked for more than 100ms
        #expect(maxBlockTime < 0.1)

        try? FileManager.default.removeItem(at: tempURL)
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