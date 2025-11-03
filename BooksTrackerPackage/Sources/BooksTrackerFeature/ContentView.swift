import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var selectedTab: MainTab = .library
    @State private var searchCoordinator = SearchCoordinator()
    @State private var dtoMapper: DTOMapper?

    // Enrichment progress tracking (no Live Activity required!)
    @State private var isEnriching = false
    @State private var enrichmentProgress: (completed: Int, total: Int) = (0, 0)
    @State private var currentBookTitle = ""

    public var body: some View {
        if #available(iOS 26.0, *) {
            Group {
                if let dtoMapper = dtoMapper {
                    TabView(selection: $selectedTab) {
                        // Library Tab
                        NavigationStack {
                            iOS26LiquidLibraryView()
                        }
                        .tabItem {
                            Label("Library", systemImage: selectedTab == .library ? "books.vertical.fill" : "books.vertical")
                        }
                        .tag(MainTab.library)

                        // Search Tab
                        NavigationStack {
                            SearchView()
                                .environment(searchCoordinator)
                        }
                        .tabItem {
                            Label("Search", systemImage: selectedTab == .search ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        }
                        .tag(MainTab.search)

                        // Shelf Tab
                        NavigationStack {
                            BookshelfScannerView()
                        }
                        .tabItem {
                            Label("Shelf", systemImage: selectedTab == .shelf ? "viewfinder.circle.fill" : "viewfinder")
                        }
                        .tag(MainTab.shelf)

                        // Insights Tab
                        NavigationStack {
                            InsightsView()
                        }
                        .tabItem {
                            Label("Insights", systemImage: selectedTab == .insights ? "chart.bar.fill" : "chart.bar")
                        }
                        .tag(MainTab.insights)
                    }
                    .environment(\.dtoMapper, dtoMapper)
                    .tint(themeStore.primaryColor)
                    #if os(iOS)
                    .tabBarMinimizeBehavior(
                        voiceOverEnabled || reduceMotion ? .never : (featureFlags.enableTabBarMinimize ? .onScrollDown : .never)
                    )
                    #endif
                } else {
                    ProgressView()
                }
            }
            .themedBackground()
            .onAppear(perform: setupDTOMapper)
            .task {
                // Validate enrichment queue on app startup - remove stale persistent IDs
                EnrichmentQueue.shared.validateQueue(in: modelContext)
            }
            .task {
                // Clean up temporary scan images after all books reviewed
                await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
                // Clean up orphaned temp files from failed scans (24h+ old)
                await ImageCleanupService.shared.cleanupOrphanedFiles(in: modelContext)
            }
            .task {
                // Setup sample data if library is empty
                let generator = SampleDataGenerator(modelContext: modelContext)
                generator.setupSampleDataIfNeeded()
            }
            .task {
                await handleNotifications()
            }
            .overlay(alignment: .bottom) {
                if isEnriching {
                    EnrichmentBanner(
                        completed: enrichmentProgress.completed,
                        total: enrichmentProgress.total,
                        currentBookTitle: currentBookTitle,
                        themeStore: themeStore
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEnriching)
        } else {
            // Fallback on earlier versions
        }
    }

    private func setupDTOMapper() {
        if dtoMapper == nil {
            dtoMapper = DTOMapper(modelContext: modelContext)
        }
    }

    public init() {}

    // MARK: - Notification Handling (Swift 6.2)

    private func handleNotifications() async {
        // Handle each notification type sequentially to avoid Swift 6 isolation checker limitations
        // See: https://github.com/swiftlang/swift/issues/XXXXX
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .switchToLibraryTab) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentStarted) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentProgress) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .enrichmentCompleted) {
                handle(notification)
            }
        }
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .searchForAuthor) {
                handle(notification)
            }
        }
    }

    @MainActor
    private func handle(_ notification: Notification) {
        switch notification.name {
        case .switchToLibraryTab:
            selectedTab = .library

        case .enrichmentStarted:
            if let userInfo = notification.userInfo,
               let total = userInfo["totalBooks"] as? Int {
                isEnriching = true
                enrichmentProgress = (0, total)
                currentBookTitle = ""
            }

        case .enrichmentProgress:
            if let userInfo = notification.userInfo,
               let completed = userInfo["completed"] as? Int,
               let total = userInfo["total"] as? Int,
               let title = userInfo["currentTitle"] as? String {
                enrichmentProgress = (completed, total)
                currentBookTitle = title
            }

        case .enrichmentCompleted:
            isEnriching = false

        case .searchForAuthor:
            if let authorName = notification.userInfo?["authorName"] as? String {
                selectedTab = .search
                searchCoordinator.setPendingAuthorSearch(authorName)
                // SearchView will observe the coordinator and trigger search when tab becomes visible
            }

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let switchToLibraryTab = Notification.Name("SwitchToLibraryTab")
    static let enrichmentStarted = Notification.Name("EnrichmentStarted")
    static let enrichmentProgress = Notification.Name("EnrichmentProgress")
    static let enrichmentCompleted = Notification.Name("EnrichmentCompleted")
    static let libraryWasReset = Notification.Name("LibraryWasReset")
    static let searchForAuthor = Notification.Name("SearchForAuthor")
}

// MARK: - Tab Navigation

enum MainTab: String, CaseIterable {
    case library = "library"
    case search = "search"
    case shelf = "shelf"
    case insights = "insights"

    var displayName: String {
        switch self {
        case .library: return "Library"
        case .search: return "Search"
        case .shelf: return "Shelf"
        case .insights: return "Insights"
        }
    }
}

// MARK: - Placeholder Views

// SettingsView now implemented in SettingsView.swift
// InsightsView now implemented in Insights/InsightsView.swift

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    ContentView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
