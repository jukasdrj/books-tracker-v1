import SwiftUI
import SwiftData
import BooksTrackerFeature

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .iOS26ThemeStore(themeStore)
                .modelContainer(modelContainer)
        }
    }

    // MARK: - SwiftData Configuration

    private var modelContainer: ModelContainer {
        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}