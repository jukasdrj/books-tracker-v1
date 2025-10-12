import Foundation
import ActivityKit
import SwiftUI

// MARK: - CSV Import Live Activity Attributes

/// ActivityKit attributes for CSV import progress tracking
/// Displays on Lock Screen and Dynamic Island during long imports
@available(iOS 16.2, *)
public struct CSVImportActivityAttributes: ActivityAttributes, Sendable {

    // MARK: - Static Content

    /// Content that remains constant throughout the activity lifecycle
    public struct ContentState: Codable, Hashable, Sendable {
        /// Total number of books to import
        public var totalBooks: Int

        /// Number of books processed so far (import phase)
        public var processedBooks: Int

        /// Number of successfully imported books
        public var successfulImports: Int

        /// Number of skipped duplicates
        public var skippedDuplicates: Int

        /// Number of failed imports
        public var failedImports: Int

        /// Title of the currently processing book
        public var currentBookTitle: String

        /// Current status message
        public var statusMessage: String

        /// Estimated time remaining in seconds
        public var estimatedTimeRemaining: TimeInterval?

        /// Start time of the import
        public var startTime: Date

        /// Whether we're in the enrichment phase (vs import phase)
        public var isEnrichmentPhase: Bool

        /// Number of books enriched so far (enrichment phase)
        public var enrichedBooks: Int

        /// Progress percentage (0.0 to 1.0)
        public var progress: Double {
            guard totalBooks > 0 else { return 0 }
            if isEnrichmentPhase {
                return Double(enrichedBooks) / Double(totalBooks)
            } else {
                return Double(processedBooks) / Double(totalBooks)
            }
        }

        /// Books per minute rate
        public var processingRate: Double {
            let elapsed = Date().timeIntervalSince(startTime)
            let count = isEnrichmentPhase ? enrichedBooks : processedBooks
            guard elapsed > 0, count > 0 else { return 0 }
            return Double(count) / (elapsed / 60.0)
        }

        public init(
            totalBooks: Int,
            processedBooks: Int = 0,
            successfulImports: Int = 0,
            skippedDuplicates: Int = 0,
            failedImports: Int = 0,
            currentBookTitle: String = "",
            statusMessage: String = "Preparing import...",
            estimatedTimeRemaining: TimeInterval? = nil,
            startTime: Date = Date(),
            isEnrichmentPhase: Bool = false,
            enrichedBooks: Int = 0
        ) {
            self.totalBooks = totalBooks
            self.processedBooks = processedBooks
            self.successfulImports = successfulImports
            self.skippedDuplicates = skippedDuplicates
            self.failedImports = failedImports
            self.currentBookTitle = currentBookTitle
            self.statusMessage = statusMessage
            self.estimatedTimeRemaining = estimatedTimeRemaining
            self.startTime = startTime
            self.isEnrichmentPhase = isEnrichmentPhase
            self.enrichedBooks = enrichedBooks
        }
    }

    // MARK: - Fixed Attributes

    /// Import session ID (unique per import)
    public var importSessionID: UUID

    /// Name of the CSV file being imported
    public var fileName: String

    /// File size in bytes (for display purposes)
    public var fileSizeBytes: Int?

    /// Theme primary color (hex string for Live Activity serialization)
    public var themePrimaryColorHex: String

    /// Theme secondary color (hex string for Live Activity serialization)
    public var themeSecondaryColorHex: String

    public init(
        importSessionID: UUID = UUID(),
        fileName: String,
        fileSizeBytes: Int? = nil,
        themePrimaryColorHex: String = "#007AFF",
        themeSecondaryColorHex: String = "#4DB0FF"
    ) {
        self.importSessionID = importSessionID
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.themePrimaryColorHex = themePrimaryColorHex
        self.themeSecondaryColorHex = themeSecondaryColorHex
    }

    // MARK: - Theme Color Helpers

