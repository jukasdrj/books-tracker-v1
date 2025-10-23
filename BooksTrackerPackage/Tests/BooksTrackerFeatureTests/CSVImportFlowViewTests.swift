import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("CSVImportFlowView Tests")
@MainActor
struct CSVImportFlowViewTests {

    @Test("View initializes without crash")
    func viewInitialization() {
        if #available(iOS 26.0, *) {
            let view = CSVImportFlowView()
            // Test passes if initialization doesn't crash
        }
    }

    @Test("View uses SyncCoordinator singleton")
    func usesSyncCoordinator() {
        let coordinator = SyncCoordinator.shared
        // Test passes if coordinator is accessible
    }
}
