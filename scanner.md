This package provides a comprehensive, modern barcode scanning solution utilizing Swift concurrency (`async/await`), the `AVFoundation` framework for camera control, and the `Vision` framework for robust barcode detection.

To pull the current barcode scanning implementation into another app, you need four core Swift files and one essential supporting utility file, **`ISBNValidator.swift`**, as the entire system is designed to emit validated ISBNs.

Below is the complete code for the five necessary files.

### 1\. Essential Dependency: `ISBNValidator.swift`

This utility is critical because your `BarcodeDetectionService` and `ModernBarcodeScannerView` rely on its `ISBN` struct and validation logic.

```swift
import Foundation

public struct ISBNValidator {

    public struct ISBN: Equatable, Hashable, Sendable {
        public let normalizedValue: String
        public let displayValue: String
        public let type: ISBNType

        public enum ISBNType: String, Sendable {
            case isbn10 = "ISBN-10"
            case isbn13 = "ISBN-13"
        }
    }

    public enum ValidationResult: Equatable {
        case valid(ISBN)
        case invalid(String)
    }

    /// Cleans and validates an ISBN-10 or ISBN-13 string.
    public static func validate(_ rawValue: String) -> ValidationResult {
        // 1. Clean the input
        let cleanValue = rawValue.filter { $0.isNumber || $0.uppercased() == "X" }

        switch cleanValue.count {
        case 10:
            return validateISBN10(cleanValue)
        case 13:
            return validateISBN13(cleanValue)
        default:
            return .invalid("Invalid length: \(cleanValue.count)")
        }
    }

    private static func validateISBN10(_ isbn: String) -> ValidationResult {
        guard isbn.count == 10 else { return .invalid("Length not 10") }

        let chars = Array(isbn.uppercased())
        var sum = 0

        for i in 0..<9 {
            guard let digit = Int(String(chars[i])) else { return .invalid("Invalid character in ISBN-10") }
            sum += (i + 1) * digit
        }

        let lastChar = chars[9]
        let lastDigit: Int
        if lastChar == "X" {
            lastDigit = 10
        } else if let digit = Int(String(lastChar)) {
            lastDigit = digit
        } else {
            return .invalid("Invalid check digit in ISBN-10")
        }

        sum += 10 * lastDigit

        if sum % 11 == 0 {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN10(isbn),
                type: .isbn10
            ))
        } else {
            return .invalid("Checksum failed for ISBN-10")
        }
    }

    private static func validateISBN13(_ isbn: String) -> ValidationResult {
        guard isbn.count == 13 else { return .invalid("Length not 13") }
        guard isbn.prefix(3) == "978" || isbn.prefix(3) == "979" else { return .invalid("Not a recognized prefix") }

        let digits = isbn.compactMap { Int(String($0)) }
        guard digits.count == 13 else { return .invalid("Invalid character in ISBN-13") }

        var sum = 0
        for i in 0..<12 {
            sum += digits[i] * (i % 2 == 0 ? 1 : 3)
        }

        let checksum = (10 - (sum % 10)) % 10

        if checksum == digits[12] {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN13(isbn),
                type: .isbn13
            ))
        } else {
            return .invalid("Checksum failed for ISBN-13")
        }
    }

    private static func formatISBN10(_ isbn: String) -> String {
        return "\(isbn.prefix(1))-\(isbn.prefix(5).suffix(4))-\(isbn.prefix(9).suffix(4))-\(isbn.suffix(1))"
    }

    private static func formatISBN13(_ isbn: String) -> String {
        return "\(isbn.prefix(3))-\(isbn.prefix(4).suffix(1))-\(isbn.prefix(9).suffix(5))-\(isbn.prefix(12).suffix(3))-\(isbn.suffix(1))"
    }
}
```

### 2\. `books/Services/CameraManager.swift`

This file contains the actor (`@CameraSessionActor`), error definitions, and the actor-isolated `CameraManager` class for thread-safe session control.

