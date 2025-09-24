import Foundation
import SwiftData
import SwiftUI

@Model
public final class Work: Identifiable {
    public var id: UUID = UUID()
    var title: String
    var originalLanguage: String?
    var firstPublicationYear: Int?
    var subjectTags: [String] = []

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationships - PROPER NORMALIZATION
    @Relationship(deleteRule: .nullify, inverse: \Author.works)
    var authors: [Author] = []

    @Relationship(deleteRule: .cascade)
    var editions: [Edition] = []

    @Relationship(deleteRule: .cascade)
    var userLibraryEntries: [UserLibraryEntry] = []

    public init(
        title: String,
        authors: [Author] = [],
        originalLanguage: String? = nil,
        firstPublicationYear: Int? = nil,
        subjectTags: [String] = []
    ) {
        self.title = title
        self.authors = authors
        self.originalLanguage = originalLanguage
        self.firstPublicationYear = firstPublicationYear
        self.subjectTags = subjectTags
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Get primary author (first in list)
    var primaryAuthor: Author? {
        return authors.first
    }

    /// Get primary author name for display
    var primaryAuthorName: String {
        return primaryAuthor?.name ?? "Unknown Author"
    }

    /// Get all author names formatted for display
    var authorNames: String {
        let names = authors.map { $0.name }
        switch names.count {
        case 0: return "Unknown Author"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }

    /// Get cultural data from primary author
    var culturalRegion: CulturalRegion? {
        return primaryAuthor?.culturalRegion
    }

    var authorGender: AuthorGender? {
        return primaryAuthor?.gender
    }

    /// Get all editions of this work
    var availableEditions: [Edition] {
        return editions.sorted { $0.publicationDate ?? "" > $1.publicationDate ?? "" }
    }

    /// Get the user's library entry for this work (if any)
    var userEntry: UserLibraryEntry? {
        return userLibraryEntries.first
    }

    /// Check if user has this work in their library (owned or wishlist)
    var isInLibrary: Bool {
        return userEntry != nil
    }

    /// Check if user owns this work (has specific edition)
    var isOwned: Bool {
        guard let entry = userEntry else { return false }
        return entry.readingStatus != .wishlist && entry.edition != nil
    }

    /// Check if user has this work on wishlist
    var isOnWishlist: Bool {
        return userEntry?.readingStatus == .wishlist
    }

    /// Get the primary edition (usually most recent or preferred)
    var primaryEdition: Edition? {
        // Return user's selected edition first, then most recent
        return userEntry?.edition ?? availableEditions.first
    }

    /// Add an author to this work
    func addAuthor(_ author: Author) {
        if !authors.contains(author) {
            authors.append(author)
            author.updateStatistics()
            touch()
        }
    }

    /// Remove an author from this work
    func removeAuthor(_ author: Author) {
        if let index = authors.firstIndex(of: author) {
            authors.remove(at: index)
            author.updateStatistics()
            touch()
        }
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }
}

