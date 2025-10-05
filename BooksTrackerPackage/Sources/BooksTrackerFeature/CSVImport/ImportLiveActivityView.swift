import SwiftUI
import ActivityKit
import WidgetKit

// MARK: - CSV Import Live Activity Widget

/// Live Activity widget for CSV import progress
/// Displays on Lock Screen and Dynamic Island
@available(iOS 16.2, *)
public struct CSVImportLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CSVImportActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }

                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact leading (left side of Dynamic Island)
                CompactLeadingView(context: context)
            } compactTrailing: {
                // Compact trailing (right side of Dynamic Island)
                CompactTrailingView(context: context)
            } minimal: {
                // Minimal state (when multiple activities are active)
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.2, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [context.attributes.themePrimaryColor, context.attributes.themeSecondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Importing Books")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(context.attributes.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Processing rate badge
                if context.state.processingRate > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                        Text("\(Int(context.state.processingRate))/min")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(context.attributes.themePrimaryColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                            .frame(height: 12)

                        // Progress fill with gradient
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [context.attributes.themePrimaryColor, context.attributes.themeSecondaryColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * context.state.progress,
                                height: 12
                            )
                            .animation(.smooth(duration: 0.5), value: context.state.progress)
                    }
                }
                .frame(height: 12)

                // Progress text
                HStack {
                    Text("\(context.state.processedBooks) of \(context.state.totalBooks)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)

                    Spacer()

                    if let remaining = context.state.estimatedTimeRemaining {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(remaining.formattedTimeRemaining)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Current book
            if !context.state.currentBookTitle.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(context.attributes.themePrimaryColor)

                    Text(context.state.currentBookTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(context.attributes.themePrimaryColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Statistics
            HStack(spacing: 16) {
                StatBadge(
                    icon: "checkmark.circle.fill",
                    value: "\(context.state.successfulImports)",
                    label: "Imported",
                    color: .green
                )

                if context.state.skippedDuplicates > 0 {
                    StatBadge(
                        icon: "doc.on.doc.fill",
                        value: "\(context.state.skippedDuplicates)",
                        label: "Skipped",
                        color: .orange
                    )
                }

                if context.state.failedImports > 0 {
                    StatBadge(
                        icon: "xmark.circle.fill",
                        value: "\(context.state.failedImports)",
                        label: "Failed",
                        color: .red
                    )
                }

                Spacer()
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Import progress")
        .accessibilityValue("\(context.state.processedBooks) of \(context.state.totalBooks) books imported. \(Int(context.state.progress * 100)) percent complete.")
    }
}

// MARK: - Dynamic Island Expanded Views

@available(iOS 16.2, *)
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "books.vertical.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [context.attributes.themePrimaryColor, context.attributes.themeSecondaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse)

            Text("\(context.state.processedBooks)")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("imported")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}

@available(iOS 16.2, *)
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            CircularProgressView(
                progress: context.state.progress,
                primaryColor: context.attributes.themePrimaryColor,
                secondaryColor: context.attributes.themeSecondaryColor
            )
            .frame(width: 48, height: 48)

            if let remaining = context.state.estimatedTimeRemaining {
                Text(remaining.formattedTimeRemaining)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 8)
    }
}

@available(iOS 16.2, *)
struct ExpandedCenterView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        VStack(spacing: 4) {
            Text(context.state.statusMessage)
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text("\(context.state.totalBooks) books")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

@available(iOS 16.2, *)
struct ExpandedBottomView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            // Current book
            if !context.state.currentBookTitle.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption2)
                        .foregroundStyle(context.attributes.themePrimaryColor)

                    Text(context.state.currentBookTitle)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [context.attributes.themePrimaryColor, context.attributes.themeSecondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * context.state.progress,
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            // Statistics
            HStack(spacing: 12) {
                MiniStatBadge(
                    icon: "checkmark.circle.fill",
                    value: "\(context.state.successfulImports)",
                    color: .green
                )

                if context.state.skippedDuplicates > 0 {
                    MiniStatBadge(
                        icon: "doc.on.doc.fill",
                        value: "\(context.state.skippedDuplicates)",
                        color: .orange
                    )
                }

                if context.state.failedImports > 0 {
                    MiniStatBadge(
                        icon: "xmark.circle.fill",
                        value: "\(context.state.failedImports)",
                        color: .red
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Dynamic Island Compact Views

@available(iOS 16.2, *)
struct CompactLeadingView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        Image(systemName: "books.vertical.fill")
            .foregroundStyle(context.attributes.themePrimaryColor)
            .symbolEffect(.pulse)
    }
}

@available(iOS 16.2, *)
struct CompactTrailingView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        HStack(spacing: 4) {
            Text("\(Int(context.state.progress * 100))%")
                .font(.caption2.bold())
                .foregroundStyle(.primary)

            CircularProgressView(
                progress: context.state.progress,
                primaryColor: context.attributes.themePrimaryColor,
                secondaryColor: context.attributes.themeSecondaryColor
            )
            .frame(width: 20, height: 20)
        }
    }
}

// MARK: - Dynamic Island Minimal View

@available(iOS 16.2, *)
struct MinimalView: View {
    let context: ActivityViewContext<CSVImportActivityAttributes>

    var body: some View {
        CircularProgressView(
            progress: context.state.progress,
            primaryColor: context.attributes.themePrimaryColor,
            secondaryColor: context.attributes.themeSecondaryColor
        )
        .frame(width: 24, height: 24)
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MiniStatBadge: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)

            Text(value)
                .font(.caption2.bold())
                .foregroundStyle(.primary)
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    var primaryColor: Color = .blue
    var secondaryColor: Color = .cyan

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(.quaternary, lineWidth: 4)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [primaryColor, secondaryColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.5), value: progress)
        }
    }
}

// MARK: - Accessibility Support

@available(iOS 16.2, *)
extension CSVImportActivityAttributes.ContentState {
    var accessibilityDescription: String {
        var description = "\(processedBooks) of \(totalBooks) books imported. "
        description += "\(Int(progress * 100)) percent complete. "

        if successfulImports > 0 {
            description += "\(successfulImports) successful. "
        }

        if skippedDuplicates > 0 {
            description += "\(skippedDuplicates) duplicates skipped. "
        }

        if failedImports > 0 {
            description += "\(failedImports) failed. "
        }

        if let remaining = estimatedTimeRemaining {
            description += "Estimated time remaining: \(remaining.formattedTimeRemaining). "
        }

        if !currentBookTitle.isEmpty {
            description += "Currently importing: \(currentBookTitle)."
        }

        return description
    }
}