```swift
@preconcurrency import AVFoundation
import Vision
import SwiftUI
import UIKit

/// Actor-based camera session manager for barcode scanning
/// Provides Swift 6 compliant concurrency and session lifecycle management
@globalActor
actor CameraSessionActor {
    static let shared = CameraSessionActor()
}

/// Represents different types of camera-related errors
enum CameraError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case sessionConfigurationFailed
    case torchUnavailable
    case focusUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission is required to scan barcodes"
        case .deviceUnavailable:
            return "Camera device is not available"
        case .sessionConfigurationFailed:
            return "Failed to configure camera session"
        case .torchUnavailable:
            return "Torch is not available on this device"
        case .focusUnavailable:
            return "Auto-focus is not available on this device"
        }
    }
}

/// Session state for camera operations
enum CameraSessionState: Equatable {
    case idle
    case configuring
    case running
    case stopped
    case error(CameraError)

    static func == (lhs: CameraSessionState, rhs: CameraSessionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.configuring, .configuring), (.running, .running), (.stopped, .stopped):
            return true
        case (.error, .error):
            return true // Consider all errors equal for state comparison
        default:
            return false
        }
    }
}

/// Camera session manager with Swift 6 concurrency compliance and ObservableObject support
@CameraSessionActor
final class CameraManager: ObservableObject {

    // MARK: - Published Properties
    @MainActor @Published var isTorchOn: Bool = false
    @MainActor @Published var isSessionRunning: Bool = false
    @MainActor @Published var lastError: CameraError?

    // MARK: - Private Properties
    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var metadataOutput: AVCaptureMetadataOutput?

    private var sessionState: CameraSessionState = .idle
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "camera.vision.queue", qos: .userInitiated)

    // MARK: - Public Interface

    /// Current session state
    var state: CameraSessionState {
        sessionState
    }

    /// Check if the device has torch capability
    var hasTorch: Bool {
        videoDevice?.hasTorch ?? false
    }

    /// Check if the device supports auto-focus
    var hasAutoFocus: Bool {
        videoDevice?.isFocusModeSupported(.autoFocus) ?? false
    }

    // MARK: - Session Management

    /// Configure and start the camera session
    func startSession() async throws -> AVCaptureSession {
        guard sessionState != .running else {
            guard let session = captureSession else {
                throw CameraError.sessionConfigurationFailed
            }
            return session
        }

        sessionState = .configuring

        do {
            let session = try await configureSession()
            sessionState = .running

            // Start session on background queue
            await withCheckedContinuation { continuation in
                sessionQueue.async {
                    session.startRunning()
                    continuation.resume()
                }
            }

            // Update published state on main actor
            await MainActor.run {
                isSessionRunning = true
                lastError = nil
            }

            return session
        } catch {
            sessionState = .error(error as? CameraError ?? .sessionConfigurationFailed)

            await MainActor.run {
                isSessionRunning = false
                lastError = error as? CameraError ?? .sessionConfigurationFailed
            }

            throw error
        }
    }

    /// Stop the camera session and clean up resources
    func stopSession() async {
        guard let session = captureSession else { return }

        sessionState = .stopped

        // Turn off torch before stopping
        if let device = videoDevice, device.hasTorch {
            try? await setTorchMode(.off)
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }

        // Clean up resources
        captureSession = nil
        videoDevice = nil
        videoInput = nil
        videoOutput = nil
        metadataOutput = nil

        sessionState = .idle

        // Update published state on main actor
        await MainActor.run {
            isSessionRunning = false
            isTorchOn = false
        }
    }

    // MARK: - Device Controls

    /// Set torch mode (flashlight)
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode) async throws {
        guard let device = videoDevice else {
            throw CameraError.deviceUnavailable
        }

        guard device.hasTorch else {
            throw CameraError.torchUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = mode
                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Update published state on main actor
        await MainActor.run {
            isTorchOn = (mode == .on)
            lastError = nil
        }
    }

    /// Toggle torch on/off
    func toggleTorch() async throws {
        let currentTorchState = await isTorchOn
        let newMode: AVCaptureDevice.TorchMode = currentTorchState ? .off : .on
        try await setTorchMode(newMode)
    }

    /// Focus at the center of the frame
    func focusAtCenter() async throws {
        guard let device = videoDevice else {
            throw CameraError.deviceUnavailable
        }

        guard device.isFocusModeSupported(.autoFocus) else {
            throw CameraError.focusUnavailable
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try device.lockForConfiguration()

                    device.focusMode = .autoFocus
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)

                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }

                    device.unlockForConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Update published state on main actor
        await MainActor.run {
            lastError = nil
        }
    }

    /// Set region of interest for optimized barcode detection
    /// - Parameter rect: Normalized rectangle (0.0-1.0) for region of interest
    func setRegionOfInterest(_ rect: CGRect) async {
        guard let metadataOutput = metadataOutput else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                metadataOutput.rectOfInterest = rect
                continuation.resume()
            }
        }
    }

    /// Provides read-only access to the capture session for preview layer
    var session: AVCaptureSession? {
        captureSession
    }

    // MARK: - Private Methods

    private func configureSession() async throws -> AVCaptureSession {
        // Check camera permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            throw CameraError.permissionDenied
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Configure video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw CameraError.deviceUnavailable
        }

        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            session.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }

        guard session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw CameraError.sessionConfigurationFailed
        }

        session.addInput(videoInput)

        // Store references
        self.videoDevice = videoDevice
        self.videoInput = videoInput
        self.captureSession = session

        // Configure device settings
        try await configureVideoDevice(videoDevice)

        // Add outputs
        try configureOutputs(session)

        session.commitConfiguration()
        return session
    }

    private func configureVideoDevice(_ device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try device.lockForConfiguration()

                // Enable continuous auto focus
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                // Enable continuous auto exposure
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                // Optimize for barcode scanning (disable HDR for speed)
                if device.activeFormat.isVideoHDRSupported {
                    device.automaticallyAdjustsVideoHDREnabled = false
                    device.isVideoHDREnabled = false
                }

                device.unlockForConfiguration()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func configureOutputs(_ session: AVCaptureSession) throws {
        // Video output for Vision framework
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        guard session.canAddOutput(videoOutput) else {
            throw CameraError.sessionConfigurationFailed
        }

        session.addOutput(videoOutput)
        self.videoOutput = videoOutput

        // Metadata output as fallback
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.metadataObjectTypes = [
            AVMetadataObject.ObjectType.ean13,
            AVMetadataObject.ObjectType.ean8,
            AVMetadataObject.ObjectType.upce,
            AVMetadataObject.ObjectType.code128,
            AVMetadataObject.ObjectType.code39,
            AVMetadataObject.ObjectType.code93,
            AVMetadataObject.ObjectType.interleaved2of5
        ]

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            self.metadataOutput = metadataOutput
        }
    }

    // MARK: - Lifecycle Management

    /// Initialize lifecycle observers
    init() {
        setupAppLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // Note: Cannot access actor-isolated properties in deinit
        // Cleanup will be handled by app lifecycle observers and explicit stopSession() calls
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @CameraSessionActor in
                await self?.handleAppWillEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @CameraSessionActor in
                await self?.handleAppDidEnterBackground()
            }
        }
    }

    private func handleAppWillEnterForeground() async {
        guard let session = captureSession, sessionState == .stopped else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }

        sessionState = .running
        await MainActor.run {
            isSessionRunning = true
        }
    }

    private func handleAppDidEnterBackground() async {
        guard let session = captureSession, sessionState == .running else { return }

        // Turn off torch when going to background
        if let device = videoDevice, device.hasTorch, await isTorchOn {
            try? await setTorchMode(.off)
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }

        sessionState = .stopped
        await MainActor.run {
            isSessionRunning = false
        }
    }
}

// MARK: - Delegate Support

extension CameraManager {
    /// Sets delegates for video and metadata output
    /// - Parameters:
    ///   - videoDelegate: Delegate for video sample buffer output
    ///   - metadataDelegate: Delegate for metadata object detection
    ///   - delegateQueue: Queue for delegate callbacks
    func setDelegates(
        videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?,
        metadataDelegate: AVCaptureMetadataOutputObjectsDelegate?,
        delegateQueue: DispatchQueue
    ) async {
        let currentVideoOutput = videoOutput
        let currentMetadataOutput = metadataOutput

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                currentVideoOutput?.setSampleBufferDelegate(videoDelegate, queue: delegateQueue)
                currentMetadataOutput?.setMetadataObjectsDelegate(metadataDelegate, queue: delegateQueue)
                continuation.resume()
            }
        }
    }
}

// MARK: - Permission Management

extension CameraManager {

    /// Request camera permission asynchronously
    static func requestCameraPermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Check current camera permission status
    static var cameraPermissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }
}
```

