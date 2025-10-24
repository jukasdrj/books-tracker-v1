import Testing
import SwiftUI
@testable import BooksTrackerFeature

@Suite("Batch Capture UI")
@MainActor
struct BatchCaptureUITests {

    @Test("Shows submit and take more buttons after capture")
    func postCaptureButtons() async {
        let model = BatchCaptureModel()
        let image = createTestImage()

        model.addPhoto(image)

        #expect(model.capturedPhotos.count == 1)
        #expect(model.showingPostCaptureOptions == true)
    }

    @Test("Returns to camera when take more tapped")
    func takeMoreFlow() async {
        let model = BatchCaptureModel()

        model.addPhoto(createTestImage())
        model.handleTakeMore()

        #expect(model.showingPostCaptureOptions == false)
        #expect(model.capturedPhotos.count == 1) // Photo retained
    }

    @Test("Enforces 5 photo limit")
    func photoLimit() async {
        let model = BatchCaptureModel()

        // Add 5 photos
        for _ in 0..<5 {
            model.addPhoto(createTestImage())
        }

        #expect(model.capturedPhotos.count == 5)

        // Attempt to add 6th
        model.addPhoto(createTestImage())

        #expect(model.capturedPhotos.count == 5) // Still 5
    }

    @Test("Submit initiates batch scan")
    func submitBatch() async {
        let model = BatchCaptureModel()

        model.addPhoto(createTestImage())
        model.addPhoto(createTestImage())

        await model.submitBatch()

        #expect(model.isSubmitting == true)
        #expect(model.capturedPhotos.count == 2)
    }

    @Test("Can delete individual photos")
    func deletePhoto() async {
        let model = BatchCaptureModel()

        model.addPhoto(createTestImage())
        let photo2 = model.addPhoto(createTestImage())
        model.addPhoto(createTestImage())

        model.deletePhoto(photo2)

        #expect(model.capturedPhotos.count == 2)
    }

    @Test("canAddMore reflects photo limit")
    func canAddMoreProperty() async {
        let model = BatchCaptureModel()

        #expect(model.canAddMore == true)

        // Add 4 photos
        for _ in 0..<4 {
            model.addPhoto(createTestImage())
        }

        #expect(model.canAddMore == true)

        // Add 5th photo
        model.addPhoto(createTestImage())

        #expect(model.canAddMore == false)
    }
}

// MARK: - Helper

/// Creates a test image (system SF Symbol)
@MainActor
func createTestImage() -> UIImage {
    UIImage(systemName: "book.fill")!
}
