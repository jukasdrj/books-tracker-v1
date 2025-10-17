import SwiftUI

// MARK: - Background Import Banner

/// Banner displayed when CSV import continues in background
/// Shows minimal progress and allows user to return to import view
@MainActor
public struct BackgroundImportBanner: View {

    // MARK: - Properties

    @Binding var isShowing: Bool
    let processedBooks: Int
    let totalBooks: Int
    let currentBookTitle: String
    let onTap: () -> Void

    @State private var isExpanded = false
    @Environment(\.iOS26ThemeStore) private var themeStore

    // MARK: - Computed Properties

    private var progress: Double {
        guard totalBooks > 0 else { return 0 }
        return Double(processedBooks) / Double(totalBooks)
    }

    private var percentComplete: Int {
        Int(progress * 100)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Main banner
            HStack(spacing: 12) {
                // Icon with pulse animation
                ZStack {
                    Circle()
                        .fill(themeStore.primaryColor.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(themeStore.primaryColor)
                        .symbolEffect(.pulse)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Importing Books")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(percentComplete)%")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.quaternary)
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeStore.primaryColor)
                                .frame(
                                    width: geometry.size.width * min(1.0, max(0.0, progress)),
                                    height: 4
                                )
                                .animation(.smooth(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)

                    Text("\(processedBooks) of \(totalBooks) books")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Expand/collapse button
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 0 : 12)
                    .fill(.ultraThinMaterial)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Expanded details
            if isExpanded {
                ExpandedDetails(
                    currentBookTitle: currentBookTitle,
                    onViewDetails: onTap,
                    themeStore: themeStore
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(y: isShowing ? 0 : -120)
        .animation(.smooth(duration: 0.4), value: isShowing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Import in progress")
        .accessibilityValue("\(processedBooks) of \(totalBooks) books imported. \(percentComplete) percent complete.")
        .accessibilityHint("Tap to view import details")
    }
}

// MARK: - Expanded Details

struct ExpandedDetails: View {
    let currentBookTitle: String
    let onViewDetails: () -> Void
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 16)

            // Current book
            if !currentBookTitle.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(themeStore.primaryColor)

                    Text(currentBookTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // Action button
            Button {
                onViewDetails()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle")
                    Text("View Import Progress")
                }
                .font(.subheadline.bold())
                .foregroundStyle(themeStore.primaryColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeStore.primaryColor.opacity(0.15))
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Floating Action Button (Return to Import)

/// Floating action button that appears when user navigates away during import
public struct ReturnToImportButton: View {

    @Binding var isShowing: Bool
    let onTap: () -> Void
    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 16))
                    .symbolEffect(.pulse)

                Text("Import in Progress")
                    .font(.subheadline.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(themeStore.primaryColor)
            )
            .shadow(color: themeStore.primaryColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .offset(y: isShowing ? 0 : 100)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: isShowing)
        .accessibilityLabel("Return to import")
        .accessibilityHint("Tap to view import progress")
    }
}

// MARK: - Import Notification Banner

/// Success/failure notification banner after import completes
public struct ImportCompletionNotification: View {

    // MARK: - State

    public enum NotificationType {
        case success(imported: Int, duplicates: Int, errors: Int)
        case failure(message: String)

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            }
        }

        var title: String {
            switch self {
            case .success: return "Import Complete"
            case .failure: return "Import Failed"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .failure: return .red
            }
        }
    }

    // MARK: - Properties

    @Binding var isShowing: Bool
    let notificationType: NotificationType
    let onDismiss: () -> Void
    let onViewDetails: (() -> Void)?

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var autoHideTask: Task<Void, Never>?

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: notificationType.icon)
                    .font(.title2)
                    .foregroundStyle(notificationType.color.gradient)
                    .symbolEffect(.bounce, value: isShowing)

                VStack(alignment: .leading, spacing: 4) {
                    Text(notificationType.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    switch notificationType {
                    case .success(let imported, let duplicates, let errors):
                        HStack(spacing: 12) {
                            Label("\(imported)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)

                            if duplicates > 0 {
                                Label("\(duplicates)", systemImage: "doc.on.doc.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if errors > 0 {
                                Label("\(errors)", systemImage: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                    case .failure(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Dismiss button
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowing = false
                    }
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Circle().fill(.quaternary))
                }
            }

            // View details button (optional)
            if let onViewDetails = onViewDetails {
                Button {
                    onViewDetails()
                } label: {
                    HStack {
                        Text("View Details")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(themeStore.primaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeStore.primaryColor.opacity(0.15))
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .offset(y: isShowing ? 0 : -200)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: isShowing)
        .onAppear {
            // Auto-hide after 5 seconds
            autoHideTask = Task {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowing = false
                    }
                    onDismiss()
                }
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notificationType.title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Enrichment Progress Banner (Moved from ContentView with Contrast Fix)

/// Banner displayed during background enrichment operations
/// Shows live progress with proper material background for legibility
public struct EnrichmentBanner: View {
    let completed: Int
    let total: Int
    let currentBookTitle: String
    let themeStore: iOS26ThemeStore

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress bar (Top bar)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 4)

                    // Progress fill with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [themeStore.primaryColor, themeStore.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * min(1.0, max(0.0, progress)),
                            height: 4
                        )
                        .animation(.smooth(duration: 0.5), value: progress)
                }
            }
            .frame(height: 4)

            // Content
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeStore.primaryColor, themeStore.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enriching Metadata")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !currentBookTitle.isEmpty {
                        Text(currentBookTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary) // Ensures good contrast
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Progress text
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completed)/\(total)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary) // Ensures good contrast
                }
            }
            .padding(16)
            .background {
                 // FIX: Use a more prominent material for legibility
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8) // Padding from the bottom safe area
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Preview Helpers

#if DEBUG
@available(iOS 16.2, *)
struct BackgroundImportBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            BackgroundImportBanner(
                isShowing: .constant(true),
                processedBooks: 750,
                totalBooks: 1500,
                currentBookTitle: "The Way of Kings by Brandon Sanderson"
            ) {
                print("Tapped")
            }

            ReturnToImportButton(isShowing: .constant(true)) {
                print("Return tapped")
            }

            ImportCompletionNotification(
                isShowing: .constant(true),
                notificationType: .success(imported: 1450, duplicates: 45, errors: 5),
                onDismiss: {},
                onViewDetails: { print("View details") }
            )
        }
        .padding()
        .background(Color.black)
    }
}
#endif
