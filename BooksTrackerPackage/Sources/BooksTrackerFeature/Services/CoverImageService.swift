import Foundation
import SwiftUI

/// Centralized service for resolving cover image URLs with intelligent fallback logic
///
/// **Purpose:** Single source of truth for cover URL resolution across all display views.
/// Implements fallback chain: Edition → Work → nil
///
/// **Why This Exists:**
/// - 3 of 4 display views were using `.availableEditions.first` instead of `work.primaryEdition`
/// - No views had fallback from `edition.coverImageURL` to `work.coverImageURL`
/// - This caused covers to not display despite data being correct in database
///
/// **Usage:**
/// ```swift
/// // In any view displaying covers
/// CachedAsyncImage(url: CoverImageService.coverURL(for: work)) { image in
///     image.resizable()
/// } placeholder: {
///     Image(systemName: "book.closed")
/// }
/// ```
///
/// - SeeAlso: Issue #325 - Cover images not displaying despite enrichment data in database
/// - SeeAlso: `docs/architecture/2025-11-09-cover-image-display-bug-analysis.md`
@MainActor
public final class CoverImageService {

    /// Get cover URL for display with intelligent fallback logic
    ///
    /// **Fallback Chain:**
    /// 1. Try primary edition cover (uses `EditionSelectionStrategy.AutoStrategy` which prioritizes covers +10 points)
    /// 2. Fall back to Work-level cover (populated by backend enrichment)
    /// 3. Return nil if no cover available
    ///
    /// **Why AutoStrategy Matters:**
    /// `work.primaryEdition` uses `AutoStrategy` which gives +10 points to editions with covers.
    /// This ensures we select the edition most likely to have a cover image.
    ///
    /// - Parameter work: The work to get cover for
    /// - Returns: URL for cover image, or nil if no cover available
    public static func coverURL(for work: Work) -> URL? {
        // 1. Try primary edition (uses AutoStrategy for intelligent selection)
        if let primaryEdition = work.primaryEdition,
           let coverURL = primaryEdition.coverURL {
            return coverURL
        }

        // 2. Fall back to Work-level cover
        // Backend enrichment populates this field when edition doesn't have cover
        if let coverImageURL = work.coverImageURL,
           !coverImageURL.isEmpty {
            return URL(string: coverImageURL)
        }

        // 3. No cover available
        return nil
    }

    /// Get cover URL for specific edition with Work fallback
    ///
    /// **Use Case:** When you have a specific edition to display (e.g., user's owned edition)
    /// but still want fallback to Work-level cover if edition lacks one.
    ///
    /// - Parameters:
    ///   - edition: Specific edition to try first (optional)
    ///   - work: Work to fall back to if edition has no cover
    /// - Returns: URL for cover image, or nil if no cover available
    public static func coverURL(for edition: Edition?, work: Work) -> URL? {
        // Try edition first
        if let edition = edition, let coverURL = edition.coverURL {
            return coverURL
        }

        // Fall back to work
        return coverURL(for: work)
    }
}