### 3\. `books/Services/BarcodeDetectionService.swift`

This service manages the detection process using `AsyncStream` and handles the throttling and filtering logic.

```swift
import AVFoundation
import Vision
import Combine

/// Modern AsyncStream-based barcode detection service
/// Provides real-time barcode scanning with intelligent filtering and validation
final class BarcodeDetectionService: @unchecked Sendable {

    // MARK: - Detection Result Types

    struct BarcodeDetection: Sendable {
        let value: String
        let confidence: Float
        let timestamp: Date
        let detectionMethod: DetectionMethod
        let isbn: ISBNValidator.ISBN?

        enum DetectionMethod: Sendable {
            case vision
            case avFoundation
        }
    }

    enum DetectionError: LocalizedError, Sendable {
        case sessionNotRunning
        case noValidBarcodes
        case processingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .sessionNotRunning:
                return "Camera session is not running"
            case .noValidBarcodes:
                return "No valid barcodes found in frame"
            case .processingFailed(let error):
                return "Barcode processing failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Configuration

    struct Configuration {
        let enableVisionDetection: Bool
        let enableAVFoundationFallback: Bool
        let isbnValidationEnabled: Bool
        let duplicateThrottleInterval: TimeInterval
        let regionOfInterest: CGRect?

        static let `default` = Configuration(
            enableVisionDetection: true,
            enableAVFoundationFallback: true,
            isbnValidationEnabled: true,
            duplicateThrottleInterval: 2.0,
            regionOfInterest: nil
        )
    }

    // MARK: - Private Properties

    private let configuration: Configuration
    private let visionQueue = DispatchQueue(label: "barcode.vision.queue", qos: .userInitiated)

    // Throttling state
    private var lastDetectionTime: Date = .distantPast
    private var lastDetectedValue: String = ""

    // Stream management
    private var detectionContinuation: AsyncStream<BarcodeDetection>.Continuation?

    // MARK: - Initialization

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public Interface

    /// Start barcode detection stream
    /// Returns an AsyncStream of barcode detections
    func startDetection(cameraManager: CameraManager) -> AsyncStream<BarcodeDetection> {
        AsyncStream<BarcodeDetection> { continuation in
            self.detectionContinuation = continuation

            Task {
                await setupDetection(cameraManager: cameraManager, continuation: continuation)
            }

            continuation.onTermination = { _ in
                Task {
                    await self.stopDetection(cameraManager: cameraManager)
                }
            }
        }
    }

    /// Stop barcode detection
    func stopDetection() async {
        detectionContinuation?.finish()
        detectionContinuation = nil
    }

    // MARK: - Private Implementation

    @CameraSessionActor
    private func setupDetection(
        cameraManager: CameraManager,
        continuation: AsyncStream<BarcodeDetection>.Continuation
    ) async {
        do {
            let session = try await cameraManager.startSession()

            // Setup Vision detection if enabled
            if configuration.enableVisionDetection {
                await setupVisionDetection(session: session)
            }

            // Setup AVFoundation fallback if enabled
            if configuration.enableAVFoundationFallback {
                await setupAVFoundationDetection(session: session)
            }

        } catch {
            let detectionError = DetectionError.processingFailed(error)
            continuation.finish()
        }
    }

    @CameraSessionActor
    private func stopDetection(cameraManager: CameraManager) async {
        await cameraManager.stopSession()
    }

    @CameraSessionActor
    private func setupVisionDetection(session: AVCaptureSession) async {
        // Find video output
        guard let videoOutput = session.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first else {
            return
        }

        // Setup delegate for Vision processing
        let delegate = VisionProcessingDelegate(
            service: self,
            configuration: configuration
        )

        videoOutput.setSampleBufferDelegate(delegate, queue: visionQueue)
    }

    @CameraSessionActor
    private func setupAVFoundationDetection(session: AVCaptureSession) async {
        // Find metadata output
        guard let metadataOutput = session.outputs.compactMap({ $0 as? AVCaptureMetadataOutput }).first else {
            return
        }

        // Setup delegate for AVFoundation processing
        let delegate = MetadataProcessingDelegate(
            service: self,
            configuration: configuration
        )

        metadataOutput.setMetadataObjectsDelegate(delegate, queue: visionQueue)
    }

    internal func processDetectedBarcode(
        value: String,
        confidence: Float,
        method: BarcodeDetection.DetectionMethod
    ) {
        // Apply throttling to prevent duplicate detections
        let now = Date()
        if value == lastDetectedValue &&
           now.timeIntervalSince(lastDetectionTime) < configuration.duplicateThrottleInterval {
            return
        }

        lastDetectionTime = now
        lastDetectedValue = value

        // Validate as ISBN if enabled
        var isbn: ISBNValidator.ISBN?
        if configuration.isbnValidationEnabled {
            switch ISBNValidator.validate(value) {
            case .valid(let validISBN):
                isbn = validISBN
            case .invalid:
                // Not a valid ISBN, skip detection
                return
            }
        }

        // Create detection result
        let detection = BarcodeDetection(
            value: value,
            confidence: confidence,
            timestamp: now,
            detectionMethod: method,
            isbn: isbn
        )

        // Send through stream
        detectionContinuation?.yield(detection)
    }
}

// MARK: - Vision Processing Delegate

private final class VisionProcessingDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var service: BarcodeDetectionService?
    private let configuration: BarcodeDetectionService.Configuration

    init(service: BarcodeDetectionService, configuration: BarcodeDetectionService.Configuration) {
        self.service = service
        self.configuration = configuration
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let service = service else {
            return
        }

        // Create Vision request
        let request = VNDetectBarcodesRequest { [weak service] request, error in
            guard let service = service,
                  error == nil,
                  let results = request.results as? [VNBarcodeObservation] else {
                return
            }

            // Process each detected barcode
            for observation in results {
                guard let payloadString = observation.payloadStringValue else { continue }

                // Filter by region of interest if configured
                if let roi = self.configuration.regionOfInterest {
                    let boundingBox = observation.boundingBox
                    if !roi.intersects(boundingBox) {
                        continue
                    }
                }

                service.processDetectedBarcode(
                    value: payloadString,
                    confidence: observation.confidence,
                    method: .vision
                )
            }
        }

        // Configure barcode types
        request.symbologies = [
            VNBarcodeSymbology.ean13,
            VNBarcodeSymbology.ean8,
            VNBarcodeSymbology.upce,
            VNBarcodeSymbology.code128,
            VNBarcodeSymbology.code39,
            VNBarcodeSymbology.code93,
            VNBarcodeSymbology.i2of5
        ]

        // Perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Silently handle Vision processing errors
        }
    }
}

// MARK: - Metadata Processing Delegate

private final class MetadataProcessingDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private weak var service: BarcodeDetectionService?
    private let configuration: BarcodeDetectionService.Configuration

    init(service: BarcodeDetectionService, configuration: BarcodeDetectionService.Configuration) {
        self.service = service
        self.configuration = configuration
        super.init()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let service = service else { return }

        for metadataObject in metadataObjects {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else {
                continue
            }

            // Filter by region of interest if configured
            if let roi = configuration.regionOfInterest {
                if !roi.intersects(readableObject.bounds) {
                    continue
                }
            }

            service.processDetectedBarcode(
                value: stringValue,
                confidence: 1.0, // AVFoundation doesn't provide confidence
                method: .avFoundation
            )
        }
    }
}

// MARK: - Convenience Extensions

extension BarcodeDetectionService {
    /// Create a stream that only emits valid ISBN detections
    func isbnDetectionStream(cameraManager: CameraManager) -> AsyncStream<ISBNValidator.ISBN> {
        AsyncStream { continuation in
            Task {
                for await detection in startDetection(cameraManager: cameraManager) {
                    if let isbn = detection.isbn {
                        continuation.yield(isbn)
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

### 4\. `books/Views/Components/ModernCameraPreview.swift`

This reusable SwiftUI view manages the visual representation of the camera session, including the live feed, focus indicators, and the specialized ISBN scanning overlay.

```swift
import SwiftUI
@preconcurrency import AVFoundation
import UIKit

