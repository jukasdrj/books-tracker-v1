import SwiftUI
import SwiftData
import BooksTrackerFeature

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()

    // MARK: - SwiftData Configuration

    /// SwiftData model container - created once and reused
    /// Configured for local storage (CloudKit sync via entitlements)
    let modelContainer: ModelContainer = {
        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
            // CloudKit sync will be enabled automatically via entitlements
            // No need to specify cloudKitDatabase here - it can cause issues
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Print detailed error for debugging
            print("❌ ModelContainer creation failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .iOS26ThemeStore(themeStore)
                .modelContainer(modelContainer)
        }
    }
}