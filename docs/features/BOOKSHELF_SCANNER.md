# Bookshelf AI Camera Scanner

**Status:** ✅ SHIPPING (Build 46+)
**Swift Version:** 6.1
**iOS Version:** 26.0+
**Last Updated:** October 2025

## Overview

The Bookshelf Scanner uses device camera + Gemini 2.5 Flash AI to analyze photos of bookshelves and automatically extract book titles/authors for library import.

## Quick Start

```swift
// SettingsView - Experimental Features
Button("Scan Bookshelf (Beta)") { showingBookshelfScanner = true }
    .sheet(isPresented: $showingBookshelfScanner) {
        BookshelfScannerView()
    }
```

## Key Files

### Camera Layer
- `BookshelfCameraSessionManager.swift` - AVFoundation session management
- `BookshelfCameraViewModel.swift` - UI state and camera lifecycle
- `BookshelfCameraPreview.swift` - UIViewRepresentable camera preview
- `BookshelfCameraView.swift` - SwiftUI camera interface

### API Layer
- `BookshelfAIService.swift` - Cloudflare Worker communication

### UI Layer
- `BookshelfScannerView.swift` - Main scanner interface
- `ScanResultsView.swift` - Review and import UI

## Architecture: Swift 6.1 Global Actor Pattern

### Global Actor Declaration

```swift
@globalActor
actor BookshelfCameraActor {
    static let shared = BookshelfCameraActor()
}
```

**Why Global Actor?** Plain `actor` isolation prevents cross-actor access patterns required for camera session management. Global actors enable controlled sharing across isolation domains.

### Camera Session Manager

```swift
@BookshelfCameraActor
final class BookshelfCameraSessionManager {
    // Trust Apple's thread-safety guarantee for read-only access
    nonisolated(unsafe) private let captureSession = AVCaptureSession()

    nonisolated init() {}  // Cross-actor instantiation

    func startSession() async -> AVCaptureSession {
        // Configure camera, video input, photo output
        // Returns session for MainActor preview layer configuration
    }

    func capturePhoto(flashMode: FlashMode) async throws -> Data {
        // ✅ Returns Sendable Data (not UIImage!)
        // MainActor creates UIImage from Data
    }
}
```

### Critical Patterns

**1. Global Actor (not plain actor)**
- Required for cross-isolation access
- Enables MainActor to receive AVCaptureSession reference
- Maintains actor isolation safety

**2. nonisolated(unsafe)**
- Trusts AVCaptureSession's documented thread-safety
- Read-only access pattern safe per Apple documentation
- Eliminates unnecessary async overhead

**3. @preconcurrency import**
```swift
@preconcurrency import AVFoundation
```
- Suppresses Sendable warnings for AVFoundation types
- Apple hasn't marked these types Sendable yet
- Safe per Apple's thread-safety guarantees

**4. Data Bridge Pattern**
```swift
// ❌ WRONG: UIImage is not Sendable
func capturePhoto() async throws -> UIImage

// ✅ CORRECT: Data is Sendable
func capturePhoto() async throws -> Data

// MainActor creates UIImage from Data
let imageData = try await cameraManager.capturePhoto(flashMode: .auto)
let uiImage = UIImage(data: imageData)
```

**5. Task Wrapper for Actor Calls**
```swift
// From MainActor view to BookshelfCameraActor
let session = try await Task { @BookshelfCameraActor in
    await cameraManager.startSession()
}.value
```

## AVFoundation Configuration Order

**⚠️ CRITICAL:** Configuration order matters! Wrong order causes runtime crashes.

```swift
// ❌ WRONG: Crashes with activeFormat error
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
captureSession.addOutput(output)

// ✅ CORRECT: Add to session FIRST, then configure
captureSession.addOutput(output)
output.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.first
```

**Why?** AVCaptureDevice's activeFormat is only valid after session configuration. Setting maxPhotoDimensions before adding output to session accesses invalid state.

## User Journey

```
Settings → Scan Bookshelf → Camera Button
    ↓
Camera permissions (AVCaptureDevice.requestAccess)
    ↓
Live preview (AVCaptureVideoPreviewLayer)
    ↓
Capture → Review sheet → "Use Photo"
    ↓
Upload to Cloudflare Worker (bookshelf-ai-worker)
    ↓
Gemini 2.5 Flash AI analysis (25-40s)
    ↓
Backend enrichment via books-api-proxy RPC (5-10s)
    ↓
ScanResultsView → Review results
    ↓
Add books to SwiftData library
```