/// Modern SwiftUI camera preview component with proper error handling
/// Designed for Swift 6 concurrency and clean separation of concerns
struct ModernCameraPreview: View {
    // MARK: - Configuration

    struct Configuration {
        let regionOfInterest: CGRect?
        let showFocusIndicator: Bool
        let showScanningOverlay: Bool
        let enableTapToFocus: Bool
        let aspectRatio: CGFloat?
        let overlayStyle: ScanningOverlayStyle

        static let `default` = Configuration(
            regionOfInterest: nil,
            showFocusIndicator: true,
            showScanningOverlay: true,
            enableTapToFocus: true,
            aspectRatio: nil,
            overlayStyle: .standard
        )

        static let isbnScanning = Configuration(
            regionOfInterest: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4),
            showFocusIndicator: true,
            showScanningOverlay: true,
            enableTapToFocus: true,
            aspectRatio: 4/3,
            overlayStyle: .isbn
        )
    }

    enum ScanningOverlayStyle {
        case standard
        case isbn
        case minimal
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let onError: (CameraError) -> Void

    @StateObject private var cameraManager: CameraManager
    @State private var detectionService: BarcodeDetectionService?
    @State private var sessionState: CameraSessionState = .idle
    @State private var focusPoint: CGPoint?
    @State private var showingFocusIndicator = false

    // MARK: - Initialization

    init(
        cameraManager: CameraManager? = nil,
        configuration: Configuration = .default,
        detectionConfiguration: BarcodeDetectionService.Configuration = .default,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onError = onError
        self._cameraManager = StateObject(wrappedValue: cameraManager ?? CameraManager())

        // Initialize detection service with provided configuration
        self._detectionService = State(initialValue: BarcodeDetectionService(configuration: detectionConfiguration))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview layer
                CameraPreviewLayer(
                    cameraManager: cameraManager,
                    sessionState: $sessionState
                )
                .onTapGesture { location in
                    if configuration.enableTapToFocus {
                        handleTapToFocus(at: location, in: geometry.size)
                    }
                }

                // Focus indicator
                if configuration.showFocusIndicator, let focusPoint = focusPoint, showingFocusIndicator {
                    FocusIndicator()
                        .position(focusPoint)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(1)
                }

                // Scanning overlay
                if configuration.showScanningOverlay {
                    ScanningOverlay(
                        regionOfInterest: configuration.regionOfInterest,
                        style: configuration.overlayStyle
                    )
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                // Error overlay
                if case .error(let error) = sessionState {
                    ErrorOverlay(error: error, onRetry: startSession)
                        .zIndex(3)
                }
            }
        }
        .aspectRatio(configuration.aspectRatio, contentMode: .fit)
        .onAppear {
            startSession()
        }
        .onDisappear {
            stopSession()
        }
    }

    // MARK: - Public Methods

    /// Start barcode detection and return AsyncStream of ISBN detections
    func startISBNDetection() -> AsyncStream<ISBNValidator.ISBN> {
        guard let detectionService = detectionService else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        return detectionService.isbnDetectionStream(cameraManager: cameraManager)
    }

    /// Start general barcode detection
    func startBarcodeDetection() -> AsyncStream<BarcodeDetectionService.BarcodeDetection> {
        guard let detectionService = detectionService else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        return detectionService.startDetection(cameraManager: cameraManager)
    }

    /// Toggle torch (flashlight)
    func toggleTorch() async {
        do {
            try await cameraManager.toggleTorch()
        } catch {
            if let cameraError = error as? CameraError {
                onError(cameraError)
            }
        }
    }

    /// Focus at center of preview
    func focusAtCenter() async {
        do {
            try await cameraManager.focusAtCenter()
            await showFocusAnimation(at: CGPoint(x: 0.5, y: 0.5))
        } catch {
            if let cameraError = error as? CameraError {
                onError(cameraError)
            }
        }
    }

    // MARK: - Private Methods

    private func startSession() {
        Task {
            do {
                sessionState = .configuring
                try await cameraManager.startSession()
                _ = () // Discard the return value to avoid sendable issues
                sessionState = .running
            } catch {
                let cameraError = error as? CameraError ?? .sessionConfigurationFailed
                sessionState = .error(cameraError)
                onError(cameraError)
            }
        }
    }

    private func stopSession() {
        Task {
            await cameraManager.stopSession()
            await detectionService?.stopDetection()
            sessionState = .stopped
        }
    }

    private func handleTapToFocus(at location: CGPoint, in size: CGSize) {
        Task {
            do {
                // Convert tap location to camera coordinates
                let normalizedPoint = CGPoint(
                    x: location.x / size.width,
                    y: location.y / size.height
                )

                // Show focus animation
                await showFocusAnimation(at: location)

                // Focus camera (this would need to be implemented in CameraManager)
                try await cameraManager.focusAtCenter()

            } catch {
                if let cameraError = error as? CameraError {
                    onError(cameraError)
                }
            }
        }
    }

    @MainActor
    private func showFocusAnimation(at point: CGPoint) async {
        focusPoint = point

        withAnimation(.easeInOut(duration: 0.2)) {
            showingFocusIndicator = true
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        withAnimation(.easeInOut(duration: 0.3)) {
            showingFocusIndicator = false
        }
    }
}

