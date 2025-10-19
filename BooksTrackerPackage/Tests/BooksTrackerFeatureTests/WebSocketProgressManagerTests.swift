import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("WebSocketProgressManager Tests")
struct WebSocketProgressManagerTests {

    @Test("Should initialize with disconnected state")
    @MainActor
    func testInitialState() async throws {
        let manager = WebSocketProgressManager()

        #expect(!manager.isConnected)
        #expect(manager.lastError == nil)
    }

    @Test("Should handle missing URL gracefully")
    @MainActor
    func testInvalidURL() async throws {
        let manager = WebSocketProgressManager()

        // Empty jobId should fail gracefully
        await manager.connect(jobId: "", progressHandler: { _ in })

        #expect(!manager.isConnected)
        #expect(manager.lastError != nil)
    }

    @Test("Should disconnect cleanly")
    @MainActor
    func testDisconnect() async throws {
        let manager = WebSocketProgressManager()

        // Connect then disconnect
        await manager.connect(jobId: "test-job", progressHandler: { _ in })
        await manager.disconnect()

        #expect(!manager.isConnected)
    }
}
