# Plan: Rebuilding Barcode Scanning with AVFoundation and Vision

This document outlines a detailed plan to implement a robust, native barcode scanning experience using Apple's recommended frameworks, `AVFoundation` and `Vision`. This approach will create a live camera view that continuously analyzes the video stream for barcodes, providing a seamless, modern user experience.

---

### Phase 1: Create a UIKit Camera View Controller

Since `AVFoundation` (the camera framework) is UIKit-based, we will first create a `UIViewController` to manage the camera session and the video preview. This is the standard practice for integrating advanced camera functionality into a SwiftUI application.

1.  **New File:** Create `BarcodeScannerViewController.swift` inside `BooksTrackerPackage/Sources/BooksTrackerFeature/`.
2.  **Responsibilities:**
    *   **Camera Permissions:** Request user permission for camera access using `AVCaptureDevice.requestAccess(for: .video)`.
    *   **AVFoundation Setup:**
        *   Initialize and configure an `AVCaptureSession`.
        *   Find the default video device (`AVCaptureDevice`).
        *   Create an `AVCaptureDeviceInput` from the device.
        *   Create an `AVCaptureVideoDataOutput` to receive raw video frames for analysis.
        *   Add the input and output to the session.
    *   **Live Preview:** Create an `AVCaptureVideoPreviewLayer` and add it to the view controller's main view. This layer will display the live camera feed to the user.
    *   **Delegate:** Set the view controller as the delegate for the `AVCaptureVideoDataOutput` to process video frames as they are captured.

### Phase 2: Implement Barcode Detection with the Vision Framework

We will use Apple's `Vision` framework to analyze the video frames from `AVFoundation` in real-time, which is highly efficient and optimized for the platform.

1.  **Adopt Protocol:** Make `BarcodeScannerViewController` conform to `AVCaptureVideoDataOutputSampleBufferDelegate`.
2.  **Implement `captureOutput`:** In the delegate method `captureOutput(_:didOutput:from:)`, we will:
    *   Convert the incoming `CMSampleBuffer` (the video frame) into a `CVImageBuffer`.
    *   Create a `VNImageRequestHandler` for the image buffer.
    *   Define a `VNDetectBarcodesRequest`. This is the Vision request that specifically looks for barcodes.
    *   In the completion handler of the request, check the results for `VNBarcodeObservation` objects.
    *   If a barcode is found, extract its string value (`payloadStringValue`).
    *   To prevent duplicate scans and conserve resources, we'll process the *first* valid barcode found and then use a callback to notify our SwiftUI view.

### Phase 3: Bridge the UIKit Controller to SwiftUI

To use our `BarcodeScannerViewController` in the existing SwiftUI interface, we'll wrap it in a `UIViewControllerRepresentable`. This is the standard bridging mechanism.

1.  **New File:** Create `BarcodeScannerView.swift` in the same directory (`BooksTrackerPackage/Sources/BooksTrackerFeature/`).
2.  **Responsibilities:**
    *   Conform to `UIViewControllerRepresentable`.
    *   **Data Binding:** It will have a binding (e.g., `@Binding var scannedCode: String?`) to pass the detected barcode string back to the parent SwiftUI view.
    *   **Coordinator:** It will have a `Coordinator` class. This coordinator will act as the delegate for our `BarcodeScannerViewController` to receive the found barcode and update the SwiftUI binding on the main thread.
    *   **Lifecycle Methods:** Implement `makeUIViewController` and `updateUIViewController` to create and manage the `BarcodeScannerViewController`'s lifecycle.

### Phase 4: Integrate into the Existing UI

Finally, we'll replace the current, non-functional barcode scanning action with our new, fully functional `BarcodeScannerView`.

1.  **Locate the View:** I will find the SwiftUI view that contains the "Scan Barcode" button, which is expected to be within `BooksTrackerPackage/Sources/BooksTrackerFeature/`.
2.  **State Management:** In that SwiftUI view, I will add state variables to manage the presentation and result:
    *   `@State private var isShowingScanner = false`
    *   `@State private var scannedCode: String?`
3.  **Trigger the Scanner:** The "Scan Barcode" button's action will now simply set `isShowingScanner` to `true`.
4.  **Present the View:** A `.sheet` modifier will be used to present the scanner modally for a clean user experience:
    ```swift
    .sheet(isPresented: $isShowingScanner) {
        BarcodeScannerView(scannedCode: $scannedCode)
    }
    ```
5.  **Handle the Result:** An `.onChange(of: scannedCode)` modifier will watch for changes. When `scannedCode` receives a value, we will:
    *   Dismiss the scanner sheet by setting `isShowingScanner = false`.
    *   Use the `scannedCode` value to proceed with the app's logic (e.g., fetching book details from an API).

### Final Step: Update Project Configuration

1.  **Info.plist:** I will add the `NSCameraUsageDescription` key to the project's `Info.plist` file. This is a mandatory step to provide a user-facing reason for requiring camera access, ensuring the app is compliant with Apple's privacy policies.
