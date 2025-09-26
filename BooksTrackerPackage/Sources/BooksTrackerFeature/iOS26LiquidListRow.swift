import SwiftUI
import SwiftData

/// Liquid list row with iOS 26 design patterns
/// Optimized for dense information display with smooth interactions
struct iOS26LiquidListRow: View {
    let work: Work
    let displayStyle: ListRowStyle

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showingQuickActions = false

    // Current user's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries.first
    }

    // Primary edition for display
    private var primaryEdition: Edition? {
        userEntry?.edition ?? work.availableEditions.first
    }

    init(work: Work, displayStyle: ListRowStyle = .standard) {
        self.work = work
        self.displayStyle = displayStyle
    }

    var body: some View {
        HStack(spacing: rowSpacing) {
            // Book cover thumbnail
            coverThumbnail

            // Main content area
            mainContent

            // Trailing accessories
            trailingAccessories
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            liquidRowBackground
        }
        .contextMenu {
            quickActionsMenu
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(work: work)
                .presentationDetents([.medium])
                .iOS26SheetGlass()
        }
    }

    // MARK: - Cover Thumbnail

    private var coverThumbnail: some View {
        AsyncImage(url: primaryEdition?.coverURL) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        themeStore.primaryColor.opacity(0.3),
                        themeStore.secondaryColor.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    Image(systemName: "book.closed")
                        .font(thumbnailIconFont)
                        .foregroundColor(.white.opacity(0.8))
                }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius))
        .glassEffect(.subtle, tint: themeStore.primaryColor.opacity(0.1))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            // Title and author
            titleAndAuthorSection

            // Metadata row
            if displayStyle != .minimal {
                metadataRow
            }

            // Reading progress (if applicable)
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0,
               displayStyle == .detailed {
                readingProgressSection(userEntry.readingProgress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleAndAuthorSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Book title
            Text(work.title)
                .font(titleFont)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)

            // Author names
            Text(work.authorNames)
                .font(authorFont)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Publication year
            if let year = work.firstPublicationYear {
                Label("\(year)", systemImage: "calendar")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Edition format
            if let edition = primaryEdition {
                Label(edition.format.shortName, systemImage: edition.format.icon)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Cultural diversity indicator
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityIndicator
            }

            Spacer()
        }
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 2) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(themeStore.culturalColors.international)

            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            themeStore.culturalColors.international.opacity(0.1),
            in: Capsule()
        )
    }

    private func readingProgressSection(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption2.bold())
                    .foregroundColor(.primary)
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: themeStore.primaryColor))
                .scaleEffect(y: 0.8)
        }
    }

    // MARK: - Trailing Accessories

    private var trailingAccessories: some View {
        VStack(spacing: accessorySpacing) {
            // Status indicator
            if let userEntry = userEntry {
                statusIndicator(for: userEntry.readingStatus)
            }

            // Quick action button
            if displayStyle == .detailed {
                quickActionButton
            }
        }
    }

    private func statusIndicator(for status: ReadingStatus) -> some View {
        Group {
            switch displayStyle {
            case .minimal:
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)

            case .standard:
                VStack(spacing: 2) {
                    Image(systemName: status.systemImage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(status.color, in: Circle())
                        .glassEffect(.subtle, interactive: true)

                    if displayStyle == .standard {
                        Text(status.shortName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

            case .detailed:
                VStack(alignment: .trailing, spacing: 4) {
                    Label(status.displayName, systemImage: status.systemImage)
                        .font(.caption)
                        .foregroundColor(status.color)
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .glassEffect(.subtle, tint: status.color.opacity(0.2))

                    Text(status.shortName)
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var quickActionButton: some View {
        Button {
            showingQuickActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(.quaternary, in: Circle())
                .glassEffect(.subtle, interactive: true)
        }
        .buttonStyle(PressedButtonStyle())
    }

    // MARK: - Background

    private var liquidRowBackground: some View {
        RoundedRectangle(cornerRadius: rowCornerRadius)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .fill(themeStore.primaryColor.opacity(0.05))
                    .blendMode(.overlay)
            }
            .overlay {
                // Subtle glass reflection
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.2), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.3),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
    }

    // MARK: - Quick Actions

    private var quickActionsMenu: some View {
        Group {
            if let userEntry = userEntry {
                Button("Mark as Reading", systemImage: "book.pages") {
                    updateReadingStatus(.reading)
                }

                Button("Mark as Read", systemImage: "checkmark.circle") {
                    updateReadingStatus(.read)
                }

                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            } else {
                Button("Add to Library", systemImage: "plus.circle") {
                    addToLibrary()
                }

                Button("Add to Wishlist", systemImage: "heart") {
                    addToWishlist()
                }
            }

            Button("View Details", systemImage: "info.circle") {
                // Navigate to detail view
            }
        }
    }

    // MARK: - Style Properties

    private var rowSpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    private var horizontalPadding: CGFloat {
        switch displayStyle {
        case .minimal: return 12
        case .standard: return 16
        case .detailed: return 20
        }
    }

    private var verticalPadding: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    private var thumbnailSize: CGSize {
        switch displayStyle {
        case .minimal: return CGSize(width: 32, height: 48)
        case .standard: return CGSize(width: 48, height: 72)
        case .detailed: return CGSize(width: 60, height: 90)
        }
    }

    private var thumbnailCornerRadius: CGFloat {
        switch displayStyle {
        case .minimal: return 4
        case .standard: return 6
        case .detailed: return 8
        }
    }

    private var thumbnailIconFont: Font {
        switch displayStyle {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .body
        }
    }

    private var contentSpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 2
        case .standard: return 4
        case .detailed: return 6
        }
    }

    private var titleFont: Font {
        switch displayStyle {
        case .minimal: return .caption
        case .standard: return .subheadline
        case .detailed: return .headline
        }
    }

    private var authorFont: Font {
        switch displayStyle {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .subheadline
        }
    }

    private var titleLineLimit: Int {
        switch displayStyle {
        case .minimal: return 1
        case .standard: return 2
        case .detailed: return 3
        }
    }

    private var accessorySpacing: CGFloat {
        switch displayStyle {
        case .minimal: return 4
        case .standard: return 6
        case .detailed: return 8
        }
    }

    private var rowCornerRadius: CGFloat {
        switch displayStyle {
        case .minimal: return 8
        case .standard: return 12
        case .detailed: return 16
        }
    }

    // MARK: - Actions


    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func updateReadingStatus(_ status: ReadingStatus) {
        guard let userEntry = userEntry else { return }

        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()

        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }

    private func addToLibrary() {
        let primaryEdition = work.availableEditions.first
        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: primaryEdition ?? Edition(work: work),
            status: .toRead
        )
        // Add to SwiftData context
    }

    private func addToWishlist() {
        let entry = UserLibraryEntry.createWishlistEntry(for: work)
        // Add to SwiftData context
    }

    private func removeFromLibrary() {
        guard let userEntry = userEntry else { return }
        // Remove from SwiftData context
    }
}

// MARK: - List Row Styles

enum ListRowStyle: String, CaseIterable {
    case minimal = "minimal"
    case standard = "standard"
    case detailed = "detailed"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .detailed: return "Detailed"
        }
    }
}

// MARK: - Extensions are now defined in ModelTypes.swift

// MARK: - Preview

#Preview {
    let sampleWork = Work(
        title: "Klara and the Sun",
        authors: [Author(name: "Kazuo Ishiguro")],
        originalLanguage: "English",
        firstPublicationYear: 2021
    )

    return NavigationStack {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(ListRowStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(style.displayName)
                            .font(.headline.bold())
                            .padding(.horizontal)

                        iOS26LiquidListRow(work: sampleWork, displayStyle: style)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Liquid List Rows")
        .themedBackground()
        .iOS26NavigationGlass()
    }
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
    .iOS26ThemeStore(iOS26ThemeStore())
}