// MARK: - Camera Preview Layer

private struct CameraPreviewLayer: UIViewRepresentable {
    let cameraManager: CameraManager
    @Binding var sessionState: CameraSessionState

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

// MARK: - Focus Indicator

private struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                    scale = 0.8
                }
            }
    }
}

// MARK: - Error Overlay

private struct ErrorOverlay: View {
    let error: CameraError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text(error.localizedDescription)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            if error != .permissionDenied {
                Button("Retry", action: onRetry)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(8)
            } else {
                Button("Open Settings") {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Modern Scanning Overlay

private struct ScanningOverlay: View {
    let regionOfInterest: CGRect?
    let style: ModernCameraPreview.ScanningOverlayStyle
    @State private var isScanning = false

    var body: some View {
        ZStack {
            // Darkened background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Scanning frame
            VStack {
                Spacer()

                ZStack {
                    // Frame based on style
                    switch style {
                    case .standard:
                        standardScanningFrame
                    case .isbn:
                        isbnScanningFrame
                    case .minimal:
                        minimalScanningFrame
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            isScanning = true
        }
    }

    @ViewBuilder
    private var standardScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 280, height: 140)

        RoundedRectangle(cornerRadius: 12)
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height))
    }

    @ViewBuilder
    private var isbnScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 300, height: 120)

        RoundedRectangle(cornerRadius: 8)
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
            )
            .overlay(
                // Corner indicators for ISBN scanning
                VStack {
                    HStack {
                        cornerMarker
                        Spacer()
                        cornerMarker
                    }
                    Spacer()
                    HStack {
                        cornerMarker
                        Spacer()
                        cornerMarker
                    }
                }
                .padding(8)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height, color: .blue))
    }

    @ViewBuilder
    private var minimalScanningFrame: some View {
        let frameSize = regionOfInterest ?? CGRect(x: 0, y: 0, width: 260, height: 100)

        Rectangle()
            .fill(Color.clear)
            .frame(width: frameSize.width, height: frameSize.height)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .overlay(animatedScanLine(width: frameSize.width, height: frameSize.height, thickness: 1))
    }

    private var cornerMarker: some View {
        Rectangle()
            .fill(Color.blue)
            .frame(width: 20, height: 3)
    }

    private func animatedScanLine(width: CGFloat, height: CGFloat, color: Color = .red, thickness: CGFloat = 3) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, color, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width - 20, height: thickness)
            .offset(y: isScanning ? -height/2 + 20 : height/2 - 20)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isScanning
            )
    }
}

