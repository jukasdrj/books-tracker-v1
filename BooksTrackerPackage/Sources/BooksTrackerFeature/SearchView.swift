import SwiftUI
import SwiftData

// MARK: - Main Search View

public struct SearchView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchModel = SearchModel()
    @State private var selectedBook: SearchResult?
    @State private var showingBookDetail = false
    @Namespace private var searchTransition

    // Performance tracking for development
    @State private var performanceText = ""

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Themed background
                backgroundView

                // Main content based on search state
                VStack(spacing: 0) {
                    // Search bar with ergonomic placement
                    searchBarSection
                        .zIndex(1) // Ensure search bar stays on top

                    // Content area
                    Spacer(minLength: 0)

                    searchContentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer(minLength: 0)

                    // Performance info (development only)
                    if !performanceText.isEmpty {
                        performanceSection
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Initialize search model
            await loadInitialData()
        }
        .sheet(isPresented: $showingBookDetail) {
            if let selectedBook = selectedBook {
                BookDetailSheet(searchResult: selectedBook)
            }
        }
    }

    // MARK: - Background View

    private var backgroundView: some View {
        ZStack {
            // Base themed background
            themeStore.backgroundGradient
                .ignoresSafeArea()

            // Subtle pattern overlay for depth
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.1)
                .ignoresSafeArea()
        }
    }

    // MARK: - Search Bar Section

    private var searchBarSection: some View {
        iOS26MorphingSearchBar(
            searchText: $searchModel.searchText,
            isSearching: $searchModel.isSearching,
            suggestions: searchModel.searchSuggestions,
            onSearchSubmit: {
                performSearch()
            },
            onClear: {
                searchModel.clearSearch()
                updatePerformanceText()
            },
            onSuggestionTap: { suggestion in
                searchModel.search(query: suggestion)
                updatePerformanceText()
            }
        )
        .searchBarPlacement(.automatic)
        .onChange(of: searchModel.searchText) { oldValue, newValue in
            searchModel.search(query: newValue)
            updatePerformanceText()
        }
    }

    // MARK: - Search Content Area

    @ViewBuilder
    private var searchContentArea: some View {
        switch searchModel.searchState {
        case .initial:
            initialStateView

        case .searching:
            searchingStateView

        case .results:
            resultsStateView

        case .noResults:
            noResultsStateView

        case .error(let message):
            errorStateView(message: message)
        }
    }

    // MARK: - State Views

    private var initialStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Welcome section
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(themeStore.primaryColor)

                    VStack(spacing: 8) {
                        Text("Discover Your Next Great Read")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text("Search millions of books by title, author, or ISBN")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)

                // Trending books grid
                if !searchModel.trendingBooks.isEmpty {
                    trendingBooksSection
                }

                Spacer(minLength: 120) // Account for search bar at bottom
            }
            .padding(.horizontal, 20)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity.combined(with: .scale(scale: 1.05))
        ))
    }

    private var trendingBooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Trending Books")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: "flame")
                    .foregroundStyle(themeStore.primaryColor)
                    .font(.title3)
            }

            iOS26FluidGridSystem<SearchResult, AnyView>.bookLibrary(
                items: searchModel.trendingBooks
            ) { book in
                AnyView(
                    Button {
                        selectedBook = book
                        showingBookDetail = true
                    } label: {
                        iOS26FloatingBookCard(
                            work: book.work,
                            namespace: searchTransition
                        )
                    }
                    .buttonStyle(.plain)
                )
            }
        }
    }

    private var searchingStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                // Liquid glass loading indicator
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Circle()
                                .fill(themeStore.glassStint(intensity: 0.2))
                        }

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(themeStore.primaryColor)
                }

                VStack(spacing: 8) {
                    Text("Searching...")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text("Finding the perfect books for you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var resultsStateView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Results header
                HStack {
                    Text("\(searchModel.searchResults.count) results")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if searchModel.cacheHitRate > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(themeStore.primaryColor)
                                .font(.caption)

                            Text("Cached")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Results list
                ForEach(searchModel.searchResults) { result in
                    Button {
                        selectedBook = result
                        showingBookDetail = true
                    } label: {
                        iOS26LiquidListRow(
                            work: result.work,
                            displayStyle: .standard
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 120) // Account for search bar
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var noResultsStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ContentUnavailableView {
                Label("No Results Found", systemImage: "magnifyingglass")
            } description: {
                Text("Try different keywords or check your spelling")
            } actions: {
                Button("Clear Search") {
                    searchModel.clearSearch()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ContentUnavailableView {
                Label("Search Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    searchModel.retryLastSearch()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(spacing: 4) {
            Divider()

            Text(performanceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helper Methods

    private func performSearch() {
        // Search is automatically triggered by text changes
        // This method is for explicit search submission
        updatePerformanceText()

        // Provide haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func loadInitialData() async {
        // Load trending books or popular searches
        // This is handled by SearchModel initialization
    }

    private func updatePerformanceText() {
        if searchModel.lastSearchTime > 0 {
            let cacheStatus = searchModel.cacheHitRate > 0 ? "CACHED" : "FRESH"
            performanceText = String(format: "%.0fms • %@ • %.0f%% cache rate",
                                     searchModel.lastSearchTime * 1000,
                                     cacheStatus,
                                     searchModel.cacheHitRate * 100)
        } else {
            performanceText = ""
        }
    }
}

// MARK: - Book Detail Sheet

private struct BookDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    let searchResult: SearchResult

    var body: some View {
        NavigationStack {
            WorkDetailView(work: searchResult.work)
                .navigationTitle(searchResult.work.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.medium)
                        .tint(themeStore.primaryColor)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Accessibility Extensions

extension SearchView {
    private var accessibilityLabel: String {
        switch searchModel.searchState {
        case .initial:
            return "Search for books. Currently showing trending books."
        case .searching:
            return "Searching for books. Please wait."
        case .results:
            return "Search results. \(searchModel.searchResults.count) books found."
        case .noResults:
            return "No search results found."
        case .error(let message):
            return "Search error: \(message)"
        }
    }
}

// MARK: - Preview

#Preview("Search View - Initial State") {
    NavigationStack {
        SearchView()
    }
    .environment(\.iOS26ThemeStore, iOS26ThemeStore())
    .modelContainer(for: [Work.self, Edition.self, Author.self, UserLibraryEntry.self])
}

#Preview("Search View - Dark Mode") {
    NavigationStack {
        SearchView()
    }
    .environment(\.iOS26ThemeStore, iOS26ThemeStore())
    .modelContainer(for: [Work.self, Edition.self, Author.self, UserLibraryEntry.self])
    .preferredColorScheme(.dark)
}