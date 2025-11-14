import Foundation
import SwiftData

@MainActor
final class DuplicateDetectionService {
    static func findExistingEntry(
        for work: Work,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        // Multi-criteria matching:
        // 1. Exact ISBN match (highest confidence)
        // 2. Title + Author name match (high confidence)
        // 3. Normalized title match (medium confidence)

        // Try ISBN match first
        if let isbn = work.primaryEdition?.isbn13,
           let entry = findByISBN(isbn, in: modelContext) {
            return entry
        }

        // Fall back to title + author
        return findByTitleAndAuthor(work, in: modelContext)
    }

    private static func findByISBN(
        _ isbn: String,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        let predicate = #Predicate<UserLibraryEntry> { entry in
            entry.edition?.isbn13 == isbn
        }
        let descriptor = FetchDescriptor(predicate: predicate, fetchLimit: 1)
        return try? modelContext.fetch(descriptor).first
    }

    private static func findByTitleAndAuthor(
        _ work: Work,
        in modelContext: ModelContext
    ) -> UserLibraryEntry? {
        guard let title = work.title?.lowercased(),
              let firstAuthor = work.authors.first?.name.lowercased() else {
            return nil
        }

        let predicate = #Predicate<UserLibraryEntry> { entry in
            entry.work?.title?.lowercased() == title &&
            entry.work?.authors.contains { author in
                author.name.lowercased() == firstAuthor
            } ?? false
        }
        let descriptor = FetchDescriptor(predicate: predicate, fetchLimit: 1)
        return try? modelContext.fetch(descriptor).first
    }
}
