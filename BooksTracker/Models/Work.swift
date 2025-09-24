import Foundation
import SwiftData
import SwiftUI

@Model
final class Work: Identifiable {
    var id: UUID = UUID()
    var title: String
    var primaryAuthor: String
    var originalLanguage: String?
    var firstPublicationYear: Int?
    var subjectTags: [String] = []

    // Cultural diversity tracking
    var culturalRegion: CulturalRegion?
    var authorGender: AuthorGender?

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationships
    @Relationship(deleteRule: .cascade)
    var editions: [Edition] = []

    @Relationship(deleteRule: .cascade)
    var userLibraryEntries: [UserLibraryEntry] = []

    init(
        title: String,
        primaryAuthor: String,
        originalLanguage: String? = nil,
        firstPublicationYear: Int? = nil,
        subjectTags: [String] = [],
        culturalRegion: CulturalRegion? = nil,
        authorGender: AuthorGender? = nil
    ) {
        self.title = title
        self.primaryAuthor = primaryAuthor
        self.originalLanguage = originalLanguage
        self.firstPublicationYear = firstPublicationYear
        self.subjectTags = subjectTags
        self.culturalRegion = culturalRegion
        self.authorGender = authorGender
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Get all editions of this work
    var availableEditions: [Edition] {
        return editions.sorted { $0.publicationDate ?? "" > $1.publicationDate ?? "" }
    }

    /// Get the user's library entry for this work (if any)
    var userEntry: UserLibraryEntry? {
        return userLibraryEntries.first
    }

    /// Check if user has this work in their library
    var isInLibrary: Bool {
        return userEntry != nil
    }

    /// Get the primary edition (usually most recent or preferred)
    var primaryEdition: Edition? {
        // Return user's selected edition first, then most recent
        return userEntry?.edition ?? availableEditions.first
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }
}

// MARK: - Sendable Conformance
extension Work: @unchecked Sendable {}