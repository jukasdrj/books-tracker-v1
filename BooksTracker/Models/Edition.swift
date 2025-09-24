import Foundation
import SwiftData
import SwiftUI

@Model
final class Edition: Identifiable {
    var id: UUID = UUID()
    var isbn: String?
    var publisher: String?
    var publicationDate: String?
    var pageCount: Int?
    var format: BookFormat = .physical
    var coverImageURL: String?
    var editionTitle: String? // "Deluxe Edition", "Abridged", etc.

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationship back to Work
    @Relationship
    var work: Work?

    init(
        isbn: String? = nil,
        publisher: String? = nil,
        publicationDate: String? = nil,
        pageCount: Int? = nil,
        format: BookFormat = .physical,
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

// MARK: - Book Format Enum
enum BookFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case physical = "Physical"
    case ebook = "E-book"
    case audiobook = "Audiobook"

    var id: Self { self }

    var icon: String {
        switch self {
        case .physical: return "book.closed"
        case .ebook: return "ipad"
        case .audiobook: return "headphones"
        }
    }

    var displayName: String {
        return rawValue
    }
}

// MARK: - Sendable Conformance
extension Edition: @unchecked Sendable {}