// MARK: - Convenience Initializers

extension ModernCameraPreview {
    /// Create preview specifically for ISBN barcode scanning
    static func forISBNScanning(
        cameraManager: CameraManager? = nil,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: .isbnScanning,
            onError: onError
        )
    }

    /// Create minimal preview without overlays
    static func minimal(
        cameraManager: CameraManager? = nil,
        aspectRatio: CGFloat = 16/9,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        let config = Configuration(
            regionOfInterest: nil,
            showFocusIndicator: false,
            showScanningOverlay: false,
            enableTapToFocus: false,
            aspectRatio: aspectRatio,
            overlayStyle: .minimal
        )
        return ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: config,
            onError: onError
        )
    }

    /// Create full-featured preview
    static func fullFeatured(
        cameraManager: CameraManager? = nil,
        onError: @escaping (CameraError) -> Void = { _ in }
    ) -> ModernCameraPreview {
        ModernCameraPreview(
            cameraManager: cameraManager,
            configuration: .default,
            onError: onError
        )
    }
}
```

### 5\. `books/Views/Components/ModernBarcodeScannerView.swift`

This is the main SwiftUI wrapper that manages the lifecycle of the scanner, permissions, and user interface controls like the torch and focus.

```swift
import SwiftUI
import AVFoundation

