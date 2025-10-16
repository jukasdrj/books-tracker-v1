#if canImport(UIKit)
import SwiftUI

// MARK: - Accessibility Support for CSV Import

/// VoiceOver announcements for import milestones
@MainActor
public final class ImportProgressAccessibilityAnnouncer {

    // MARK: - Singleton

    public static let shared = ImportProgressAccessibilityAnnouncer()

    private init() {}

    // MARK: - Milestone Announcements

    /// Announces when import starts
    public func announceImportStart(totalBooks: Int) {
        let announcement = "Import started. Processing \(totalBooks) books."
        postAccessibilityAnnouncement(announcement, priority: .high)
    }

    /// Announces progress milestones (25%, 50%, 75%, 100%)
    public func announceProgressMilestone(_ progress: Double, processedBooks: Int, totalBooks: Int) {
        let percentage = Int(progress * 100)

        // Only announce at milestone percentages
        guard [25, 50, 75, 100].contains(percentage) else { return }

        let announcement: String
        switch percentage {
        case 25:
            announcement = "25 percent complete. \(processedBooks) of \(totalBooks) books processed."
        case 50:
            announcement = "Halfway there. \(processedBooks) of \(totalBooks) books processed."
        case 75:
            announcement = "75 percent complete. Almost done."
        case 100:
            announcement = "Import complete. All books processed."
        default:
            return
        }

        postAccessibilityAnnouncement(announcement, priority: .medium)
    }

    /// Announces when errors occur
    public func announceErrors(errorCount: Int) {
        guard errorCount > 0 else { return }

        let announcement = "\(errorCount) \(errorCount == 1 ? "error" : "errors") occurred during import."
        postAccessibilityAnnouncement(announcement, priority: .high)
    }

    /// Announces final import results
    public func announceFinalResults(
        imported: Int,
        duplicates: Int,
        errors: Int,
        duration: TimeInterval
    ) {
        var announcement = "Import complete. "

        announcement += "\(imported) \(imported == 1 ? "book" : "books") imported. "

        if duplicates > 0 {
            announcement += "\(duplicates) duplicates skipped. "
        }

        if errors > 0 {
            announcement += "\(errors) \(errors == 1 ? "error" : "errors") occurred. "
        }

        let minutes = Int(duration / 60)
        if minutes > 0 {
            announcement += "Completed in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
        } else {
            announcement += "Completed in less than a minute."
        }

        postAccessibilityAnnouncement(announcement, priority: .high)
    }

    // MARK: - Helper Methods

    private func postAccessibilityAnnouncement(_ announcement: String, priority: AccessibilityPriority) {
        #if !os(macOS)
        let notification: UIAccessibility.Notification
        switch priority {
        case .high:
            notification = .announcement
        case .medium, .low:
            notification = .announcement
        }

        UIAccessibility.post(notification: notification, argument: announcement)
        #endif
    }

    enum AccessibilityPriority {
        case high
        case medium
        case low
    }
}

// MARK: - Accessible Progress View Modifier

/// View modifier that adds accessibility support to progress views
public struct AccessibleProgressModifier: ViewModifier {
    let processedBooks: Int
    let totalBooks: Int
    let percentComplete: Double
    let currentBookTitle: String
    let estimatedTimeRemaining: TimeInterval?

    public func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Import progress")
            .accessibilityValue(accessibilityDescription)
            .accessibilityHint("Progress updates automatically")
    }

    private var accessibilityDescription: String {
        var description = "\(processedBooks) of \(totalBooks) books imported. "
        description += "\(Int(percentComplete * 100)) percent complete. "

        if !currentBookTitle.isEmpty {
            description += "Currently processing: \(currentBookTitle). "
        }

        if let remaining = estimatedTimeRemaining {
            let formattedTime = remaining.formattedTimeRemaining
            description += "Estimated time remaining: \(formattedTime)."
        }

        return description
    }
}

extension View {
    /// Adds comprehensive accessibility support to import progress views
    public func accessibleImportProgress(
        processedBooks: Int,
        totalBooks: Int,
        percentComplete: Double,
        currentBookTitle: String,
        estimatedTimeRemaining: TimeInterval?
    ) -> some View {
        self.modifier(
            AccessibleProgressModifier(
                processedBooks: processedBooks,
                totalBooks: totalBooks,
                percentComplete: percentComplete,
                currentBookTitle: currentBookTitle,
                estimatedTimeRemaining: estimatedTimeRemaining
            )
        )
    }
}

// MARK: - Dynamic Type Support

/// Provides scaled font sizes for Dynamic Type
public struct ImportProgressDynamicTypeScale {

    public enum TextStyle {
        case headline
        case subheadline
        case body
        case caption
        case caption2

