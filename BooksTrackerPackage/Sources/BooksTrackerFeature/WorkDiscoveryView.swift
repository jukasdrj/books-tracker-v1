import SwiftUI
import SwiftData

// MARK: - Work Discovery View

/// Dedicated view for displaying search results and allowing users to add books to their library
/// This separates discovery (temporary API data) from library management (persistent SwiftData)
@MainActor
public struct WorkDiscoveryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    let searchResult: SearchResult
    @State private var isAddingToLibrary = false
    @State private var selectedAction: LibraryAction = .wishlist
    @State private var showingSuccessAlert = false
    @State private var alertMessage = ""

    enum LibraryAction: CaseIterable {
        case wishlist
        case owned
        case reading

        var title: String {
            switch self {
            case .wishlist: return "Add to Wishlist"
            case .owned: return "Mark as Owned"
            case .reading: return "Start Reading"
            }
        }

        var systemImage: String {
            switch self {
            case .wishlist: return "heart"
            case .owned: return "books.vertical"
            case .reading: return "book.pages"
            }
        }

        var readingStatus: ReadingStatus {
            switch self {
            case .wishlist: return .wishlist
            case .owned: return .toRead
            case .reading: return .reading
            }
        }
    }

    public init(searchResult: SearchResult) {
        self.searchResult = searchResult
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Book header with cover and basic info
                    bookHeaderSection

                    // Book details section
                    bookDetailsSection

                    // Add to library section
                    addToLibrarySection

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .background {
                themeStore.backgroundGradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Book Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(themeStore.primaryColor)
                }
            }
            .alert("Success!", isPresented: $showingSuccessAlert) {
                Button("View Library") {
                    // Dismiss this view first
                    dismiss()

                    // Post notification to switch to library tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("SwitchToLibraryTab"),
                            object: nil
                        )
                    }
                }
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Book Header Section

    private var bookHeaderSection: some View {
        HStack(alignment: .top, spacing: 20) {
            // Book cover with cached image loading
            CachedAsyncImage(
                url: URL(string: searchResult.work.primaryEdition?.coverImageURL ?? "")
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed")
                                .font(.title)
                                .foregroundStyle(.secondary)

                            Text("Loading Cover...")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)

            // Book info
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(searchResult.work.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)

                    Text(searchResult.work.authorNames)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                if let year = searchResult.work.firstPublicationYear {
                    Label("Published \(year)", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let pageCount = searchResult.work.primaryEdition?.pageCount {
                    Label("\(pageCount) pages", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Provider badge
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.caption2)
                    Text(searchResult.provider.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .foregroundStyle(themeStore.primaryColor)

                Spacer()
            }

            Spacer()
        }
        .padding()
        .background {
            GlassEffectContainer {
                Rectangle()
                    .fill(.clear)
            }
        }
    }

    // MARK: - Book Details Section

    private var bookDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                if let language = searchResult.work.originalLanguage {
                    DetailRow(title: "Language", value: language.capitalized)
                }

                if let publisher = searchResult.work.primaryEdition?.publisher {
                    DetailRow(title: "Publisher", value: publisher)
                }

                if let isbn = searchResult.work.primaryEdition?.isbn {
                    DetailRow(title: "ISBN", value: isbn)
                }

                if !searchResult.work.subjectTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Categories")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80), spacing: 8)
                        ], spacing: 8) {
                            ForEach(Array(searchResult.work.subjectTags.prefix(6)), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background {
            GlassEffectContainer {
                Rectangle()
                    .fill(.clear)
            }
        }
    }

    // MARK: - Add to Library Section

    private var addToLibrarySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add to Library")
                .font(.title3)
                .fontWeight(.semibold)

            actionSelectionSection
            addToLibraryButton
        }
        .padding()
        .background {
            GlassEffectContainer {
                Rectangle()
                    .fill(.clear)
            }
        }
    }
    
    private var actionSelectionSection: some View {
        VStack(spacing: 12) {
            ForEach(LibraryAction.allCases, id: \.self) { action in
                actionSelectionRow(for: action)
            }
        }
    }
    
    private func actionSelectionRow(for action: LibraryAction) -> some View {
        Button {
            selectedAction = action
        } label: {
            HStack {
                actionIconView(for: action)
                actionTextView(for: action)
                Spacer()
                actionCheckmarkView(for: action)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedAction == action ? AnyShapeStyle(themeStore.primaryColor) : AnyShapeStyle(.ultraThinMaterial))
            }
        }
        .buttonStyle(.plain)
    }
    
    private func actionIconView(for action: LibraryAction) -> some View {
        Image(systemName: action.systemImage)
            .font(.title3)
            .foregroundColor(selectedAction == action ? .white : themeStore.primaryColor)
            .frame(width: 24)
    }
    
    private func actionTextView(for action: LibraryAction) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(selectedAction == action ? .white : .primary)

            Text(actionDescription(for: action))
                .font(.caption)
                .foregroundColor(selectedAction == action ? .white.opacity(0.8) : .secondary)
        }
    }
    
    @ViewBuilder
    private func actionCheckmarkView(for action: LibraryAction) -> some View {
        if selectedAction == action {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.white)
        }
    }
    
    private var addToLibraryButton: some View {
        Button {
            addToLibrary()
        } label: {
            HStack {
                if isAddingToLibrary {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }

                Text(isAddingToLibrary ? "Adding..." : selectedAction.title)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeStore.primaryColor)
            }
        }
        .disabled(isAddingToLibrary)
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func addToLibrary() {
        Task {
            await performAddToLibrary()
        }
    }

    @MainActor
    private func performAddToLibrary() async {
        isAddingToLibrary = true

        do {
            // ✅ DUPLICATE CHECK: Search for existing work with same title + author
            if try await findExistingWork() != nil {
                // Book already exists - show message
                alertMessage = "\"\(searchResult.work.title)\" is already in your library!"
                showingSuccessAlert = true
                isAddingToLibrary = false
                return
            }

            // Create Work, Authors, and Edition objects from search result
            let work = createWorkFromSearchResult()
            let edition = createEditionFromSearchResult(work: work)

            // Save to SwiftData context
            modelContext.insert(work)
            if let edition = edition {
                modelContext.insert(edition)
            }

            // Create user library entry
            let libraryEntry: UserLibraryEntry
            if selectedAction == .wishlist {
                libraryEntry = UserLibraryEntry.createWishlistEntry(for: work)
            } else {
                libraryEntry = UserLibraryEntry.createOwnedEntry(
                    for: work,
                    edition: edition ?? createDefaultEdition(work: work),
                    status: selectedAction.readingStatus
                )
            }

            // ✅ FIX: Link the entry to the work for library view filtering
            if work.userLibraryEntries == nil {
                work.userLibraryEntries = []
            }
            work.userLibraryEntries?.append(libraryEntry)

            modelContext.insert(libraryEntry)

            try modelContext.save()

            // Show success
            alertMessage = "\"\(work.title)\" has been added to your library!"
            showingSuccessAlert = true

        } catch {
            // Handle error
            print("Failed to add book to library: \(error)")
            alertMessage = "Failed to add book to library. Please try again."
            showingSuccessAlert = true
        }

        isAddingToLibrary = false
    }

    /// Find existing work in library by title and author
    private func findExistingWork() async throws -> Work? {
        let titleToSearch = searchResult.work.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let authorToSearch = searchResult.work.authorNames.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Query all works with library entries
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)

        // Find match by title + author
        return allWorks.first { work in
            guard work.userLibraryEntries?.isEmpty == false else { return false }

            let workTitle = work.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let workAuthor = work.authorNames.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            return workTitle == titleToSearch && workAuthor == authorToSearch
        }
    }

    private func createWorkFromSearchResult() -> Work {
        // Create authors first
        let authors = searchResult.authors.map { apiAuthor in
            Author(
                name: apiAuthor.name,
                gender: apiAuthor.gender,
                culturalRegion: apiAuthor.culturalRegion
            )
        }

        // Create work with proper relationships
        let work = Work(
            title: searchResult.work.title,
            authors: authors,
            originalLanguage: searchResult.work.originalLanguage,
            firstPublicationYear: searchResult.work.firstPublicationYear,
            subjectTags: searchResult.work.subjectTags
        )

        // Set external identifiers
        work.openLibraryID = searchResult.work.openLibraryID
        work.isbndbID = searchResult.work.isbndbID
        work.googleBooksVolumeID = searchResult.work.googleBooksVolumeID
        work.isbndbQuality = searchResult.work.isbndbQuality

        return work
    }

    private func createEditionFromSearchResult(work: Work) -> Edition? {
        guard let primaryEdition = searchResult.work.primaryEdition else { return nil }

        let edition = Edition(
            isbn: primaryEdition.isbn,
            publisher: primaryEdition.publisher,
            publicationDate: primaryEdition.publicationDate,
            pageCount: primaryEdition.pageCount,
            format: primaryEdition.format,
            coverImageURL: primaryEdition.coverImageURL,
            work: work
        )

        // Set external identifiers
        edition.openLibraryID = primaryEdition.openLibraryID
        edition.isbndbID = primaryEdition.isbndbID
        edition.googleBooksVolumeID = primaryEdition.googleBooksVolumeID

        return edition
    }

    private func createDefaultEdition(work: Work) -> Edition {
        return Edition(
            isbn: nil,
            publisher: nil,
            publicationDate: nil,
            pageCount: nil,
            format: .paperback,
            coverImageURL: nil,
            work: work
        )
    }

    private func actionDescription(for action: LibraryAction) -> String {
        switch action {
        case .wishlist: return "Want to read"
        case .owned: return "Have this book"
        case .reading: return "Currently reading"
        }
    }
}

// MARK: - Detail Row Component

private struct DetailRow: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Work Discovery View") {
    // Create a mock search result for preview
    let mockWork = Work(
        title: "The Martian",
        authors: [Author(name: "Andy Weir", gender: .male, culturalRegion: .northAmerica)],
        originalLanguage: "English",
        firstPublicationYear: 2011,
        subjectTags: ["Science Fiction", "Mars", "Survival"]
    )

    let mockEdition = Edition(
        isbn: "9780553418026",
        publisher: "Crown Publishing",
        publicationDate: "2014-02-11",
        pageCount: 369,
        format: .paperback,
        coverImageURL: "https://example.com/cover.jpg",
        work: mockWork
    )

    let mockSearchResult = SearchResult(
        work: mockWork,
        editions: [mockEdition],
        authors: [Author(name: "Andy Weir", gender: .male, culturalRegion: .northAmerica)],
        relevanceScore: 1.0,
        provider: "google"
    )

    WorkDiscoveryView(searchResult: mockSearchResult)
        .modelContainer(for: [Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        .environment(iOS26ThemeStore())
}