/// Modern barcode scanner view using Swift 6 concurrency patterns
/// Replaces the legacy BarcodeScanner.swift with clean architecture
struct ModernBarcodeScannerView: View {
    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    let onISBNScanned: (ISBNValidator.ISBN) -> Void

    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var isTorchOn = false
    @State private var scanFeedback: ScanFeedback?
    @State private var isbnDetectionTask: Task<Void, Never>?
    @State private var cameraManager: CameraManager?

    // Camera configuration
    private let cameraConfiguration = ModernCameraPreview.Configuration(
        regionOfInterest: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4),
        showFocusIndicator: true,
        showScanningOverlay: true,
        enableTapToFocus: true,
        aspectRatio: nil,
        overlayStyle: .isbn
    )

    private let detectionConfiguration = BarcodeDetectionService.Configuration(
        enableVisionDetection: true,
        enableAVFoundationFallback: true,
        isbnValidationEnabled: true,
        duplicateThrottleInterval: 2.0,
        regionOfInterest: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4)
    )

    // MARK: - Feedback State

    private enum ScanFeedback: Equatable {
        case scanning
        case detected(String)
        case processing
        case error(String)

        var message: String {
            switch self {
            case .scanning:
                return "Position the barcode within the frame"
            case .detected(let isbn):
                return "ISBN detected: \(isbn)"
            case .processing:
                return "Processing barcode..."
            case .error(let message):
                return message
            }
        }

        var color: Color {
            switch self {
            case .scanning:
                return .white.opacity(0.8)
            case .detected:
                return .green
            case .processing:
                return .yellow
            case .error:
                return .red
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Main content based on permission status
                Group {
                    switch permissionStatus {
                    case .authorized:
                        authorizedContent
                    case .denied, .restricted:
                        permissionDeniedContent
                    case .notDetermined:
                        permissionRequestContent
                    @unknown default:
                        permissionRequestContent
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cleanup()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            checkCameraPermission()
        }
        .onDisappear {
            cleanup()
        }
        .alert("Camera Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                openSettings()
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Please allow camera access in Settings to scan barcodes.")
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var authorizedContent: some View {
        ZStack {
            // Camera preview
            ModernCameraPreview(
                configuration: cameraConfiguration,
                detectionConfiguration: detectionConfiguration
            ) { error in
                handleCameraError(error)
            }
            .ignoresSafeArea()
            .onAppear {
                startISBNDetection()
            }

            // Controls overlay
            VStack {
                // Top controls
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        // Torch button
                        Button(action: toggleTorch) {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(isTorchOn ? "Turn off torch" : "Turn on torch")

                        // Focus button
                        Button(action: focusCamera) {
                            Image(systemName: "camera.metering.center.weighted")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Focus camera")
                    }
                }
                .padding(.trailing)
                .padding(.top, 60)

                Spacer()

                // Bottom feedback
                feedbackView
                    .padding(.bottom, 100)
            }
        }
    }

    @ViewBuilder
    private var permissionDeniedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.6))

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Please enable camera access in Settings to scan ISBN barcodes.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open Settings") {
                openSettings()
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var permissionRequestContent: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Requesting Camera Access...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        VStack(spacing: 16) {
            Text(scanFeedback?.message ?? "Position the barcode within the frame")
                .font(.body)
                .foregroundColor(scanFeedback?.color ?? .white.opacity(0.8))
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: scanFeedback)

            // Processing indicator
            if case .processing = scanFeedback {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.yellow)
            }
        }
        .padding()
        .background(.black.opacity(0.6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func checkCameraPermission() {
        Task { @CameraSessionActor in
            let status = CameraManager.cameraPermissionStatus
            await MainActor.run {
                permissionStatus = status
            }

            if status == .notDetermined {
                let granted = await CameraManager.requestCameraPermission()
                await MainActor.run {
                    permissionStatus = granted ? .authorized : .denied
                    if !granted {
                        showingPermissionAlert = true
                    }
                }
            } else if status == .denied || status == .restricted {
                await MainActor.run {
                    showingPermissionAlert = true
                }
            }
        }
    }

    private func startISBNDetection() {
        // Cancel any existing detection task
        isbnDetectionTask?.cancel()

        isbnDetectionTask = Task {
            await handleISBNDetectionStream()
        }
    }

    private func handleISBNDetectionStream() async {
        // Initialize scanning state
        await MainActor.run {
            scanFeedback = .scanning
        }

        // Create camera manager and detection service
        let manager = await Task { @CameraSessionActor in
            return CameraManager()
        }.value

        // Store for reuse in other methods
        await MainActor.run {
            cameraManager = manager
        }

        let detectionService = BarcodeDetectionService(configuration: detectionConfiguration)

        // Start the detection stream
        for await isbn in detectionService.isbnDetectionStream(cameraManager: manager) {
            await handleISBNDetected(isbn)
            break // Exit after first successful detection
        }
    }

    @MainActor
    private func handleISBNDetected(_ isbn: ISBNValidator.ISBN) {
        // Provide immediate feedback
        withAnimation {
            scanFeedback = .detected(isbn.displayValue)
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Brief processing state
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                withAnimation {
                    scanFeedback = .processing
                }
            }

            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            await MainActor.run {
                onISBNScanned(isbn)
                cleanup()
                dismiss()
            }
        }
    }

    private func toggleTorch() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Toggle torch via camera manager
        Task {
            guard let manager = cameraManager else {
                await MainActor.run {
                    handleCameraError(.deviceUnavailable)
                }
                return
            }

            do {
                try await manager.toggleTorch()
                let torchState = await manager.isTorchOn
                await MainActor.run {
                    isTorchOn = torchState
                }
            } catch {
                await MainActor.run {
                    handleCameraError(.torchUnavailable)
                }
            }
        }
    }

    private func focusCamera() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Temporary feedback
        withAnimation {
            scanFeedback = .scanning
        }

        // Focus camera via camera manager
        Task {
            guard let manager = cameraManager else {
                await MainActor.run {
                    handleCameraError(.deviceUnavailable)
                }
                return
            }

            do {
                try await manager.focusAtCenter()
            } catch {
                await MainActor.run {
                    handleCameraError(.focusUnavailable)
                }
            }
        }
    }

    private func handleCameraError(_ error: CameraError) {
        withAnimation {
            scanFeedback = .error(error.localizedDescription)
        }

        // Auto-clear error after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                if case .error = scanFeedback {
                    withAnimation {
                        scanFeedback = .scanning
                    }
                }
            }
        }
    }

    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }

    private func cleanup() {
        isbnDetectionTask?.cancel()
        isbnDetectionTask = nil

        // Turn off torch if it's on
        if isTorchOn {
            Task {
                if let manager = cameraManager {
                    try? await manager.setTorchMode(.off)
                }
                await MainActor.run {
                    isTorchOn = false
                    cameraManager = nil
                }
            }
        } else {
            // Clean up camera manager reference
            cameraManager = nil
        }
    }
}

// MARK: - Integration Extension

extension ModernBarcodeScannerView {
    /// Create scanner view with legacy callback compatibility
    static func withCallback(onBarcodeScanned: @escaping (String) -> Void) -> some View {
        ModernBarcodeScannerView { isbn in
            onBarcodeScanned(isbn.normalizedValue)
        }
    }
}
```