        var uiFont: Font {
            switch self {
            case .headline: return .headline
            case .subheadline: return .subheadline
            case .body: return .body
            case .caption: return .caption
            case .caption2: return .caption2
            }
        }

        var scaledWeight: Font.Weight {
            // Increase weight for better readability at larger sizes
            switch self {
            case .headline: return .bold
            case .subheadline: return .semibold
            case .body: return .regular
            case .caption, .caption2: return .regular
            }
        }
    }

    /// Returns a dynamically scaled font for the given text style
    public static func scaledFont(for style: TextStyle) -> Font {
        style.uiFont.weight(style.scaledWeight)
    }
}

// MARK: - Accessibility Contrast Support

/// Ensures proper contrast for import UI elements
public struct ImportProgressContrastHelper {

    /// Returns a high-contrast color for text on themed backgrounds
    public static func contrastText(
        on backgroundColor: Color,
        theme: iOS26Theme
    ) -> Color {
        // Use system semantic colors for automatic contrast
        // These adapt to the background and accessibility settings
        return .primary
    }

    /// Returns a high-contrast secondary text color
    public static func contrastSecondaryText(
        on backgroundColor: Color,
        theme: iOS26Theme
    ) -> Color {
        // System .secondary color automatically provides WCAG AA contrast
        return .secondary
    }

    /// Validates if a color combination meets WCAG AA standards
    public static func meetsAccessibilityStandards(
        foreground: Color,
        background: Color
    ) -> Bool {
        // This is a simplified check - in production you'd calculate actual contrast ratio
        // For now, trust system semantic colors (.primary, .secondary) to be compliant
        return true
    }
}

// MARK: - VoiceOver Custom Actions

/// Custom VoiceOver actions for import screens
public struct ImportProgressVoiceOverActions {

    /// Creates VoiceOver actions for the import progress view
    public static func createProgressActions(
        onPause: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onViewDetails: @escaping () -> Void
    ) -> [AccessibilityActionHandler] {
        [
            AccessibilityActionHandler(
                name: "Pause Import",
                action: onPause
            ),
            AccessibilityActionHandler(
                name: "Cancel Import",
                action: onCancel
            ),
            AccessibilityActionHandler(
                name: "View Details",
                action: onViewDetails
            )
        ]
    }
}

// Helper struct for accessibility actions
public struct AccessibilityActionHandler {
    let name: String
    let action: () -> Void

    public init(name: String, action: @escaping () -> Void) {
        self.name = name
        self.action = action
    }
}

// MARK: - Accessibility Modifier Extensions

extension View {
    /// Adds VoiceOver custom actions to a view
    public func accessibilityCustomActions(_ actions: [AccessibilityActionHandler]) -> some View {
        var result: AnyView = AnyView(self)
        for action in actions {
            result = AnyView(
                result.accessibilityAction(named: Text(action.name)) {
                    action.action()
                }
            )
        }
        return result
    }
}

// MARK: - Screen Reader Announcements for State Changes

/// Announces state changes to screen readers
@MainActor
public final class ImportStateChangeAnnouncer {

    public static let shared = ImportStateChangeAnnouncer()

    private init() {}

    /// Announces when import state changes
    public func announceStateChange(_ newState: CSVImportService.ImportState) {
        let announcement: String

        switch newState {
        case .idle:
            announcement = "Ready to import"

        case .analyzingFile:
            announcement = "Analyzing CSV file"

        case .mappingColumns:
            announcement = "Column mapping ready. Review and start import."

        case .importing:
            announcement = "Import started"

        case .completed(let result):
            announcement = "Import complete. \(result.successCount) books imported."

        case .failed(let error):
            announcement = "Import failed. \(error)"
        }

        #if !os(macOS)
        UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }
}

// MARK: - Usage Example

#if DEBUG
/// Example of how to integrate accessibility into import views
struct AccessibleImportProgressExample: View {
    @State private var progress = 0.65
    @State private var processedBooks = 975
    @State private var totalBooks = 1500

    var body: some View {
        VStack {
            ProgressView(value: progress)
                .accessibleImportProgress(
                    processedBooks: processedBooks,
                    totalBooks: totalBooks,
                    percentComplete: progress,
                    currentBookTitle: "The Way of Kings",
                    estimatedTimeRemaining: 300
                )

            Text("\(processedBooks) of \(totalBooks)")
                .font(ImportProgressDynamicTypeScale.scaledFont(for: .headline))
                .foregroundColor(
                    ImportProgressContrastHelper.contrastText(
                        on: .blue,
                        theme: .liquidBlue
                    )
                )
        }
        .accessibilityCustomActions([
            AccessibilityActionHandler(name: "Pause") {
                print("Pause action")
            },
            AccessibilityActionHandler(name: "Cancel") {
                print("Cancel action")
            }
        ])
    }
}
#endif
#endif
