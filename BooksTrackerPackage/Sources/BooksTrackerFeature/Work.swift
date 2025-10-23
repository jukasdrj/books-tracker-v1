import Foundation
import SwiftData
import SwiftUI

@Model
public final class Work {
    var title: String = "" // CloudKit: default value required
    var originalLanguage: String?
    var firstPublicationYear: Int?
    var subjectTags: [String] = []

    // External API identifiers for syncing and deduplication
    var openLibraryID: String?      // e.g., "OL123456W" (legacy, prefer openLibraryWorkID)
    var openLibraryWorkID: String?  // OpenLibrary Work ID
    var isbndbID: String?          // ISBNDB work/book identifier
    var googleBooksVolumeID: String? // e.g., "beSP5CCpiGUC"
    var goodreadsID: String?       // Goodreads work ID (legacy, prefer goodreadsWorkIDs)

    // Enhanced cross-reference identifiers (arrays for multiple IDs)
    var goodreadsWorkIDs: [String] = []      // Multiple Goodreads work IDs
    var amazonASINs: [String] = []           // Amazon ASINs from various providers
    var librarythingIDs: [String] = []       // LibraryThing identifiers
    var googleBooksVolumeIDs: [String] = []  // Google Books volume IDs

    // Cache optimization for ISBNDB integration
    var lastISBNDBSync: Date?       // When this work was last synced with ISBNDB
    var isbndbQuality: Int = 0      // Data quality score from ISBNDB (0-100)

    // Review status for AI-detected books
    public var reviewStatus: ReviewStatus = ReviewStatus.verified

    /// Path to original bookshelf scan image (temporary storage)
    /// Will be deleted after all books from scan are reviewed
    public var originalImagePath: String?

    /// Bounding box coordinates for cropping spine from original image
    /// Stored as separate components to avoid CGRect encoding issues in SwiftData
    public var boundingBoxX: Double?
    public var boundingBoxY: Double?
    public var boundingBoxWidth: Double?
    public var boundingBoxHeight: Double?

    /// Computed property to access bounding box as CGRect
    public var boundingBox: CGRect? {
        get {
            guard let x = boundingBoxX,
                  let y = boundingBoxY,
                  let width = boundingBoxWidth,
                  let height = boundingBoxHeight else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }
        set {
            if let rect = newValue {
                boundingBoxX = rect.origin.x
                boundingBoxY = rect.origin.y
                boundingBoxWidth = rect.size.width
                boundingBoxHeight = rect.size.height
            } else {
                boundingBoxX = nil
                boundingBoxY = nil
                boundingBoxWidth = nil
                boundingBoxHeight = nil
            }
        }
    }

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationships - CloudKit requires optional relationships
    @Relationship(deleteRule: .nullify, inverse: \Author.works)
    var authors: [Author]?

    @Relationship(deleteRule: .cascade, inverse: \Edition.work)
    var editions: [Edition]?

    @Relationship(deleteRule: .cascade, inverse: \UserLibraryEntry.work)
    var userLibraryEntries: [UserLibraryEntry]?

    public init(
        title: String,
        authors: [Author] = [],
        originalLanguage: String? = nil,
        firstPublicationYear: Int? = nil,
        subjectTags: [String] = []
    ) {
        self.title = title
        self.authors = authors.isEmpty ? nil : authors
        self.originalLanguage = originalLanguage
        self.firstPublicationYear = firstPublicationYear
        self.subjectTags = subjectTags
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Get primary author (first in list)
    var primaryAuthor: Author? {
        return authors?.first
    }

    /// Get primary author name for display
    var primaryAuthorName: String {
        return primaryAuthor?.name ?? "Unknown Author"
    }

    /// Get all author names formatted for display
    var authorNames: String {
        guard let authors = authors else { return "Unknown Author" }
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
        return editions?.sorted { $0.publicationDate ?? "" > $1.publicationDate ?? "" } ?? []
    }

    /// Get the user's library entry for this work (if any)
    var userEntry: UserLibraryEntry? {
        return userLibraryEntries?.first
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
        if authors == nil {
            authors = []
        }
        if !(authors?.contains(author) ?? false) {
            authors?.append(author)
            author.updateStatistics()
            touch()
        }
    }

    /// Remove an author from this work
    func removeAuthor(_ author: Author) {
        if let index = authors?.firstIndex(of: author) {
            authors?.remove(at: index)
            author.updateStatistics()
            touch()
        }
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }

    // MARK: - External ID Management

    /// Add a Goodreads Work ID if not already present
    func addGoodreadsWorkID(_ id: String) {
        guard !id.isEmpty && !goodreadsWorkIDs.contains(id) else { return }
        goodreadsWorkIDs.append(id)
        touch()
    }

    /// Add an Amazon ASIN if not already present
    func addAmazonASIN(_ asin: String) {
        guard !asin.isEmpty && !amazonASINs.contains(asin) else { return }
        amazonASINs.append(asin)
        touch()
    }

    /// Add a LibraryThing ID if not already present
    func addLibraryThingID(_ id: String) {
        guard !id.isEmpty && !librarythingIDs.contains(id) else { return }
        librarythingIDs.append(id)
        touch()
    }

    /// Add a Google Books Volume ID if not already present
    func addGoogleBooksVolumeID(_ id: String) {
        guard !id.isEmpty && !googleBooksVolumeIDs.contains(id) else { return }
        googleBooksVolumeIDs.append(id)
        touch()
    }

    /// Merge external IDs from API response
    func mergeExternalIDs(from crossReferenceIds: [String: Any]) {
        if let goodreadsIDs = crossReferenceIds["goodreadsWorkIds"] as? [String] {
            goodreadsIDs.forEach { addGoodreadsWorkID($0) }
        }

        if let asins = crossReferenceIds["amazonASINs"] as? [String] {
            asins.forEach { addAmazonASIN($0) }
        }

        if let ltIDs = crossReferenceIds["librarythingIds"] as? [String] {
            ltIDs.forEach { addLibraryThingID($0) }
        }

        if let gbIDs = crossReferenceIds["googleBooksVolumeIds"] as? [String] {
            gbIDs.forEach { addGoogleBooksVolumeID($0) }
        }

        // Handle OpenLibrary Work ID
        if let olWorkId = crossReferenceIds["openLibraryWorkId"] as? String, !olWorkId.isEmpty {
            self.openLibraryWorkID = olWorkId
            touch()
        }
    }

    /// Get all external IDs as a dictionary for API integration
    var externalIDsDictionary: [String: Any] {
        return [
            "openLibraryWorkId": openLibraryWorkID ?? "",
            "goodreadsWorkIds": goodreadsWorkIDs,
            "amazonASINs": amazonASINs,
            "librarythingIds": librarythingIDs,
            "googleBooksVolumeIds": googleBooksVolumeIDs,
            "isbndbId": isbndbID ?? ""
        ]
    }
}

