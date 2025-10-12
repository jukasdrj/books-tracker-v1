import SwiftUI
import AVFoundation

@MainActor
struct BookshelfCameraView: View {
    private let cameraManager: CameraManager
    var onImageCapture: (Data) -> Void

    init(cameraManager: CameraManager, onImageCapture: @escaping (Data) -> Void) {
        self.cameraManager = cameraManager
        self.onImageCapture = onImageCapture
    }

    var body: some View {
        ZStack {
            CameraPreviewLayer(cameraManager: cameraManager)
                .ignoresSafeArea()

            VStack {
                Spacer()
                Button(action: takePhoto) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear(perform: startSession)
        .onDisappear(perform: stopSession)
    }

    private func startSession() {
        Task {
            do {
                _ = try await cameraManager.startSession()
            } catch {
                // Handle error
                print("Error starting camera session: \(error)")
            }
        }
    }

    private func stopSession() {
        Task {
            await cameraManager.stopSession()
        }
    }

    private func takePhoto() {
        Task {
            do {
                let imageData = try await cameraManager.takePhoto()
                onImageCapture(imageData)
            } catch {
                // Handle error
                print("Error taking photo: \(error)")
            }
        }
    }
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        Task {
            await uiView.updateSession(cameraManager: cameraManager)
        }
    }
}

private final class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    @MainActor
    func updateSession(cameraManager: CameraManager) async {
        guard previewLayer == nil else { return }

        do {
            let session = try await cameraManager.startSession()

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = bounds

            layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
        } catch {
            // Handle error through parent view
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
