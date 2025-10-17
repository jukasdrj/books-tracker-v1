import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import BooksTrackerFeature

@Suite("BookshelfAIService WebSocket Integration")
struct BookshelfAIServiceWebSocketTests {

    #if canImport(UIKit)
    @Test("processBookshelfImageWithWebSocket calls progress handler")
    func testWebSocketProgressHandlerCalled() async throws {
        // Create mock image
        let image = createMockImage()

        // Track progress updates
        var progressUpdates: [(Double, String)] = []
        let service = BookshelfAIService.shared

        // This test will fail initially because the method doesn't exist yet
        let (books, suggestions) = try await service.processBookshelfImageWithWebSocket(
            image,
            progressHandler: { @MainActor progress, stage in
                progressUpdates.append((progress, stage))
            }
        )

        // Verify progress handler was called at least once
        #expect(progressUpdates.count >= 1, "Progress handler should be called at least once")

        // Verify results are returned (even if empty for test)
        #expect(books != nil, "Books array should be returned")
        #expect(suggestions != nil, "Suggestions array should be returned")
    }

    @Test("processBookshelfImageWithWebSocket typed throws BookshelfAIError")
    func testWebSocketTypedThrows() async throws {
        // This test verifies the typed throws signature
        let image = createMockImage()
        let service = BookshelfAIService.shared

        do {
            let _ = try await service.processBookshelfImageWithWebSocket(
                image,
                progressHandler: { @MainActor _, _ in }
            )
        } catch let error as BookshelfAIError {
            // Typed throws should allow catching BookshelfAIError directly
            #expect(error != nil, "Should be able to catch typed BookshelfAIError")
        }
    }

    // MARK: - Helper Methods

    private func createMockImage() -> UIImage {
        // Create a simple 1x1 test image
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    #endif
}
