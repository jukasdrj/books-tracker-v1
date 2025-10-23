//
//  ImageCleanupService.swift
//  BooksTrackerFeature
//
//  Automatic cleanup of temporary bookshelf scan images after review
//

import Foundation
import SwiftData

/// Service for cleaning up temporary bookshelf scan images
/// when all associated books have been reviewed
@MainActor
public class ImageCleanupService {

    /// Shared singleton instance
    public static let shared = ImageCleanupService()

    private init() {}

    // MARK: - Cleanup

    /// Clean up temporary images where all associated works have been reviewed
    /// Call this on app launch to maintain clean temporary storage
    public func cleanupReviewedImages(in modelContext: ModelContext) async {
        do {
            // Fetch all works that have temporary image references
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group works by their original image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            var cleanedCount = 0
            var errorCount = 0

            // Process each image group
            for (imagePath, works) in groupedByImage {
                // Check if all books from this scan have been reviewed
                let allReviewed = works.allSatisfy { work in
                    work.reviewStatus == .verified || work.reviewStatus == .userEdited
                }

                if allReviewed {
                    // Delete the temporary image file
                    if await deleteImageFile(at: imagePath) {
                        // Clear references from all works
                        for work in works {
                            work.originalImagePath = nil
                            work.boundingBox = nil
                        }
                        cleanedCount += 1
                        print("✅ ImageCleanupService: Deleted \(imagePath) (\(works.count) books reviewed)")
                    } else {
                        errorCount += 1
                        print("⚠️ ImageCleanupService: Failed to delete \(imagePath)")
                    }
                }
            }

            // Save changes if any cleanup occurred
            if cleanedCount > 0 {
                try modelContext.save()
                print("🧹 ImageCleanupService: Cleaned up \(cleanedCount) image(s), \(errorCount) error(s)")
            } else {
                print("🧹 ImageCleanupService: No images ready for cleanup")
            }

        } catch {
            print("❌ ImageCleanupService: Failed to cleanup images - \(error)")
        }
    }

    // MARK: - File Operations

    /// Delete image file at specified path
    /// Returns true if successful or file doesn't exist
    private func deleteImageFile(at path: String) async -> Bool {
        let fileManager = FileManager.default

        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            // File already deleted - consider this success
            return true
        }

        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            print("❌ ImageCleanupService: File deletion error - \(error)")
            return false
        }
    }

    // MARK: - Statistics

    /// Get count of temporary images awaiting cleanup
    public func getPendingCleanupCount(in modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group by image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            // Count images where all books are reviewed
            return groupedByImage.filter { _, works in
                works.allSatisfy { $0.reviewStatus == .verified || $0.reviewStatus == .userEdited }
            }.count

        } catch {
            print("❌ ImageCleanupService: Failed to get pending count - \(error)")
            return 0
        }
    }

    /// Get count of temporary images still in use (books under review)
    public func getActiveImageCount(in modelContext: ModelContext) -> Int {
        do {
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)

            // Group by image path
            let worksWithImages = allWorks.filter { $0.originalImagePath != nil }
            let groupedByImage = Dictionary(grouping: worksWithImages) { $0.originalImagePath! }

            // Count images with at least one book needing review
            return groupedByImage.filter { _, works in
                works.contains { $0.reviewStatus == .needsReview }
            }.count

        } catch {
            print("❌ ImageCleanupService: Failed to get active count - \(error)")
            return 0
        }
    }
}
