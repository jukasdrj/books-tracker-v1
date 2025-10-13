import SwiftUI
@preconcurrency import AVFoundation

// MARK: - Camera Preview (UIViewRepresentable)

/// SwiftUI wrapper for AVCaptureVideoPreviewLayer.
/// Swift 6.1 compliant: Uses dependency injection pattern.
struct BookshelfCameraPreview: UIViewRepresentable {
    let cameraManager: BookshelfCameraSessionManager

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Configure session on first update
        Task { @MainActor in
            await uiView.updateSession(cameraManager: cameraManager)
        }
    }

    // MARK: - Preview View

    final class PreviewView: UIView {
        private var previewLayerInstance: AVCaptureVideoPreviewLayer?

        /// Configure session from camera manager (async pattern like ModernCameraPreview).
        /// ✅ CORRECT PATTERN: Call async startSession() from actor context, configure UI on MainActor
        @MainActor
        func updateSession(cameraManager: BookshelfCameraSessionManager) async {
            guard previewLayerInstance == nil else { return }

            // Get session from actor context
            let session = await Task { @BookshelfCameraActor in
                await cameraManager.startSession()
            }.value

            // Configure preview layer on MainActor
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds

            layer.addSublayer(previewLayer)
            self.previewLayerInstance = previewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayerInstance?.frame = bounds
        }
    }
}
