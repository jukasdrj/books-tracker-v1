import SwiftUI

#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Camera State

enum CameraState: Equatable {
    case idle
    case permissionDenied
    case settingUp
    case ready
    case capturing
    case error(String)
}

// MARK: - Camera View Model

/// Main actor view model for camera UI state management.
/// Swift 6.1 compliant: UIImage creation happens here, not in actor.
@MainActor
@Observable
final class BookshelfCameraViewModel {
    // MARK: - Published State

    var cameraState: CameraState = .idle
    var capturedImage: UIImage?
    var showReviewSheet = false
    var flashMode: AVCaptureDevice.FlashMode = .auto
    var isFlashAvailable = false

    // MARK: - Private State

    private(set) var cameraManager: BookshelfCameraSessionManager?

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Request permission and configure camera session.
    func setupCamera() async {
        cameraState = .settingUp

        do {
            let manager = BookshelfCameraSessionManager()

            // Request permission (async/throws)
            try await manager.requestPermission()

            // Configure session (sync/throws) - must call from actor context
            try await Task { @BookshelfCameraActor in
                try manager.setupSession()
            }.value

            // Start session (async) - returns AVCaptureSession
            _ = await Task { @BookshelfCameraActor in
                await manager.startSession()
            }.value

            // Check flash availability (async property)
            isFlashAvailable = await Task { @BookshelfCameraActor in
                await manager.isFlashAvailable
            }.value

            // Update state
            self.cameraManager = manager
            self.cameraState = .ready

        } catch BookshelfCameraError.permissionDenied {
            cameraState = .permissionDenied
        } catch {
            cameraState = .error("Failed to setup camera: \(error.localizedDescription)")
        }
    }

    // MARK: - Capture

    /// Capture photo and create UIImage on MainActor (Swift 6.1 safe).
    func capturePhoto() async {
        guard let manager = cameraManager else {
            cameraState = .error("Camera not initialized")
            return
        }

        guard cameraState == .ready else { return }

        cameraState = .capturing

        do {
            // ✅ CRITICAL: Receive Sendable `Data` from actor
            let imageData = try await manager.capturePhoto(flashMode: flashMode)

            // ✅ CRITICAL: Create non-Sendable UIImage on MainActor
            // This ensures UIImage never crosses actor boundaries
            guard let image = UIImage(data: imageData) else {
                cameraState = .error("Failed to create image from data")
                return
            }

            // Success - show review
            self.capturedImage = image
            self.showReviewSheet = true
            self.cameraState = .ready

        } catch {
            cameraState = .error("Failed to capture photo: \(error.localizedDescription)")

            // Return to ready state after brief delay
            try? await Task.sleep(for: .seconds(2))
            if cameraState == .error("Failed to capture photo: \(error.localizedDescription)") {
                cameraState = .ready
            }
        }
    }

    // MARK: - Flash Control

    /// Toggle flash mode: auto → on → off → auto
    func toggleFlash() {
        switch flashMode {
        case .auto:
            flashMode = .on
        case .on:
            flashMode = .off
        case .off:
            flashMode = .auto
        @unknown default:
            flashMode = .auto
        }
    }

    // MARK: - Cleanup

    /// Stop camera session and clean up resources.
    func cleanup() async {
        guard let manager = cameraManager else { return }
        await manager.cleanup()
        cameraManager = nil
        cameraState = .idle
    }

    // MARK: - Error Handling

    /// Retry camera setup after error.
    func retrySetup() async {
        cameraState = .idle
        await setupCamera()
    }

    /// Open iOS Settings app to camera permissions.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#endif  // canImport(AVFoundation)
