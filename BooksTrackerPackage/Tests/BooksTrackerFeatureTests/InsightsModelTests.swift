import Testing
@testable import BooksTrackerFeature
import SwiftData
import Foundation

@MainActor
struct InsightsModelTests {

    let modelContainer: ModelContainer
    let insightsModel: InsightsModel

    init() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            modelContainer = try ModelContainer(for: Work.self, Author.self, Edition.self, UserLibraryEntry.self, configurations: config)
            insightsModel = InsightsModel()
            setupTestData()
        } catch {
            fatalError("Failed to create model container for tests: \(error)")
        }
    }

    func setupTestData() {
        let author1 = Author(name: "Author 1", gender: .female, culturalRegion: .northAmerica)
        let author2 = Author(name: "Author 2", gender: .male, culturalRegion: .europe)
        let author3 = Author(name: "Author 3", gender: .nonBinary, culturalRegion: .asia)
        modelContainer.mainContext.insert(author1)
        modelContainer.mainContext.insert(author2)
        modelContainer.mainContext.insert(author3)

        let work1 = Work(title: "Work 1", authors: [author1], originalLanguage: "English")
        let work2 = Work(title: "Work 2", authors: [author2], originalLanguage: "French")
        let work3 = Work(title: "Work 3", authors: [author3], originalLanguage: "English")
        modelContainer.mainContext.insert(work1)
        modelContainer.mainContext.insert(work2)
        modelContainer.mainContext.insert(work3)

        let edition1 = Edition(pageCount: 100, work: work1)
        let edition2 = Edition(pageCount: 200, work: work2)
        let edition3 = Edition(pageCount: 300, work: work3)
        modelContainer.mainContext.insert(edition1)
        modelContainer.mainContext.insert(edition2)
        modelContainer.mainContext.insert(edition3)

        let entry1 = UserLibraryEntry.createOwnedEntry(for: work1, edition: edition1, status: .read)
        entry1.dateCompleted = Date() // This year
        entry1.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        entry1.personalRating = 4.0

        let entry2 = UserLibraryEntry.createOwnedEntry(for: work2, edition: edition2, status: .read)
        entry2.dateCompleted = Calendar.current.date(byAdding: .year, value: -1, to: Date())! // Last year
        entry2.dateStarted = Calendar.current.date(byAdding: .day, value: -20, to: entry2.dateCompleted!)!
        entry2.personalRating = 5.0

        let entry3 = UserLibraryEntry.createOwnedEntry(for: work3, edition: edition3, status: .reading)

        modelContainer.mainContext.insert(entry1)
        modelContainer.mainContext.insert(entry2)
        modelContainer.mainContext.insert(entry3)
    }

    @Test
    func testFetchDataThisYear() {
        insightsModel.selectedTimePeriod = .thisYear
        insightsModel.fetchData(from: modelContainer.mainContext)

        #expect(insightsModel.readingStats.booksRead == 1)
        #expect(insightsModel.readingStats.pagesRead == 100)
        #expect(insightsModel.readingStats.averageRating == 4.0)
    }

    @Test
    func testFetchDataAllTime() {
        insightsModel.selectedTimePeriod = .allTime
        insightsModel.fetchData(from: modelContainer.mainContext)

        #expect(insightsModel.readingStats.booksRead == 2)
        #expect(insightsModel.readingStats.pagesRead == 300)
        #expect(insightsModel.readingStats.averageRating, closeTo: 4.5, tolerance: 0.01)
    }

    @Test
    func testDiversityStats() {
        insightsModel.fetchData(from: modelContainer.mainContext)

        #expect(insightsModel.authorGenderDistribution[.female] == 1)
        #expect(insightsModel.authorGenderDistribution[.male] == 1)
        #expect(insightsModel.authorGenderDistribution[.nonBinary] == 1)

        #expect(insightsModel.culturalRegionDistribution[.northAmerica] == 1)
        #expect(insightsModel.culturalRegionDistribution[.europe] == 1)
        #expect(insightsModel.culturalRegionDistribution[.asia] == 1)

        #expect(insightsModel.originalLanguageDistribution["English"] == 2)
        #expect(insightsModel.originalLanguageDistribution["French"] == 1)
    }
}

// Helper for floating point comparison
func #expect(_ expression1: @autoclosure () throws -> Double, closeTo expression2: @autoclosure () throws -> Double, tolerance: Double) {
    let value1 = try! expression1()
    let value2 = try! expression2()
    #expect(abs(value1 - value2) < tolerance)
}