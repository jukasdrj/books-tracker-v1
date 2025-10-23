import Testing
import UIKit
@testable import BooksTrackerFeature

@Suite("UIImage Resize Tests")
struct UIImageResizeTests {
    @Test("Does not upscale smaller images")
    func testNoUpscaling() {
        let smallImage = createTestImage(size: CGSize(width: 100, height: 100))
        let resized = smallImage.resizeForAI(maxDimension: 1000)

        #expect(resized.size.width == 100)
        #expect(resized.size.height == 100)
    }

    @Test("Downscales larger images while preserving aspect ratio")
    func testDownscaling() {
        let largeImage = createTestImage(size: CGSize(width: 4000, height: 3000))
        let resized = largeImage.resizeForAI(maxDimension: 1536)

        let maxDim = max(resized.size.width, resized.size.height)
        #expect(maxDim <= 1536)

        // Aspect ratio preserved
        let originalRatio = 4000.0 / 3000.0
        let resizedRatio = resized.size.width / resized.size.height
        #expect(abs(originalRatio - resizedRatio) < 0.01)
    }

    private func createTestImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