    /// Convert Color to hex string for serialization
    public static func colorToHex(_ color: Color) -> String {
        guard let components = color.cgColor?.components else {
            return "#007AFF" // Fallback to system blue
        }

        let r = Int((components[0]) * 255.0)
        let g = Int((components[1]) * 255.0)
        let b = Int((components[2]) * 255.0)

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Convert hex string to Color for display
    public func hexToColor(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    /// Get theme primary color as SwiftUI Color
    public var themePrimaryColor: Color {
        hexToColor(themePrimaryColorHex)
    }

    /// Get theme secondary color as SwiftUI Color
    public var themeSecondaryColor: Color {
        hexToColor(themeSecondaryColorHex)
    }
}

// MARK: - Activity Manager

/// Manages Live Activity lifecycle for CSV imports
@available(iOS 16.2, *)
public final class CSVImportActivityManager: @unchecked Sendable {

    // MARK: - Properties

    private var currentActivity: Activity<CSVImportActivityAttributes>?
    private let updateThrottle: TimeInterval = 1.0 // Update every 1 second minimum
    private var lastUpdateTime: Date?

    // MARK: - Singleton

    public static let shared = CSVImportActivityManager()

    private init() {}

    // MARK: - Activity Lifecycle

    /// Starts a new Live Activity for the import session
    public func startActivity(
        fileName: String,
        totalBooks: Int,
        fileSizeBytes: Int? = nil,
        themePrimaryColorHex: String = "#007AFF",
        themeSecondaryColorHex: String = "#4DB0FF"
    ) async throws {
        // End any existing activity first
        await endActivity()

        let attributes = CSVImportActivityAttributes(
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            themePrimaryColorHex: themePrimaryColorHex,
            themeSecondaryColorHex: themeSecondaryColorHex
        )

        let contentState = CSVImportActivityAttributes.ContentState(
            totalBooks: totalBooks,
            statusMessage: "Starting import..."
        )

        do {
            let activity = try Activity<CSVImportActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )

            self.currentActivity = activity
            print("📱 Live Activity started for import: \(fileName)")
        } catch {
            print("⚠️ Failed to start Live Activity: \(error.localizedDescription)")
            throw error
        }
    }

    /// Updates the current Live Activity with new progress
    public func updateActivity(
        processedBooks: Int,
        successfulImports: Int,
        skippedDuplicates: Int,
        failedImports: Int,
        currentBookTitle: String,
        estimatedTimeRemaining: TimeInterval?
    ) async {
        // Throttle updates to avoid excessive UI refreshes
        if let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < updateThrottle {
            return
        }

        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }

        let contentState = CSVImportActivityAttributes.ContentState(
            totalBooks: activity.content.state.totalBooks,
            processedBooks: processedBooks,
            successfulImports: successfulImports,
            skippedDuplicates: skippedDuplicates,
            failedImports: failedImports,
            currentBookTitle: currentBookTitle,
            statusMessage: generateStatusMessage(
                processed: processedBooks,
                total: activity.content.state.totalBooks
            ),
            estimatedTimeRemaining: estimatedTimeRemaining,
            startTime: activity.content.state.startTime
        )

        await activity.update(.init(state: contentState, staleDate: nil))
        lastUpdateTime = Date()
    }

    /// Transitions Live Activity from import phase to enrichment phase
    public func startEnrichmentPhase(totalBooksToEnrich: Int) async {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to transition to enrichment")
            return
        }

        var enrichmentState = activity.content.state
        enrichmentState.isEnrichmentPhase = true
        enrichmentState.enrichedBooks = 0
        enrichmentState.totalBooks = totalBooksToEnrich
        enrichmentState.statusMessage = "Enriching metadata..."
        enrichmentState.currentBookTitle = ""
        enrichmentState.estimatedTimeRemaining = nil

        await activity.update(.init(state: enrichmentState, staleDate: nil))
        print("📱 Live Activity transitioned to enrichment phase (\(totalBooksToEnrich) books)")
    }

    /// Updates enrichment progress (called from EnrichmentQueue)
    public func updateEnrichmentProgress(
        enrichedBooks: Int,
        totalBooks: Int,
        currentBookTitle: String
    ) async {
        // Throttle updates
        if let lastUpdate = lastUpdateTime,
           Date().timeIntervalSince(lastUpdate) < updateThrottle {
            return
        }

        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }

        var enrichmentState = activity.content.state
        enrichmentState.enrichedBooks = enrichedBooks
        enrichmentState.currentBookTitle = currentBookTitle
        enrichmentState.statusMessage = generateEnrichmentStatusMessage(
            enriched: enrichedBooks,
            total: totalBooks
        )

        await activity.update(.init(state: enrichmentState, staleDate: nil))
        lastUpdateTime = Date()
    }

    /// Ends the Live Activity with final results
    public func endActivity(
        finalMessage: String = "Import complete",
        dismissAfter: TimeInterval = 4.0
    ) async {
        guard let activity = currentActivity else { return }

        var finalState = activity.content.state
        finalState.statusMessage = finalMessage

        await activity.end(
            .init(state: finalState, staleDate: Date().addingTimeInterval(dismissAfter)),
            dismissalPolicy: .after(.now + dismissAfter)
        )

        currentActivity = nil
        lastUpdateTime = nil
        print("📱 Live Activity ended: \(finalMessage)")
    }

    // MARK: - Helper Methods

    private func generateStatusMessage(processed: Int, total: Int) -> String {
        let remaining = total - processed

        if remaining == 0 {
            return "Finalizing import..."
        } else if remaining < 10 {
            return "Almost done..."
        } else if Double(processed) / Double(total) > 0.75 {
            return "Nearly there..."
        } else {
            return "Importing books..."
        }
    }

    private func generateEnrichmentStatusMessage(enriched: Int, total: Int) -> String {
        let remaining = total - enriched

        if remaining == 0 {
            return "Enrichment complete!"
        } else if remaining < 10 {
            return "Finishing enrichment..."
        } else if Double(enriched) / Double(total) > 0.75 {
            return "Nearly enriched..."
        } else {
            return "Enriching metadata..."
        }
    }
}

// MARK: - Time Formatting

extension TimeInterval {
    /// Formats time remaining for display
    var formattedTimeRemaining: String {
        if self < 60 {
            return "< 1 min"
        } else if self < 3600 {
            let minutes = Int(self / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(self / 3600)
            let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        }
    }
}
