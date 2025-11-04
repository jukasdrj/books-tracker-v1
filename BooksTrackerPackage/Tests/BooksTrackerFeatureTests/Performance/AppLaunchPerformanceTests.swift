import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("App Launch Performance")
struct AppLaunchPerformanceTests {

    @Test("Launch metrics tracking")
    func testLaunchMetricsTracking() async throws {
        let metrics = LaunchMetrics.shared

        metrics.recordMilestone("Test milestone 1")
        try await Task.sleep(for: .milliseconds(10))
        metrics.recordMilestone("Test milestone 2")

        let total = metrics.totalLaunchTime()
        #expect(total != nil)
        #expect(total! >= 10) // At least 10ms elapsed
    }

    @Test("ModelContainer creation is fast")
    func testModelContainerCreation() async throws {
        let start = CFAbsoluteTimeGetCurrent()

        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ ModelContainer creation: \(Int(elapsed))ms")
        #expect(elapsed < 200) // Should be < 200ms

        _ = container // Use to avoid warning
    }
}