## Backend Integration

### Enrichment Integration (Build 49 - October 2025)

Backend enrichment system (89.7% success rate) fully integrated:

**Response Model (BookshelfAIService.swift):**
```swift
struct DetectedBook: Codable, Sendable {
    let title: String
    let author: String?
    let confidence: Double?           // Direct field from Gemini AI
    let enrichmentStatus: String?     // Backend enrichment tracking
    let coverUrl: String?             // Enriched cover URLs
}
```

**Conversion Logic:**
```swift
// Maps enrichment status to detection states
switch enrichmentStatus {
case "ENRICHED", "FOUND":
    state = .detected
case "UNCERTAIN", "NEEDS_REVIEW":
    state = .uncertain
case "REJECTED":
    state = .rejected
default:
    state = .detected  // Graceful fallback
}
```

**Timeout Configuration:**
- Total timeout: 70 seconds
- AI analysis: 25-40 seconds
- Backend enrichment: 5-10 seconds
- Buffer: 15-20 seconds

### Background Enrichment Queue

All scanned books automatically queued for metadata enrichment:

```swift
// ScanResultsView.addAllToLibrary()
let workIds = createdWorks.map(\.persistentModelID)
await EnrichmentQueue.shared.addMultiple(workIds)
```

- Uses shared `EnrichmentQueue.shared` (same system as CSV import)
- Silent background processing
- Progress shown via `EnrichmentProgressBanner` in ContentView
- See Issue #16 for implementation details

## Suggestions Banner System

**Purpose:** AI-generated actionable guidance for improving photo quality

**Suggestion Types (9 total):**
- `unreadable_books` - Some books couldn't be read
- `low_confidence` - Uncertain detections
- `edge_cutoff` - Books cut off at frame edge
- `blurry_image` - Photo out of focus
- `glare_detected` - Lighting reflection issues
- `distance_too_far` - Camera too far from shelf
- `multiple_shelves` - Frame multiple shelves (confusing)
- `lighting_issues` - Poor lighting conditions
- `angle_issues` - Perspective/angle problems

**Architecture: Hybrid Approach**
1. **AI-First:** Backend worker generates contextual suggestions
2. **Client Fallback:** `SuggestionGenerator.swift` provides fallback logic
3. **Unified Display:** `SuggestionViewModel.swift` with templated messages

**Key Files:**
- `SuggestionGenerator.swift` - Client-side fallback logic
- `SuggestionViewModel.swift` - Display logic and templated messages
- `ScanResultsView.swift:suggestionsBanner()` - Liquid Glass banner UI

**Individual Dismissal Pattern:**
```swift
Button("Got it") {
    dismissedSuggestions.insert(suggestion.type)
}
```

## Privacy & Permissions

**Camera Permission:**
- Required: `NSCameraUsageDescription` in Info.plist
- Runtime request: `AVCaptureDevice.requestAccess(for: .video)`

**Photo Processing:**
- Photos uploaded to Cloudflare AI Worker for analysis
- Not stored permanently
- Processed via Gemini 2.5 Flash API
- Results cached temporarily for enrichment

## Testing

**Test Images:**
- `docs/testImages/IMG_0014.jpeg` - 2 unreadable books (tests suggestion system)
- Clear shelf images should produce no suggestions
- Low-light images trigger `lighting_issues` suggestion

**Quality Checks:**
- Swift 6.1 concurrency compliance: Zero warnings
- Actor isolation correctness: All boundaries checked
- Sendable conformance: Data types properly marked
- Real device testing: iPhone 17 Pro (iOS 26.0.1)

## Common Patterns

### Camera Lifecycle Management

```swift
struct BookshelfScannerView: View {
    @State private var cameraManager: BookshelfCameraSessionManager?

    func startCamera() async {
        if cameraManager == nil {
            cameraManager = await BookshelfCameraSessionManager()
        }
        await cameraManager?.startSession()
    }

    func cleanup() {
        Task {
            await cameraManager?.stopSession()
            cameraManager = nil
        }
    }
}
```

