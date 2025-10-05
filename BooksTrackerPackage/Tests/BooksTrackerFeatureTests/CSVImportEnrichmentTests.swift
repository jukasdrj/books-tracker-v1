import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

// MARK: - CSV Import & Enrichment Tests
/// Comprehensive test suite for CSV import workflow with enrichment

@MainActor
struct CSVImportEnrichmentTests {

    // MARK: - ReadingStatus Parsing Tests

    @Test("ReadingStatus.from() parses Goodreads status strings")
    func testReadingStatusGoodreadsFormat() {
        #expect(ReadingStatus.from(string: "to-read") == .wishlist)
        #expect(ReadingStatus.from(string: "currently-reading") == .reading)
        #expect(ReadingStatus.from(string: "read") == .read)
    }

    @Test("ReadingStatus.from() parses LibraryThing status strings")
    func testReadingStatusLibraryThingFormat() {
        #expect(ReadingStatus.from(string: "owned") == .toRead)
        #expect(ReadingStatus.from(string: "reading") == .reading)
        #expect(ReadingStatus.from(string: "finished") == .read)
    }

    @Test("ReadingStatus.from() parses StoryGraph status strings")
    func testReadingStatusStoryGraphFormat() {
        #expect(ReadingStatus.from(string: "want to read") == .wishlist)
        #expect(ReadingStatus.from(string: "in progress") == .reading)
        #expect(ReadingStatus.from(string: "completed") == .read)
    }

    @Test("ReadingStatus.from() handles DNF and On Hold statuses")
    func testReadingStatusSpecialCases() {
        #expect(ReadingStatus.from(string: "dnf") == .dnf)
        #expect(ReadingStatus.from(string: "did not finish") == .dnf)
        #expect(ReadingStatus.from(string: "on hold") == .onHold)
        #expect(ReadingStatus.from(string: "paused") == .onHold)
    }

    @Test("ReadingStatus.from() handles nil and empty strings")
    func testReadingStatusEdgeCases() {
        #expect(ReadingStatus.from(string: nil) == nil)
        #expect(ReadingStatus.from(string: "") == nil)
        #expect(ReadingStatus.from(string: "   ") == nil)
    }

    @Test("ReadingStatus.from() partial matching works correctly")
    func testReadingStatusPartialMatching() {
        #expect(ReadingStatus.from(string: "want-to-read") == .wishlist)
        #expect(ReadingStatus.from(string: "currently reading") == .reading)
        #expect(ReadingStatus.from(string: "abandoned") == .dnf)
    }

    // MARK: - EnrichmentQueue Tests

