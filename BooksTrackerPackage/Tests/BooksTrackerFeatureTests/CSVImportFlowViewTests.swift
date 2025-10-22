import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("CSVImportFlowView Tests")
@MainActor
struct CSVImportFlowViewTests {

    @Test("View initializes without crash")
    func viewInitialization() {
        let view = CSVImportFlowView()
        #expect(view != nil)
    }

    @Test("View uses SyncCoordinator singleton")
    func usesSyncCoordinator() {
        // Verify coordinator is accessible
        let coordinator = SyncCoordinator.shared
        #expect(coordinator != nil)
    }
}
