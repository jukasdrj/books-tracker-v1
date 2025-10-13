@preconcurrency import AVFoundation
import UIKit

// MARK: - Camera Errors

enum BookshelfCameraError: Error, Sendable {
    case permissionDenied
    case deviceUnavailable
    case sessionConfigurationFailed
    case captureOutputNotConfigured
    case photoDataUnavailable
}

// MARK: - Bookshelf Camera Actor

/// Custom global actor for bookshelf camera operations.
/// Provides Swift 6.1 compliant isolation for AVFoundation interactions.
@globalActor
actor BookshelfCameraActor {
    static let shared = BookshelfCameraActor()
}

// MARK: - Camera Session Manager

/// Manages AVCaptureSession lifecycle with Swift 6.1 strict concurrency compliance.
/// All AVFoundation interactions are isolated to BookshelfCameraActor.
@BookshelfCameraActor
final class BookshelfCameraSessionManager {
    // MARK: - Private State

    /// AVCaptureSession is thread-safe for read-only access after configuration (Apple's guarantee).
    /// Using nonisolated(unsafe) allows cross-actor access for preview layer configuration.
    nonisolated(unsafe) private let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput?
    private var videoDevice: AVCaptureDevice?

    // MARK: - Initialization

    /// Nonisolated initializer allows creation from any context.
    /// All actual session setup happens in setupSession().
    nonisolated init() {}

    // MARK: - Session Setup

    /// Request camera permission from the user.
    func requestPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw BookshelfCameraError.permissionDenied
            }
        case .denied, .restricted:
            throw BookshelfCameraError.permissionDenied
        @unknown default:
            throw BookshelfCameraError.permissionDenied
        }
    }

    /// Configure the capture session with high-quality photo output.
    func setupSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        // High-quality preset for bookshelf text recognition
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        }

        // Get back camera (wide angle)
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw BookshelfCameraError.deviceUnavailable
        }
        self.videoDevice = device

        // Configure device for optimal bookshelf capture
        try device.lockForConfiguration()

        // Continuous autofocus for varying shelf depths
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        // Auto exposure for varying lighting conditions
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        // Enable auto white balance
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        device.unlockForConfiguration()

        // Add video input
        let videoInput = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(videoInput) else {
            throw BookshelfCameraError.sessionConfigurationFailed
        }
        captureSession.addInput(videoInput)

        // Add photo output
        let output = AVCapturePhotoOutput()

        // Add output to session FIRST (required before setting maxPhotoDimensions)
        guard captureSession.canAddOutput(output) else {
            throw BookshelfCameraError.sessionConfigurationFailed
        }
        captureSession.addOutput(output)

        // NOW set maximum photo dimensions (must be AFTER adding to session with connected device)
        if #available(iOS 16.0, *) {
            output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first ?? CMVideoDimensions(width: 4032, height: 3024)
        }

        // Disable Live Photo (we only need still images)
        if output.isLivePhotoCaptureSupported {
            output.isLivePhotoCaptureEnabled = false
        }

        self.photoOutput = output
    }

    /// Start the capture session on a background queue and return it for preview layer configuration.
    /// ✅ CORRECT PATTERN: Return session from async method (like CameraManager.startSession)
    func startSession() async -> AVCaptureSession {
        guard !captureSession.isRunning else { return captureSession }

        // Start on background queue to avoid blocking UI
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
                captureSession.startRunning()
                continuation.resume()
            }
        }

        return captureSession
    }

    /// Stop the capture session.
    func stopSession() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
    }

    // MARK: - Photo Capture

    /// Capture a photo and return raw image data (Sendable).
    /// The caller is responsible for creating UIImage on MainActor.
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode) async throws -> Data {
        guard let photoOutput = photoOutput else {
            throw BookshelfCameraError.captureOutputNotConfigured
        }

        // Create photo settings
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode

        // Set maximum photo dimensions (replaces deprecated isHighResolutionPhotoEnabled)
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        // Use continuation-based delegate pattern
        let delegate = PhotoCaptureDelegate()
        return try await delegate.capturePhoto(using: photoOutput, settings: settings)
    }

    // MARK: - Flash Control

    /// Check if flash is available on the device.
    var isFlashAvailable: Bool {
        get async {
            videoDevice?.hasFlash ?? false
        }
    }

    // MARK: - Cleanup

    /// Clean up session resources.
    func cleanup() {
        stopSession()

        // Remove all inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        photoOutput = nil
        videoDevice = nil
    }
}

// MARK: - Photo Capture Delegate

/// Actor-isolated delegate for AVCapturePhoto callbacks.
/// Ensures thread-safe handling of photo capture completion.
@BookshelfCameraActor
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data, Error>?

    func capturePhoto(using output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Callback arrives on arbitrary AVFoundation thread.
    /// ✅ SAFEST PATTERN: Extract Sendable Data BEFORE crossing actor boundary
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Extract Sendable Data immediately (on AVFoundation thread)
        let result: Result<Data, Error>

        if let error = error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(BookshelfCameraError.photoDataUnavailable)
        }

        // Now safely hop to actor with Sendable Data
        Task {
            await resumeContinuation(with: result)
        }
    }

    /// Resume continuation on actor context (thread-safe).
    private func resumeContinuation(with result: Result<Data, Error>) {
        switch result {
        case .success(let data):
            continuation?.resume(returning: data)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
