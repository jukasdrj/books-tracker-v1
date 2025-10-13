# Bookshelf AI Scanner: Frontend Implementation Plan

**Version:** 1.0
**Date:** October 12, 2025
**Status:** Planning

This document outlines the three-phased plan for building the user interface and client-side logic for the Bookshelf AI Scanning feature in the BooksTracker iOS app.

---

### **Phase 1: Core User Flow & Hybrid Architecture**

**Goal:** Implement the core user flow from image capture to displaying initial results, following the hybrid architecture for a responsive user experience.

#### **1.1. Implement Camera and Image Capture UI:**
- **Task:** Build the camera interface with proactive guidance as specified in the design plan.
- **Implementation:**
    - Use `AVFoundation` to build a custom camera view in `BookshelfCameraView.swift`.
    - Add the framing guide, real-time quality feedback (lighting, stability), and level/tilt indicator.
    - On capture, compress the image to a high-quality JPEG (e.g., 85% quality, max resolution of 1920x1080) to optimize upload speed.

#### **1.2. Implement the Hybrid API Flow:**
- **Task:** Build the client-side logic for the "Instant Display + Progressive Enrichment" architecture.
- **Implementation:**
    - In `BookshelfScanModel.swift`, create a function `scanBookshelf(image:)`.
    - This function will first `POST` the image data directly to the `bookshelf-ai-worker`.
    - While waiting for the AI response, the UI will display a loading indicator.
    - Upon receiving the response, immediately parse the detected books and update the UI to display them in the `ScanResultsView`.

#### **1.3. Build the Initial Results View:**
- **Task:** Create the `ScanResultsView` to display the initial, unenriched results from the AI worker.
- **Implementation:**
    - The view will show the captured image with bounding boxes overlaid.
    - Each bounding box will display the detected title and author.
    - Use visual indicators (e.g., color-coded borders) to represent the confidence score of each detection.
    - Implement the "Add to Library" button, which will be initially disabled.

#### **1.4. Verification & Testing:**
- **UI Tests:**
    - Write UI tests to verify that the camera view opens, an image can be captured, and the loading state is displayed.
- **Manual Testing:**
    - Capture images under different lighting conditions and angles to verify the real-time quality feedback.
    - Use a mock server to return sample AI data and verify that the `ScanResultsView` displays the bounding boxes and text correctly.
    - **Verification:**
        - Ensure the app does not freeze during the 25-40s AI processing time.
        - Confirm that unenriched results are displayed to the user almost instantly after the AI processing is complete.

---

### **Phase 2: Progressive Enrichment & User Interaction**

**Goal:** Enhance the user experience by enriching the detected books with metadata from the library's API and allowing the user to interact with and correct the results.

#### **2.1. Implement Progressive Enrichment:**
- **Task:** After the initial results are displayed, trigger background requests to the `books-api-proxy` to enrich the high-confidence detections.
- **Implementation:**
    - In `BookshelfScanModel.swift`, after receiving the AI response, filter for high-confidence detections (e.g., `confidence.overall >= 0.7`).
    - Use a `TaskGroup` to send parallel requests to the `/search/advanced` endpoint for each high-confidence book.
    - As each enrichment request completes, update the corresponding `DetectedBook` object in the UI with the new metadata (cover image, publisher, etc.).

#### **2.2. Enhance the Interactive Results View:**
- **Task:** Allow users to tap on bounding boxes to view details, confirm or correct detections, and manually add books.
- **Implementation:**
    - Make each bounding box in `ScanResultsView` a tappable element.
    - Tapping a box will present a half-sheet with the detected information and the enriched metadata (if available).
    - In this half-sheet, provide an "Add to Library" button. For low-confidence detections, this button could be labeled "Search Manually."

#### **2.3. Verification & Testing:**
- **UI Tests:**
    - Write UI tests to simulate tapping on a bounding box and verifying that the detail sheet appears.
- **Integration Tests:**
    - Perform a full end-to-end test, from image capture to enrichment.
    - **Verification:**
        - Confirm that cover images and other metadata progressively appear in the `ScanResultsView` after the initial detections are shown.
        - Verify that tapping "Add to Library" correctly adds the book to the user's SwiftData library.
        - Test the manual search flow for a low-confidence detection.

---

### **Phase 3: Finalizing the Flow and Adding Polish**

**Goal:** Polish the user experience with features like batch actions, clear error handling, and a seamless transition to the user's library.

#### **3.1. Implement Batch Actions:**
- **Task:** Add "Add All" and "Clear All" buttons to the results view.
- **Implementation:**
    - The "Add All" button will add all high-confidence, user-confirmed books to the library in a single batch operation.
    - The "Clear All" button will discard the scan results and return the user to the camera view.

#### **3.2. Robust Error Handling:**
- **Task:** Implement user-friendly error messages for all potential failure points.
- **Implementation:**
    - Display alerts for network errors, image quality issues (as returned by the AI worker), and API failures.
    - Provide clear "Retry" and "Cancel" actions for each error.

#### **3.3. Implement User Feedback:**
- **Task:** Integrate with the `/feedback` endpoint on the backend to allow users to report incorrect detections.
- **Implementation:**
    - In the detail sheet for each detection, add a "Report Incorrect Detection" button.
    - Tapping this button will send the `detectionId` and a `correct: false` flag to the `/feedback` endpoint.

#### **3.4. Verification & Testing:**
- **UI Tests:**
    - Write UI tests for the "Add All" and "Clear All" buttons, verifying that the correct alerts and state changes occur.
- **Manual Testing:**
    - Test various error scenarios (e.g., turn off Wi-Fi, upload a poor-quality image) to verify that the error messages are clear and helpful.
    - **Verification:**
        - Confirm that batch actions work as expected and provide appropriate confirmation dialogs.
        - Verify that user feedback is successfully sent to the backend.

---

### **Success Metrics**

* **User Adoption:** >30% of new books are added via the bookshelf scanner within 3 months of launch.
* **Task Completion Rate:** >90% of users who start a scan successfully add at least one book to their library.
* **User Satisfaction:** The feature receives an average rating of 4.5/5 stars in user feedback surveys.
* **Time to Value:** The time from launching the feature to having a fully enriched book in the user's library is under 60 seconds on average.
* **Accuracy:** <10% of high-confidence detections require manual correction by the user.