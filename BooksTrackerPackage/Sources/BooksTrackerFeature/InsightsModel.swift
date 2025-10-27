import Foundation
import SwiftData
import SwiftUI

@Observable
final class InsightsModel {
    // MARK: - Diversity Statistics

    var authorGenderDistribution: [AuthorGender: Int] = [:]
    var culturalRegionDistribution: [CulturalRegion: Int] = [:]
    var originalLanguageDistribution: [String: Int] = [:]

    // MARK: - User Reading Statistics

    struct ReadingStats {
        var booksRead: Int = 0
        var pagesRead: Int = 0
        var averagePace: Double = 0 // pages per day
        var averageRating: Double = 0
    }

    var readingStats: ReadingStats = ReadingStats()

    // MARK: - Time Period Filter

    enum TimePeriod: String, CaseIterable, Identifiable {
        case thisYear = "This Year"
        case last90Days = "Last 90 Days"
        case allTime = "All Time"

        var id: Self { self }
    }

    var selectedTimePeriod: TimePeriod = .thisYear

    // MARK: - Data Fetching

    @MainActor
    func fetchData(from modelContext: ModelContext) {
        do {
            // Fetch all works and user library entries
            let works = try modelContext.fetch(FetchDescriptor<Work>())
            let userEntries = try modelContext.fetch(FetchDescriptor<UserLibraryEntry>())

            // Process diversity stats (from all works in the library)
            processDiversityStats(for: works)

            // Process user stats (filtered by time period)
            processUserStats(for: userEntries)

        } catch {
            print("Failed to fetch data for insights: \(error)")
        }
    }

    @MainActor
    private func processDiversityStats(for works: [Work]) {
        var genderDist: [AuthorGender: Int] = [:]
        var regionDist: [CulturalRegion: Int] = [:]
        var languageDist: [String: Int] = [:]

        for work in works {
            if let author = work.primaryAuthor {
                genderDist[author.gender, default: 0] += 1
                if let region = author.culturalRegion {
                    regionDist[region, default: 0] += 1
                }
            }
            if let language = work.originalLanguage, !language.isEmpty {
                languageDist[language, default: 0] += 1
            }
        }

        self.authorGenderDistribution = genderDist
        self.culturalRegionDistribution = regionDist
        self.originalLanguageDistribution = languageDist
    }

    @MainActor
    private func processUserStats(for entries: [UserLibraryEntry]) {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date?

        switch selectedTimePeriod {
        case .thisYear:
            startDate = calendar.date(from: calendar.dateComponents([.year], from: now))
        case .last90Days:
            startDate = calendar.date(byAdding: .day, value: -90, to: now)
        case .allTime:
            startDate = nil
        }

        let filteredEntries = entries.filter { entry in
            guard entry.readingStatus == .read, let completedDate = entry.dateCompleted else {
                return false
            }
            if let startDate = startDate {
                return completedDate >= startDate
            }
            return true
        }

        let booksRead = filteredEntries.count
        let pagesRead = filteredEntries.reduce(0) { $0 + ($1.edition?.pageCount ?? 0) }
        let totalRating = filteredEntries.reduce(0.0) { $0 + ($1.personalRating ?? 0.0) }
        let averageRating = booksRead > 0 ? totalRating / Double(booksRead) : 0.0

        // For average pace, we need to consider all read books, not just in the time period
        let allReadEntries = entries.filter { $0.readingStatus == .read }
        let totalDays = allReadEntries.reduce(0) { total, entry in
            if let start = entry.dateStarted, let end = entry.dateCompleted {
                return total + (calendar.dateComponents([.day], from: start, to: end).day ?? 0)
            }
            return total
        }
        let totalPages = allReadEntries.reduce(0) { $0 + ($1.edition?.pageCount ?? 0) }
        let averagePace = totalDays > 0 ? Double(totalPages) / Double(totalDays) : 0.0

        self.readingStats = ReadingStats(
            booksRead: booksRead,
            pagesRead: pagesRead,
            averagePace: averagePace,
            averageRating: averageRating
        )
    }
}