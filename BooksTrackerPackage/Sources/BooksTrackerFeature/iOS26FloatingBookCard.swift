import SwiftUI
import SwiftData

/// V1.0 Specification: "Floating cover images with a small info card below"
/// Fluid grid layout adapting to screen size (2 columns phone, more on tablet)
struct iOS26FloatingBookCard: View {
    let work: Work
    let namespace: Namespace.ID

    @State private var showingQuickActions = false
    @Environment(\.iOS26ThemeStore) private var themeStore

    // Current user's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries.first
    }

    // Primary edition for display
    private var primaryEdition: Edition? {
        userEntry?.edition ?? work.availableEditions.first
    }

    var body: some View {
        VStack(spacing: 10) {
            // FLOATING COVER IMAGE (Main V1.0 Requirement)
            floatingCoverImage
                .glassEffectID("cover-\(work.id)", in: namespace)

            // SMALL INFO CARD BELOW (V1.0 Requirement)
            smallInfoCard
                .glassEffectID("info-\(work.id)", in: namespace)
        }
        .contentShape(Rectangle())
        .contextMenu {
            quickActionsMenu
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(work: work)
                .presentationDetents([.medium])
                .iOS26SheetGlass()
        }
    }

    // MARK: - Floating Cover Image

    private var floatingCoverImage: some View {
        AsyncImage(url: primaryEdition?.coverURL) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            // Refined Placeholder with Theme Colors
            ZStack {
                Rectangle()
                    .fill(themeStore.primaryColor.gradient.opacity(0.3))
                
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))

                    Text(work.title)
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 240) // Consistent card height
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, tint: .white.opacity(0.1))
        .shadow(
            color: .black.opacity(0.15),
            radius: 12,
            x: 0,
            y: 8
        )
        .overlay(alignment: .topTrailing) {
            // Status indicator overlay
            if let userEntry = userEntry {
                statusIndicator(for: userEntry.readingStatus)
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            // Cultural diversity indicator
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityBadge
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            // Reading progress overlay for active books
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0 {
                ProgressView(value: userEntry.readingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
                    .scaleEffect(y: 1.5, anchor: .bottom)
                    .padding(10)
                    .background(.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Refined Small Info Card

    private var smallInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(work.title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true) // Prevents text from truncating prematurely

            Text(work.authorNames)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Refined metadata row for status and format
            HStack {
                if let userEntry = userEntry {
                    infoCardStatus(for: userEntry.readingStatus)
                }
                
                Spacer()

                if let edition = primaryEdition {
                    // ✅ FIX: Use Image(systemName:) for proper icon display
                    Image(systemName: edition.format.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Status Indicators

    private func statusIndicator(for status: ReadingStatus) -> some View {
        Circle()
            .fill(status.color.gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
            .glassEffect(.subtle)
            .shadow(color: status.color.opacity(0.4), radius: 5, x: 0, y: 2)
    }
    
    // ✅ NEW: Compact status indicator for the info card
    private func infoCardStatus(for status: ReadingStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundColor(status.color)
        }
    }

    private var culturalDiversityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))

            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .glassEffect(.subtle)
    }

    // MARK: - Quick Actions

    private var quickActionsMenu: some View {
        Group {
            if let userEntry = userEntry {
                // Status change submenu
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(ReadingStatus.allCases.filter { $0 != userEntry.readingStatus }, id: \.self) { status in
                        Button(status.displayName, systemImage: status.systemImage) {
                            updateReadingStatus(status)
                        }
                    }
                }

                Divider()

                // Quick rating (if owned)
                if !userEntry.isWishlistItem {
                    Menu("Rate Book", systemImage: "star") {
                        ForEach(1...5, id: \.self) { rating in
                            Button("\(rating) Stars") {
                                setRating(Double(rating))
                            }
                        }
                        Button("Remove Rating") {
                            setRating(0)
                        }
                    }
                }

                Divider()

                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            } else {
                // Not in library actions
                Button("Add to Library", systemImage: "plus.circle") {
                    addToLibrary()
                }

                Button("Add to Wishlist", systemImage: "heart") {
                    addToWishlist()
                }
            }
        }
    }

    // MARK: - Actions

    private func updateReadingStatus(_ status: ReadingStatus) {
        guard let userEntry = userEntry else { return }

        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()

        // Haptic feedback
        triggerHapticFeedback(.success)
    }

    private func setRating(_ rating: Double) {
        guard let userEntry = userEntry, !userEntry.isWishlistItem else { return }

        userEntry.personalRating = rating > 0 ? rating : nil
        userEntry.rating = rating > 0 ? Int(rating) : nil
        userEntry.touch()

        // Haptic feedback
        triggerHapticFeedback(.success)
    }

    private func addToLibrary() {
        let primaryEdition = work.availableEditions.first
        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: primaryEdition ?? Edition(work: work),
            status: .toRead
        )

        work.userLibraryEntries.append(entry)
        triggerHapticFeedback(.success)
    }

    private func addToWishlist() {
        let entry = UserLibraryEntry.createWishlistEntry(for: work)
        work.userLibraryEntries.append(entry)
        triggerHapticFeedback(.success)
    }

    private func removeFromLibrary() {
        guard let userEntry = userEntry else { return }

        if let index = work.userLibraryEntries.firstIndex(of: userEntry) {
            work.userLibraryEntries.remove(at: index)
        }

        triggerHapticFeedback(.warning)
    }

    private func triggerHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(type)
    }
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    let work: Work
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Work info header
                HStack(spacing: 16) {
                    AsyncImage(url: work.primaryEdition?.coverImageURL.flatMap(URL.init)) { image in
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                    .frame(width: 60, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title)
                            .font(.headline.bold())
                            .lineLimit(2)

                        Text(work.authorNames)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let year = work.firstPublicationYear {
                            Text("\(year)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Quick action buttons
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    QuickActionButton(
                        title: "Start Reading",
                        icon: "book.pages",
                        color: .blue
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "Add to Wishlist",
                        icon: "heart",
                        color: .pink
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "View Details",
                        icon: "info.circle",
                        color: .purple
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "Share",
                        icon: "square.and.arrow.up",
                        color: .green
                    ) {
                        // Action
                        dismiss()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            // .glassEffect(.regular.tint(color.opacity(0.1)))
        }
        .buttonStyle(PressedButtonStyle())
    }
}

// MARK: - Press Events Modifier (Removed - using simultaneousGesture instead)

// MARK: - Pressed Button Style

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let sampleWork = Work(
        title: "The Adventures of Huckleberry Finn",
        authors: [Author(name: "Mark Twain")],
        originalLanguage: "English",
        firstPublicationYear: 1884
    )

    return VStack {
        iOS26FloatingBookCard(work: sampleWork, namespace: Namespace().wrappedValue)
            .frame(width: 160)

        Spacer()
    }
    .padding()
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}