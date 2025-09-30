import SwiftUI
import SwiftData
import BooksTrackerFeature

@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()

    // MARK: - SwiftData Configuration

    /// SwiftData model container - created once and reused
    /// Configured for local storage (CloudKit sync disabled on simulator)
    let modelContainer: ModelContainer = {
        let schema = Schema([
            Work.self,
            Edition.self,
            Author.self,
            UserLibraryEntry.self
        ])

        #if targetEnvironment(simulator)
        // Simulator: Use in-memory storage for clean testing (no CloudKit)
        print("🧪 Running on simulator - using in-memory database")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,  // ← Clean slate every launch
            cloudKitDatabase: .none  // Explicitly disable CloudKit on simulator
        )
        #else
        // Device: Enable CloudKit sync via entitlements
        print("📱 Running on device - CloudKit sync enabled")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
            // CloudKit sync will be enabled automatically via entitlements
        )
        #endif

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Print detailed error for debugging
            print("❌ ModelContainer creation failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")

            #if targetEnvironment(simulator)
            print("💡 Simulator detected - trying in-memory fallback")
            // Last resort fallback for simulator
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Failed to create fallback ModelContainer: \(error)")
            }
            #else
            fatalError("Failed to create ModelContainer: \(error)")
            #endif
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