import SwiftUI
import SwiftData

/// Single Book Detail View - iOS 26 Immersive Design
/// Features blurred cover art background with floating metadata card
struct WorkDetailView: View {
    let work: Work

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var selectedEdition: Edition?
    @State private var showingEditionPicker = false
    @State private var selectedAuthor: Author?

    // Primary edition for display
    private var primaryEdition: Edition {
        selectedEdition ?? work.primaryEdition ?? work.availableEditions.first ?? placeholderEdition
    }

    // Placeholder edition for works without editions
    private var placeholderEdition: Edition {
        Edition(work: work)
    }

    var body: some View {
        ZStack {
            // MARK: - Immersive Background
            immersiveBackground

            // MARK: - Main Content
            mainContent
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 32, height: 32)
                        }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if work.availableEditions.count > 1 {
                    Button("Editions") {
                        showingEditionPicker.toggle()
                    }
                    .foregroundColor(.white)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .frame(height: 32)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .onAppear {
            selectedEdition = work.primaryEdition
        }
        .sheet(isPresented: $showingEditionPicker) {
            EditionPickerView(
                work: work,
                selectedEdition: Binding(
                    get: { selectedEdition ?? primaryEdition },
                    set: { selectedEdition = $0 }
                )
            )
            .iOS26SheetGlass()
        }
        .sheet(item: $selectedAuthor) { author in
            AuthorSearchResultsView(author: author)
        }
    }

    // MARK: - Immersive Background

    private var immersiveBackground: some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred cover art background
                CachedAsyncImage(url: primaryEdition.coverImageURL.flatMap(URL.init)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 20)
                        .overlay {
                            // Color shift overlay
                            LinearGradient(
                                colors: [
                                    themeStore.primaryColor.opacity(0.3),
                                    themeStore.secondaryColor.opacity(0.2),
                                    Color.black.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                } placeholder: {
                    // Fallback gradient background
                    LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.6),
                            themeStore.secondaryColor.opacity(0.4),
                            Color.black.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top spacer for navigation bar
                Color.clear.frame(height: 60)

                // MARK: - Book Cover Hero
                bookCoverHero

                // MARK: - Edition Metadata Card
                EditionMetadataView(work: work, edition: primaryEdition)
                    .padding(.horizontal, 20)

                // Bottom padding
                Color.clear.frame(height: 40)
            }
        }
    }

    private var bookCoverHero: some View {
        VStack(spacing: 16) {
            // Large cover image
            CachedAsyncImage(url: primaryEdition.coverImageURL.flatMap(URL.init)) { image in
                image
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [
                            themeStore.primaryColor.opacity(0.4),
                            themeStore.secondaryColor.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 200, height: 300)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.8))

                            Text(work.title)
                                .font(.headline.bold())
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }

            // Work title and author (large, readable)
            VStack(spacing: 8) {
                Text(work.title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                // Clickable author names
                if let authors = work.authors, authors.count == 1, let author = authors.first {
                    Button {
                        selectedAuthor = author
                    } label: {
                        HStack(spacing: 4) {
                            Text(author.name)
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.9))
                            Image(systemName: "magnifyingglass")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(work.authorNames)
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Edition Picker View

struct EditionPickerView: View {
    let work: Work
    @Binding var selectedEdition: Edition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        NavigationStack {
            List(work.availableEditions, id: \.id) { edition in
                Button(action: {
                    selectedEdition = edition
                    dismiss()
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Edition title or format
                        Text(edition.editionTitle ?? edition.format.displayName)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        // Publisher info
                        if !edition.publisherInfo.isEmpty {
                            Text(edition.publisherInfo)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Format and pages
                        HStack {
                            Label(edition.format.displayName, systemImage: edition.format.icon)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let pageCount = edition.pageCountString {
                                Spacer()
                                Text(pageCount)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // ISBN
                        if let isbn = edition.primaryISBN {
                            Text("ISBN: \(isbn)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    edition.id == selectedEdition.id ?
                    Color.blue.opacity(0.1) : Color.clear
                )
            }
            .navigationTitle("Choose Edition")
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

// MARK: - Author Search Results View

/// Dedicated view for displaying search results for a specific author
struct AuthorSearchResultsView: View {
    let author: Author

    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var searchModel = SearchModel()
    @State private var selectedBook: SearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                // Content
                Group {
                    switch searchModel.searchState {
                    case .searching:
                        searchingView
                    case .results:
                        resultsView
                    case .noResults:
                        noResultsView
                    case .error:
                        errorView
                    default:
                        searchingView
                    }
                }
            }
            .navigationTitle("Books by \(author.name)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeStore.primaryColor)
                }
            }
            .navigationDestination(item: $selectedBook) { result in
                WorkDiscoveryView(searchResult: result)
            }
            .task {
                let criteria = AdvancedSearchCriteria()
                criteria.authorName = author.name
                searchModel.advancedSearch(criteria: criteria)
            }
        }
    }

    // MARK: - State Views

    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(themeStore.primaryColor)

            Text("Searching for books by \(author.name)...")
                .font(.headline)
                .foregroundColor(.primary)
        }
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(searchModel.searchResults) { result in
                    Button {
                        selectedBook = result
                    } label: {
                        iOS26AdaptiveBookCard(
                            work: result.work,
                            displayMode: .standard
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No books found")
                .font(.title2.bold())
                .foregroundColor(.primary)

            Text("We couldn't find any books by \(author.name)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Search Error")
                .font(.title2.bold())
                .foregroundColor(.primary)

            if let errorMessage = searchModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Try Again") {
                Task {
                    let criteria = AdvancedSearchCriteria()
                    criteria.authorName = author.name
                    searchModel.advancedSearch(criteria: criteria)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(themeStore.primaryColor)
        }
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)

    let context = container.mainContext

    // Sample data
    let author = Author(name: "Kazuo Ishiguro", culturalRegion: .asia)
    let work = Work(
        title: "Klara and the Sun",
        authors: [author],
        originalLanguage: "English",
        firstPublicationYear: 2021
    )
    let edition = Edition(
        isbn: "9780571364893",
        publisher: "Faber & Faber",
        publicationDate: "2021",
        pageCount: 303,
        format: .hardcover,
        work: work
    )

    context.insert(author)
    context.insert(work)
    context.insert(edition)

    let themeStore = BooksTrackerFeature.iOS26ThemeStore()

    return NavigationStack {
        WorkDetailView(work: work)
    }
    .modelContainer(container)
    .environment(\.iOS26ThemeStore, themeStore)
}