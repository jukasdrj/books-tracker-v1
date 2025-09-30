import SwiftUI
import SwiftData

/// Edition Metadata Card - iOS 26 Liquid Glass Design
/// Displays core bibliographic information and user tracking data
struct EditionMetadataView: View {
    let work: Work
    let edition: Edition

    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var showingStatusPicker = false
    @State private var showingNotesEditor = false

    // User's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries?.first
    }

    // Create or get user library entry
    @State private var libraryEntry: UserLibraryEntry?

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Core Metadata Section
                coreMetadataSection

                Divider()
                    .overlay(Color.secondary.opacity(0.3))

                // MARK: - User Tracking Section
                userTrackingSection

                // MARK: - Action Buttons
                actionButtonsSection
            }
            .padding(20)
        }
        .glassEffect(.regular, tint: themeStore.primaryColor.opacity(0.1))
        .onAppear {
            setupLibraryEntry()
        }
    }

    // MARK: - Core Metadata Section

    private var coreMetadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Work Title
            Text(work.title)
                .font(.headline.bold())
                .foregroundColor(.primary)
                .lineLimit(3)

            // Author Names
            Text(work.authorNames)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Publisher Info
            if !edition.publisherInfo.isEmpty {
                Text(edition.publisherInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Page Count
            if let pageCountString = edition.pageCountString {
                Text(pageCountString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Edition Format
            HStack(spacing: 8) {
                Image(systemName: edition.format.icon)
                    .foregroundColor(themeStore.primaryColor)

                Text(edition.format.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - User Tracking Section

    private var userTrackingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reading Status
            readingStatusIndicator

            // User Rating (if book is owned)
            if libraryEntry?.isOwned == true {
                userRatingView
            }

            // Reading Progress (if currently reading)
            if libraryEntry?.readingStatus == .reading {
                readingProgressView
            }

            // Notes Field
            notesSection
        }
    }

    private var readingStatusIndicator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Status")
                .font(.caption.bold())
                .foregroundColor(.primary)

            Button(action: {
                showingStatusPicker.toggle()
                triggerHaptic(.light)
            }) {
                HStack(spacing: 12) {
                    Image(systemName: currentStatus.systemImage)
                        .foregroundColor(currentStatus.color)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentStatus.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        Text(currentStatus.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(currentStatus.color.opacity(0.1))
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingStatusPicker) {
            ReadingStatusPicker(
                selectedStatus: Binding(
                    get: { currentStatus },
                    set: { newStatus in
                        updateReadingStatus(to: newStatus)
                    }
                )
            )
            .presentationDetents([.medium])
            .iOS26SheetGlass()
        }
    }

    private var userRatingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Rating")
                .font(.caption.bold())
                .foregroundColor(.primary)

            StarRatingView(
                rating: Binding(
                    get: { libraryEntry?.personalRating ?? 0 },
                    set: { newRating in
                        libraryEntry?.personalRating = newRating
                        libraryEntry?.touch()
                        saveContext()
                    }
                )
            )
        }
    }

    private var readingProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading Progress")
                .font(.caption.bold())
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ProgressView(value: libraryEntry?.readingProgress ?? 0.0)
                    .tint(themeStore.primaryColor)

                HStack {
                    Text("Page \(libraryEntry?.currentPage ?? 0)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let pageCount = edition.pageCount {
                        Text("of \(pageCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Notes")
                .font(.caption.bold())
                .foregroundColor(.primary)

            Button(action: {
                showingNotesEditor.toggle()
            }) {
                Text(libraryEntry?.notes?.isEmpty == false ? libraryEntry!.notes! : "Add your thoughts...")
                    .font(.subheadline)
                    .foregroundColor(libraryEntry?.notes?.isEmpty == false ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorView(
                notes: Binding(
                    get: { libraryEntry?.notes ?? "" },
                    set: { newNotes in
                        libraryEntry?.notes = newNotes.isEmpty ? nil : newNotes
                        libraryEntry?.touch()
                        saveContext()
                    }
                ),
                workTitle: work.title
            )
            .iOS26SheetGlass()
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if libraryEntry?.readingStatus == .wishlist {
                // Wishlist → To Read conversion
                Button("Add to Library") {
                    convertWishlistToOwned()
                    triggerHaptic(.medium)
                }
                .buttonStyle(GlassProminentButtonStyle(tint: themeStore.primaryColor))
                .frame(maxWidth: .infinity)
            }

            if libraryEntry?.readingStatus == .toRead {
                // Start Reading
                Button("Start Reading") {
                    startReading()
                    triggerHaptic(.medium)
                }
                .buttonStyle(GlassProminentButtonStyle(tint: .green))
                .frame(maxWidth: .infinity)
            }

            if libraryEntry?.readingStatus == .reading {
                // Mark as Completed
                Button("Mark as Read") {
                    markAsCompleted()
                    triggerHaptic(.medium)
                }
                .buttonStyle(GlassProminentButtonStyle(tint: .green))
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Helper Properties

    private var currentStatus: ReadingStatus {
        libraryEntry?.readingStatus ?? .wishlist
    }

    // MARK: - Setup and State Management

    private func setupLibraryEntry() {
        if let existingEntry = userEntry {
            libraryEntry = existingEntry
        } else {
            // Create wishlist entry if none exists
            let wishlistEntry = UserLibraryEntry.createWishlistEntry(for: work)
            modelContext.insert(wishlistEntry)
            libraryEntry = wishlistEntry
            saveContext()
        }
    }

    private func updateReadingStatus(to newStatus: ReadingStatus) {
        guard let entry = libraryEntry else { return }

        entry.readingStatus = newStatus
        entry.touch()

        // Handle status-specific logic
        switch newStatus {
        case .reading:
            if entry.dateStarted == nil {
                entry.dateStarted = Date()
            }
        case .read:
            entry.markAsCompleted()
        default:
            break
        }

        saveContext()
    }

    private func convertWishlistToOwned() {
        libraryEntry?.acquireEdition(edition, status: .toRead)
        saveContext()
    }

    private func startReading() {
        libraryEntry?.startReading()
        saveContext()
    }

    private func markAsCompleted() {
        libraryEntry?.markAsCompleted()
        saveContext()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Star Rating View

struct StarRatingView: View {
    @Binding var rating: Double
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Button(action: {
                    rating = Double(star)
                    triggerHaptic(.light)
                }) {
                    Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                        .foregroundColor(star <= Int(rating) ? .yellow : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if rating > 0 {
                Text("\(Int(rating))/5")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Reading Status Picker

struct ReadingStatusPicker: View {
    @Binding var selectedStatus: ReadingStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ReadingStatus.allCases, id: \.self) { status in
                Button(action: {
                    selectedStatus = status
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: status.systemImage)
                            .foregroundColor(status.color)
                            .font(.title3)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.displayName)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)

                            Text(status.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if status == selectedStatus {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.caption.bold())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Reading Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Notes Editor View

struct NotesEditorView: View {
    @Binding var notes: String
    let workTitle: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Notes for \(workTitle)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                TextEditor(text: $notes)
                    .focused($isTextEditorFocused)
                    .font(.body)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
                    .overlay {
                        if notes.isEmpty {
                            VStack {
                                HStack {
                                    Text("Add your thoughts...")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 20)
                                        .padding(.top, 8)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                    }

                Spacer()
            }
            .padding()
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                isTextEditorFocused = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)
        let context = container.mainContext

        // Sample data
        let author = Author(name: "Sample Author")
        let work = Work(title: "Sample Book Title", authors: [author])
        let edition = Edition(isbn: "9780123456789", publisher: "Sample Publisher", publicationDate: "2023", pageCount: 300, work: work)

        context.insert(author)
        context.insert(work)
        context.insert(edition)

        return container
    }()

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return EditionMetadataView(work: Work(title: "Sample Book"), edition: Edition())
        .modelContainer(container)
        .environment(\.iOS26ThemeStore, themeStore)
        .padding()
        .themedBackground()
}