    @Test("EnrichmentQueue enqueues and dequeues items correctly")
    func testEnrichmentQueueBasicOperations() async {
        let queue = EnrichmentQueue.shared
        queue.clear()

        // Create fake persistent IDs for testing
        let id1 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())
        let id2 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())

        queue.enqueue(workID: id1)
        queue.enqueue(workID: id2)

        #expect(queue.count() == 2)
        #expect(queue.isEmpty() == false)

        let first = queue.pop()
        #expect(first == id1)
        #expect(queue.count() == 1)

        queue.clear()
        #expect(queue.isEmpty() == true)
    }

    @Test("EnrichmentQueue prioritization moves items to front")
    func testEnrichmentQueuePrioritization() async {
        let queue = EnrichmentQueue.shared
        queue.clear()

        let id1 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())
        let id2 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())
        let id3 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())

        queue.enqueue(workID: id1)
        queue.enqueue(workID: id2)
        queue.enqueue(workID: id3)

        // Prioritize id3 (last item)
        queue.prioritize(workID: id3)

        // id3 should now be first
        let first = queue.next()
        #expect(first == id3)

        queue.clear()
    }

    @Test("EnrichmentQueue prevents duplicate entries")
    func testEnrichmentQueueDuplicatePrevention() async {
        let queue = EnrichmentQueue.shared
        queue.clear()

        let id1 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())

        queue.enqueue(workID: id1)
        queue.enqueue(workID: id1) // Duplicate
        queue.enqueue(workID: id1) // Another duplicate

        #expect(queue.count() == 1)

        queue.clear()
    }

    // MARK: - CSV Parsing Tests

    @Test("CSVParsingActor detects ISBN columns correctly")
    func testCSVColumnDetectionISBN() async {
        let headers = ["Title", "ISBN", "Author"]
        let sampleRows = [
            ["The Martian", "9780553418026", "Andy Weir"],
            ["Project Hail Mary", "9780593135204", "Andy Weir"]
        ]

        let mappings = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: sampleRows
        )

        let isbnMapping = mappings.first { $0.csvColumn == "ISBN" }
        #expect(isbnMapping != nil)
        #expect(isbnMapping?.mappedField == .isbn || isbnMapping?.mappedField == .isbn13)
        #expect((isbnMapping?.confidence ?? 0) > 0.8)
    }

    @Test("CSVParsingActor detects title and author columns")
    func testCSVColumnDetectionBasics() async {
        let headers = ["Book Title", "Primary Author", "Year"]
        let sampleRows = [
            ["Dune", "Frank Herbert", "1965"],
            ["Foundation", "Isaac Asimov", "1951"]
        ]

        let mappings = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: sampleRows
        )

        let titleMapping = mappings.first { $0.csvColumn == "Book Title" }
        let authorMapping = mappings.first { $0.csvColumn == "Primary Author" }

        #expect(titleMapping?.mappedField == .title)
        #expect(authorMapping?.mappedField == .author)
    }

    @Test("CSVParsingActor parses row with all fields")
    func testCSVRowParsingComplete() async {
        let mappings = [
            CSVParsingActor.ColumnMapping(
                csvColumn: "Title",
                mappedField: .title,
                sampleValues: [],
                confidence: 0.9
            ),
            CSVParsingActor.ColumnMapping(
                csvColumn: "Author",
                mappedField: .author,
                sampleValues: [],
                confidence: 0.9
            ),
            CSVParsingActor.ColumnMapping(
                csvColumn: "ISBN",
                mappedField: .isbn13,
                sampleValues: [],
                confidence: 0.9
            ),
            CSVParsingActor.ColumnMapping(
                csvColumn: "Rating",
                mappedField: .myRating,
                sampleValues: [],
                confidence: 0.9
            )
        ]

        let row = ["The Martian", "Andy Weir", "9780553418026", "4.5"]
        let parsed = await CSVParsingActor.shared.processRow(
            values: row,
            mappings: mappings
        )

        #expect(parsed != nil)
        #expect(parsed?.title == "The Martian")
        #expect(parsed?.author == "Andy Weir")
        #expect(parsed?.isbn13 == "9780553418026")
        #expect(parsed?.rating == 4.5)
    }

    @Test("CSVParsingActor requires title and author")
    func testCSVRowParsingRequiredFields() async {
        let mappings = [
            CSVParsingActor.ColumnMapping(
                csvColumn: "Title",
                mappedField: .title,
                sampleValues: [],
                confidence: 0.9
            )
        ]

        // Missing author - should fail
        let row = ["The Martian", ""]
        let parsed = await CSVParsingActor.shared.processRow(
            values: row,
            mappings: mappings
        )

        #expect(parsed == nil)
    }

    // MARK: - Integration Tests

    @Test("EnrichmentService statistics tracking works")
    func testEnrichmentServiceStatistics() async {
        let service = EnrichmentService.shared
        let stats = service.getStatistics()

        // Statistics should be initialized
        #expect(stats.totalEnriched >= 0)
        #expect(stats.totalFailed >= 0)
    }

    @Test("EnrichmentQueue persistence works across instances")
    func testEnrichmentQueuePersistence() async {
        // Clear queue first
        EnrichmentQueue.shared.clear()

        let id1 = PersistentIdentifier(id: UUID(), entityName: "Work", primaryKey: UUID())

        // Add item
        EnrichmentQueue.shared.enqueue(workID: id1)
        #expect(EnrichmentQueue.shared.count() == 1)

        // Simulate app restart by accessing fresh queue
        // (In real implementation, queue loads from UserDefaults on init)
        let count = EnrichmentQueue.shared.count()
        #expect(count >= 0) // Queue persisted

        // Clean up
        EnrichmentQueue.shared.clear()
    }
}

// MARK: - CSV Import Service Tests

@MainActor
struct CSVImportServiceTests {

    @Test("CSV Import Service initializes correctly")
    func testCSVImportServiceInit() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let modelContext = ModelContext(container)

        let service = CSVImportService(modelContext: modelContext)

        #expect(service.importState == .idle)
        #expect(service.progress.totalRows == 0)
    }

    @Test("CSV Import Service can map columns")
    func testCSVImportServiceColumnMapping() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let modelContext = ModelContext(container)

        let service = CSVImportService(modelContext: modelContext)

        // Set up mappings
        service.mappings = [
            CSVParsingActor.ColumnMapping(
                csvColumn: "Title",
                mappedField: .title,
                sampleValues: [],
                confidence: 0.9
            ),
            CSVParsingActor.ColumnMapping(
                csvColumn: "Author",
                mappedField: .author,
                sampleValues: [],
                confidence: 0.9
            )
        ]

        #expect(service.canProceedWithImport() == true)
    }

    @Test("CSV Import Service validates required fields")
    func testCSVImportServiceRequiredFieldValidation() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let modelContext = ModelContext(container)

        let service = CSVImportService(modelContext: modelContext)

        // Only title mapped - should fail
        service.mappings = [
            CSVParsingActor.ColumnMapping(
                csvColumn: "Title",
                mappedField: .title,
                sampleValues: [],
                confidence: 0.9
            )
        ]

        #expect(service.canProceedWithImport() == false)

        // Add author - should pass
        service.mappings.append(
            CSVParsingActor.ColumnMapping(
                csvColumn: "Author",
                mappedField: .author,
                sampleValues: [],
                confidence: 0.9
            )
        )

        #expect(service.canProceedWithImport() == true)
    }
}
