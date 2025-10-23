import Testing
import UIKit
@testable import BooksTrackerFeature

// Note: These tests require a running backend. They will be skipped in CI until mock infrastructure is added.

@Test("processViaWebSocket returns detected books on success", .disabled("Requires live backend"))
func testProcessViaWebSocketSuccess() async throws {
    let mockImage = UIImage(systemName: "book")!
    let jobId = UUID().uuidString

    let service = BookshelfAIService.shared

    // Mock successful WebSocket flow
    let result = try await service.processViaWebSocket(
        image: mockImage,
        jobId: jobId,
        provider: .gemini,
        progressHandler: { progress, status in
            print("Progress: \(Int(progress * 100))% - \(status)")
        }
    )

    #expect(result.0.count > 0)  // Has detected books
    #expect(result.1.count >= 0)  // Has suggestions (or empty)
}

@Test("processViaWebSocket throws on WebSocket connection failure", .disabled("Requires live backend"))
func testProcessViaWebSocketConnectionFailure() async {
    let mockImage = UIImage(systemName: "book")!
    let invalidJobId = "invalid-job-id"

    let service = BookshelfAIService.shared

    await #expect(throws: BookshelfAIError.self) {
        try await service.processViaWebSocket(
            image: mockImage,
            jobId: invalidJobId,
            provider: .gemini,
            progressHandler: { _, _ in }
        )
    }
}
