import Testing
@testable import BooksTrackerFeature

@Test("ProgressStrategy has correct cases")
func testProgressStrategyCases() {
    let webSocket = ProgressStrategy.webSocket
    let polling = ProgressStrategy.polling

    #expect(webSocket != polling)
}

@Test("ProgressStrategy is Sendable")
func testProgressStrategyIsSendable() {
    func acceptsSendable<T: Sendable>(_ value: T) {}
    acceptsSendable(ProgressStrategy.webSocket)
}

@Test("ProgressStrategy has user-friendly descriptions")
func testProgressStrategyDescriptions() {
    #expect(ProgressStrategy.webSocket.description == "WebSocket (real-time)")
    #expect(ProgressStrategy.polling.description == "HTTP Polling (fallback)")
}