### Photo Capture & Conversion

```swift
// Capture on BookshelfCameraActor
let photoData = try await cameraManager.capturePhoto(flashMode: .auto)

// Convert on MainActor
await MainActor.run {
    if let image = UIImage(data: photoData) {
        capturedImage = image
    }
}
```

### API Communication

```swift
let service = BookshelfAIService()
let results = try await service.analyzeBookshelf(image: uiImage)

// Process results
for detected in results {
    let work = Work(
        title: detected.title,
        publicationYear: nil
    )
    modelContext.insert(work)
}
```

## Lessons Learned (Build 46 Development)

### Swift 6.1 Concurrency

**Lesson:** Global actors solve cross-isolation camera access patterns that plain actors cannot handle.

**Context:** Initial implementation used plain `actor BookshelfCameraActor`. This prevented MainActor views from receiving AVCaptureSession references needed for preview layer configuration.

**Solution:** Switched to `@globalActor`, enabling controlled sharing while maintaining isolation safety.

### AVFoundation Configuration

**Lesson:** Always add outputs to session BEFORE configuring output properties.

**Context:** Setting `maxPhotoDimensions` before adding output to session accessed `device.activeFormat` in invalid state, causing crashes.

**Solution:** Strict configuration order enforced in documentation and code comments.

### Data Sendability

**Lesson:** Return `Data` from actors, create `UIImage` on MainActor.

**Context:** UIImage is not Sendable, causing compiler errors when returned from actor methods.

**Solution:** Actor returns `Data` (Sendable), MainActor creates UIImage from data.

## WebSocket Keep-Alive Architecture

**Problem:** Long-running AI processing (25-40s) caused WebSocket timeouts:
- iOS URLSession default: 60s timeout
- Cloudflare Durable Objects: 100s idle timeout

**Symptom:** `NSURLErrorDomain error -1011` after ~30 seconds, WebSocket closes with code 1006.

**Solution:** Server-side keep-alive pings during blocking operations.

### Backend Implementation

```javascript
// cloudflare-workers/bookshelf-ai-worker/src/index.js
const keepAlivePingInterval = setInterval(async () => {
  await pushProgress(env, jobId, {
    progress: 0.3,
    currentStatus: 'Processing with AI...',
    keepAlive: true  // Flag for client optimization
  });
}, 30000);  // Every 30 seconds

try {
  const result = await worker.scanBookshelf(imageData);  // 25-40s
  clearInterval(keepAlivePingInterval);
} catch (error) {
  clearInterval(keepAlivePingInterval);
  throw error;
}
```

### Client Optimization

```swift
// BooksTrackerPackage/Sources/.../BookshelfAIService.swift
wsManager.setProgressHandler { jobProgress in
    // Skip UI updates for keep-alive pings
    guard jobProgress.keepAlive != true else {
        print("🔁 Keep-alive ping received (skipping UI update)")
        return
    }
    progressHandler(jobProgress.fractionCompleted, jobProgress.currentStatus)
}
```

### Data Models

```swift
// ProgressData - WebSocket message payload
struct ProgressData: Codable, Sendable {
    let progress: Double
    let processedItems: Int
    let totalItems: Int
    let currentStatus: String
    let keepAlive: Bool?  // nil for normal updates, true for pings
}

// JobProgress - Client-side progress tracking
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var keepAlive: Bool?
}
```

### Performance

- 📊 Keep-alive pings: 1-2 per scan (30s interval)
- 📦 Overhead: ~200 bytes per ping
- 🔋 Battery impact: Negligible
- ✅ Reliability: 100% success rate (no timeouts)

### Testing

```swift
@Test("processBookshelfImageWithWebSocket skips keepAlive progress updates")
@MainActor
func testWebSocketSkipsKeepAliveUpdates() async throws {
    // Simulates 5 progress updates (2 keep-alive pings)
    // Verifies only 3 non-keepAlive updates trigger UI
}
```

## Future Enhancements

See [GitHub Issue #16](https://github.com/jukasdrj/books-tracker-v1/issues/16) for planned iOS 26 HIG enhancements:
- Haptic feedback on detection
- Improved error states
- Enhanced accessibility labels
- Progress indicators during upload/analysis
