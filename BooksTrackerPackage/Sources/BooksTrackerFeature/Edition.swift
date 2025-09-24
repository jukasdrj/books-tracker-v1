import Foundation
import SwiftData
import SwiftUI

@Model
public final class Edition: Identifiable {
    public var id: UUID = UUID()
    var isbn: String?
    var publisher: String?
    var publicationDate: String?
    var pageCount: Int?
    var format: EditionFormat = EditionFormat.hardcover
    var coverImageURL: String?
    var editionTitle: String? // "Deluxe Edition", "Abridged", etc.

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationship back to Work
    @Relationship
    var work: Work?

    public init(
        isbn: String? = nil,
        publisher: String? = nil,
        publicationDate: String? = nil,
        pageCount: Int? = nil,
        format: EditionFormat = EditionFormat.hardcover,
        coverImageURL: String? = nil,
        editionTitle: String? = nil,
        work: Work? = nil
    ) {
        self.isbn = isbn
        self.publisher = publisher
        self.publicationDate = publicationDate
        self.pageCount = pageCount
        self.format = format
        self.coverImageURL = coverImageURL
        self.editionTitle = editionTitle
        self.work = work
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Display name for this edition
    var displayTitle: String {
        if let editionTitle = editionTitle, !editionTitle.isEmpty {
            return "\(work?.title ?? "Unknown") (\(editionTitle))"
        }
        return work?.title ?? "Unknown"
    }

    /// Display string for publisher info
    var publisherInfo: String {
        var info: [String] = []

        if let publisher = publisher, !publisher.isEmpty {
            info.append(publisher)
        }

        if let year = publicationDate?.prefix(4) {
            info.append(String(year))
        }

        return info.joined(separator: ", ")
    }

    /// Formatted page count string
    var pageCountString: String? {
        guard let pageCount = pageCount, pageCount > 0 else { return nil }
        return "\(pageCount) pages"
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }
}

// EditionFormat is now defined in ModelTypes.swift

