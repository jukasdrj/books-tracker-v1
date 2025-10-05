import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: MainTab = .library

    public var body: some View {
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
            }
            .tabItem {
                Label("Search", systemImage: selectedTab == .search ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }
            .tag(MainTab.search)

            // Insights Tab
            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Insights", systemImage: selectedTab == .insights ? "chart.bar.fill" : "chart.bar")
            }
            .tag(MainTab.insights)

            // Settings Tab
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: selectedTab == .settings ? "gear.circle.fill" : "gear")
            }
            .tag(MainTab.settings)
        }
        .tint(themeStore.primaryColor)
        .themedBackground()
        // Sample data disabled for production - empty library on first launch
        // .onAppear {
        //     setupSampleData()
        // }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToLibraryTab"))) { _ in
            selectedTab = .library
        }
    }

    public init() {}

    // MARK: - Sample Data Setup

    private func setupSampleData() {
        // Only add sample data if the library is empty
        let fetchRequest = FetchDescriptor<Work>()
        let existingWorks = try? modelContext.fetch(fetchRequest)

        if existingWorks?.isEmpty == true {
            addSampleData()
        }
    }

    private func addSampleData() {
        // Sample Authors
        let kazuoIshiguro = Author(
            name: "Kazuo Ishiguro",
            gender: .male,
            culturalRegion: .asia
        )

        let octaviaButler = Author(
            name: "Octavia E. Butler",
            gender: .female,
            culturalRegion: .northAmerica
        )

        let chimamandaNgozi = Author(
            name: "Chimamanda Ngozi Adichie",
            gender: .female,
            culturalRegion: .africa
        )

        modelContext.insert(kazuoIshiguro)
        modelContext.insert(octaviaButler)
        modelContext.insert(chimamandaNgozi)

        // Sample Works
        let klaraAndTheSun = Work(
            title: "Klara and the Sun",
            authors: [kazuoIshiguro],
            originalLanguage: "English",
            firstPublicationYear: 2021
        )

        let kindred = Work(
            title: "Kindred",
            authors: [octaviaButler],
            originalLanguage: "English",
            firstPublicationYear: 1979
        )

        let americanah = Work(
            title: "Americanah",
            authors: [chimamandaNgozi],
            originalLanguage: "English",
            firstPublicationYear: 2013
        )

        modelContext.insert(klaraAndTheSun)
        modelContext.insert(kindred)
        modelContext.insert(americanah)

        // Sample Editions
        let klaraEdition = Edition(
            isbn: "9780571364893",
            publisher: "Faber & Faber",
            publicationDate: "2021",
            pageCount: 303,
            format: .hardcover,
            work: klaraAndTheSun
        )

        let kindredEdition = Edition(
            isbn: "9780807083697",
            publisher: "Beacon Press",
            publicationDate: "1979",
            pageCount: 287,
            format: .paperback,
            work: kindred
        )

        let americanahEdition = Edition(
            isbn: "9780307455925",
            publisher: "Knopf",
            publicationDate: "2013",
            pageCount: 477,
            format: .ebook,
            work: americanah
        )

        modelContext.insert(klaraEdition)
        modelContext.insert(kindredEdition)
        modelContext.insert(americanahEdition)

        // Sample Library Entries
        let klaraEntry = UserLibraryEntry.createOwnedEntry(
            for: klaraAndTheSun,
            edition: klaraEdition,
            status: .reading
        )
        klaraEntry.readingProgress = 0.35
        klaraEntry.dateStarted = Calendar.current.date(byAdding: .day, value: -7, to: Date())

        let kindredEntry = UserLibraryEntry.createOwnedEntry(
            for: kindred,
            edition: kindredEdition,
            status: .read
        )
        kindredEntry.dateCompleted = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        kindredEntry.personalRating = 5.0

        let americanahEntry = UserLibraryEntry.createWishlistEntry(for: americanah)

        modelContext.insert(klaraEntry)
        modelContext.insert(kindredEntry)
        modelContext.insert(americanahEntry)

        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save sample data: \(error)")
        }
    }
}

// MARK: - Tab Navigation

enum MainTab: String, CaseIterable {
    case library = "library"
    case search = "search"
    case insights = "insights"
    case settings = "settings"

    var displayName: String {
        switch self {
        case .library: return "Library"
        case .search: return "Search"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Placeholder Views

struct InsightsView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)

            Text("Reading Insights")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Track your reading progress and discover patterns in your literary journey")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .navigationTitle("Insights")
    }
}

// SettingsView now implemented in SettingsView.swift


// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .iOS26ThemeStore(iOS26ThemeStore())
}