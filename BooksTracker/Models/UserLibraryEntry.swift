import Foundation
import SwiftData
import SwiftUI

@Model
final class UserLibraryEntry: Identifiable {
    var id: UUID = UUID()
    var dateAdded: Date = Date()
    var readingStatus: ReadingStatus = .toRead
    var currentPage: Int = 0
    var readingProgress: Double = 0.0 // 0.0 to 1.0
    var rating: Int? // 1-5 stars
    var notes: String?
    var tags: [String] = []

    // Reading tracking
    var dateStarted: Date?
    var dateCompleted: Date?
    var estimatedFinishDate: Date?

    // Metadata
    var lastModified: Date = Date()

    // Relationships
    @Relationship
    var work: Work?

    @Relationship
    var edition: Edition? // Nil for wishlist items (don't own yet)

    init(
        work: Work,
        edition: Edition? = nil,
        readingStatus: ReadingStatus = .toRead
    ) {
        self.work = work
        self.edition = edition
        self.readingStatus = readingStatus
        self.dateAdded = Date()
        self.lastModified = Date()
    }

    /// Create wishlist entry (want to read but don't own)
    static func createWishlistEntry(for work: Work) -> UserLibraryEntry {
        let entry = UserLibraryEntry(work: work, edition: nil, readingStatus: .wishlist)
        return entry
    }

    /// Create owned entry (have specific edition)
    static func createOwnedEntry(for work: Work, edition: Edition, status: ReadingStatus = .toRead) -> UserLibraryEntry {
        let entry = UserLibraryEntry(work: work, edition: edition, readingStatus: status)
        return entry
    }

    // MARK: - Reading Progress Methods

    /// Update reading progress based on current page and edition page count
    func updateReadingProgress() {
        // Can't track progress for wishlist items (no edition)
        guard readingStatus != .wishlist,
              let pageCount = edition?.pageCount,
              pageCount > 0 else {
            readingProgress = 0.0
            return
        }

        readingProgress = min(Double(currentPage) / Double(pageCount), 1.0)

        // Auto-complete if progress reaches 100%
        if readingProgress >= 1.0 && readingStatus != .read {
            markAsCompleted()
        }
    }

    /// Mark the book as completed
    func markAsCompleted() {
        readingStatus = .read
        readingProgress = 1.0
        if dateCompleted == nil {
            dateCompleted = Date()
        }
        if dateStarted == nil {
            dateStarted = Date()
        }
        if let pageCount = edition?.pageCount {
            currentPage = pageCount
        }
        touch()
    }

    /// Start reading the book (only if owned)
    func startReading() {
        guard readingStatus != .wishlist, edition != nil else {
            // Can't start reading a wishlist item - need to acquire edition first
            return
        }

        if readingStatus == .toRead {
            readingStatus = .reading
            if dateStarted == nil {
                dateStarted = Date()
            }
            touch()
        }
    }

    /// Convert wishlist entry to owned entry
    func acquireEdition(_ edition: Edition, status: ReadingStatus = .toRead) {
        guard readingStatus == .wishlist else { return }

        self.edition = edition
        self.readingStatus = status
        touch()
    }

    /// Check if this is a wishlist entry
    var isWishlistItem: Bool {
        return readingStatus == .wishlist && edition == nil
    }

    /// Check if user owns this entry
    var isOwned: Bool {
        return !isWishlistItem
    }

    /// Calculate reading pace (pages per day)
    var readingPace: Double? {
        guard let started = dateStarted,
              currentPage > 0,
              started < Date() else { return nil }

        let daysSinceStart = Calendar.current.dateComponents([.day], from: started, to: Date()).day ?? 1
        return Double(currentPage) / Double(max(daysSinceStart, 1))
    }

    /// Estimate finish date based on current pace and remaining pages
    func calculateEstimatedFinishDate() {
        guard let pageCount = edition?.pageCount,
              let pace = readingPace,
              pace > 0,
              currentPage < pageCount else {
            estimatedFinishDate = nil
            return
        }

        let remainingPages = pageCount - currentPage
        let daysToFinish = Double(remainingPages) / pace
        estimatedFinishDate = Calendar.current.date(byAdding: .day, value: Int(ceil(daysToFinish)), to: Date())
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }

    // MARK: - Validation

    /// Validate rating is within acceptable range
    func validateRating() -> Bool {
        guard let rating = rating else { return true }
        return (1...5).contains(rating)
    }

    /// Validate notes length
    func validateNotes() -> Bool {
        guard let notes = notes else { return true }
        return notes.count <= 2000
    }
}

// MARK: - Reading Status Enum
enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case wishlist = "Wishlist"     // Want to have/read but don't own
    case toRead = "TBR"            // Have it and want to read in the future
    case reading = "Reading"       // Currently reading
    case read = "Read"             // Finished reading
    case onHold = "On Hold"        // Started but paused
    case dnf = "DNF"               // Did not finish

    var id: Self { self }

    var displayName: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .toRead: return "To Read"
        case .reading: return "Reading"
        case .read: return "Read"
        case .onHold: return "On Hold"
        case .dnf: return "Did Not Finish"
        }
    }

    var description: String {
        switch self {
        case .wishlist: return "Want to have or read, but don't have"
        case .toRead: return "Have it and want to read in the future"
        case .reading: return "Currently reading"
        case .read: return "Finished reading"
        case .onHold: return "Started reading but paused"
        case .dnf: return "Started but did not finish"
        }
    }

    var systemImage: String {
        switch self {
        case .toRead: return "book"
        case .reading: return "book.pages"
        case .read: return "checkmark.circle.fill"
        case .onHold: return "pause.circle"
        case .dnf: return "xmark.circle"
        case .wishlist: return "heart"
        }
    }

    var color: Color {
        switch self {
        case .toRead: return .blue
        case .reading: return .orange
        case .read: return .green
        case .onHold: return .yellow
        case .dnf: return .red
        case .wishlist: return .pink
        }
    }
}

// MARK: - Sendable Conformance
extension UserLibraryEntry: @unchecked Sendable {}