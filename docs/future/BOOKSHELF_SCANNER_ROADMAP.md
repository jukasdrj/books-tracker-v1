# PROJECT ROADMAP: Bookshelf AI Scanner Frontend

**Version:** 1.0
**Date:** October 13, 2025
**Status:** Architecture Review
**Project Lead:** Technical Project Manager (Claude Code)

---

## Executive Summary

This document outlines the comprehensive implementation plan for the Bookshelf AI Scanner feature in BooksTracker v3.x. The feature enables users to capture photos of their bookshelves and automatically detect/add books to their digital library using Cloudflare AI Workers for computer vision.

**Scope:** Phase 1 (MVP for launch), Phase 2 (post-launch enhancements), Phase 3 (advanced features)
**Timeline:** Phase 1 estimated 2-3 weeks of development + 3-5 days real device validation
**Dependencies:** Cloudflare `bookshelf-ai-worker` (implemented per `shelfBack.md`)

---

## Project Overview

**Objective**: Implement a production-ready Bookshelf AI Scanner that captures bookshelf photos, sends them to Cloudflare AI for analysis, and progressively enriches detected books with metadata.

**Complexity**: High
- Camera integration with AVFoundation (hardware exclusivity requirements)
- Network API with 25-40s processing time (requires robust loading states)
- Progressive UI updates during enrichment (TaskGroup concurrency)
- Memory management for image capture/compression (<200MB target)

**Estimated Phases**: 3 major phases
- **Phase 1**: Core flow (MVP - launch blocking)
- **Phase 2**: Interactive improvements (post-launch)
- **Phase 3**: Advanced features (future iteration)

**Key Risks**:
1. **Memory Management**: Image capture/compression must stay <200MB (like CSV import)
2. **Network Reliability**: 25-40s AI processing time requires robust error handling
3. **Actor Isolation**: Must maintain Swift 6 strict concurrency with camera hardware exclusivity
4. **Real Device Testing**: Camera features MUST be validated on physical devices (simulator inadequate)
5. **User Experience**: Long processing time requires thoughtful loading states and feedback

---

## Architecture Blueprint

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│  BookshelfCameraView (@MainActor)                      │
│  ├─ CameraManager (@CameraSessionActor) [REUSE]        │
│  ├─ CameraGuidanceOverlay (framing + quality feedback) │
│  └─ Capture Button → BookshelfScanModel.startScan()   │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  BookshelfScanModel (@Observable @MainActor)           │
│  ├─ capturedImage: UIImage?                            │
│  ├─ scanState: ScanState (.capturing, .processing...)  │
│  ├─ detectedBooks: [DetectedBook]                       │
│  ├─ enrichmentProgress: [UUID: EnrichmentStatus]       │
│  └─ Methods:                                            │
│     ├─ startScan(imageData: Data)                      │
│     ├─ processAIResponse()                             │
│     └─ startProgressiveEnrichment()                    │
└─────────────────────────────────────────────────────────┘
           │                        │
           ▼                        ▼
┌──────────────────────┐  ┌─────────────────────────────┐
│ ImageCompression     │  │ BookshelfAIService          │
│ Service              │  │ (@nonisolated sendable)     │
│ (nonisolated async)  │  │ ├─ POST /scan               │
│ ├─ compress(image)   │  │ ├─ Parse JSON response      │
│ └─ Output: Data      │  │ └─ Return [DetectedBook]    │
└──────────────────────┘  └─────────────────────────────┘
                                    │
                                    ▼
                          ┌───────────────────────────────┐
                          │ EnrichmentCoordinator         │
                          │ (@MainActor)                  │
                          │ ├─ TaskGroup for parallel API │
                          │ ├─ /search/advanced calls     │
                          │ └─ Incremental UI updates     │
                          └───────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────┐
│  ScanResultsView (@MainActor)                          │
│  ├─ Captured image with bounding boxes                 │
│  ├─ List of detected books (enrichment status)         │
│  ├─ Tap book → DetectedBookDetailSheet                 │
│  └─ Batch actions: "Add All" / "Clear All"             │
└─────────────────────────────────────────────────────────┘
```

### File Structure

**Location:** `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/`

```
BookshelfScanning/
├── Models/
│   ├── DetectedBook.swift ✅ (EXISTS - needs enhancement)
│   ├── BookshelfScanModel.swift 🆕
│   └── AIBookDetection.swift 🆕
├── Services/
│   ├── BookshelfAIService.swift 🆕
│   ├── ImageCompressionService.swift 🆕
│   └── EnrichmentCoordinator.swift 🆕
├── Views/
│   ├── BookshelfCameraView.swift 🆕
│   ├── ScanProgressView.swift 🆕
│   ├── ScanResultsView.swift 🆕
│   └── DetectedBookDetailSheet.swift 🆕
└── Supporting/
    ├── CameraGuidanceOverlay.swift 🆕
    └── BoundingBoxRenderer.swift 🆕
```

---

## Phase 1: Core User Flow (MVP - LAUNCH BLOCKING)

**Goal**: Complete flow from camera capture → AI processing → results display → progressive enrichment → add to library.

### Task 1.1: Enhance DetectedBook Model
**File**: `BookshelfScanning/Models/DetectedBook.swift`
**Status**: Exists, needs enhancement

**Add Fields**:
- `publisher: String?`
- `publicationYear: Int?`
- `coverImageURL: URL?` (populated during enrichment)
- `enrichmentStatus: EnrichmentStatus` enum

**Conform to**: `Codable` for AI response parsing

---

### Task 1.2: Create BookshelfScanModel
**File**: `BookshelfScanning/Models/BookshelfScanModel.swift`
**Pattern**: `@Observable @MainActor` (matches app patterns)

```swift
@Observable
@MainActor
final class BookshelfScanModel {
    // State
    var scanState: ScanState = .idle
    var capturedImage: UIImage?
    var detectedBooks: [DetectedBook] = []
    var enrichmentProgress: [UUID: EnrichmentStatus] = [:]
    var errorMessage: String?

    // Dependencies
    private let aiService: BookshelfAIService
    private let enrichmentCoordinator: EnrichmentCoordinator
    private let modelContext: ModelContext

    // API
    func startScan(imageData: Data) async
    func retryEnrichment(for bookID: UUID) async
    func addToLibrary(_ book: DetectedBook) async
    func addAllHighConfidence() async
    func clearScan()
}
```

**States**:
```swift
enum ScanState {
    case idle
    case capturing
    case compressing
    case uploadingToAI
    case processingAI(progress: Double?)
    case displayingResults
    case enriching(completed: Int, total: Int)
    case error(String)
}

enum EnrichmentStatus {
    case pending
    case inProgress
    case completed(metadata: EnrichedMetadata)
    case failed(String)
}
```

---

### Task 1.3: Implement ImageCompressionService
**File**: `BookshelfScanning/Services/ImageCompressionService.swift`
**Isolation**: `nonisolated async` (Sendable struct)

```swift
struct ImageCompressionService: Sendable {
    static func compress(
        _ image: UIImage,
        maxDimension: CGFloat = 1920,
        quality: CGFloat = 0.85
    ) async -> Result<Data, CompressionError> {
        // 1. Resize to max 1920x1080 (maintain aspect ratio)
        // 2. Convert to JPEG at 85% quality
        // 3. Target output: 2-5 MB
    }
}
```

**Memory Safety**:
- Use `autoreleasepool` for UIImage operations
- Release UIImage immediately after compression
- Validate output size <10MB

---

### Task 1.4: Implement BookshelfAIService
**File**: `BookshelfScanning/Services/BookshelfAIService.swift`
**Isolation**: `actor` (network operations)

```swift
actor BookshelfAIService {
    func scanBookshelf(imageData: Data) async throws -> [DetectedBook] {
        // POST multipart/form-data to bookshelf-ai-worker
        // Timeout: 60s (AI processing is 25-40s)
        // Parse JSON response
    }
}
```

**Endpoint**: `POST https://bookshelf-ai-worker.jukasdrj.workers.dev/scan`
**Error Handling**: Network, API, JSON parsing, image quality rejection

---

### Task 1.5: Implement EnrichmentCoordinator
**File**: `BookshelfScanning/Services/EnrichmentCoordinator.swift`
**Isolation**: `@MainActor` (updates UI incrementally)

```swift
@MainActor
final class EnrichmentCoordinator: ObservableObject {
    @Published var progress: [UUID: EnrichmentStatus] = [:]

    func enrichBooks(_ books: [DetectedBook]) async {
        let highConfidence = books.filter { $0.confidence >= 0.7 }

        await withTaskGroup(of: (UUID, EnrichmentResult).self) { group in
            for book in highConfidence {
                group.addTask {
                    await self.enrichBook(book)
                }
            }

            for await (id, result) in group {
                self.progress[id] = .completed(result)
            }
        }
    }
}
```

**API**: `GET /search/advanced?title=...&author=...` (books-api-proxy)

---

### Task 1.6: Build BookshelfCameraView
**File**: `BookshelfScanning/Views/BookshelfCameraView.swift`
**Pattern**: Reuse `CameraManager` with single-instance dependency injection

**Critical Pattern** (from CLAUDE.md barcode scanner):
```swift
struct BookshelfCameraView: View {
    @State private var cameraManager: CameraManager? // SINGLE ownership
    @State private var scanModel = BookshelfScanModel()

    var body: some View {
        ZStack {
            if let manager = cameraManager {
                ModernCameraPreview(
                    cameraManager: manager, // Dependency injection
                    configuration: cameraConfig,
                    detectionConfiguration: nil
                )
            }

            CameraGuidanceOverlay() // Framing, quality feedback

            Button("Capture Bookshelf") {
                Task { await captureAndScan() }
            }
        }
        .onAppear {
            cameraManager = CameraManager() // Create ONCE
        }
        .onDisappear {
            cleanup() // Stop session, nil out manager
        }
    }
}
```

**Guidance Overlays**:
- Framing guide (horizontal lines for shelf alignment)
- Lighting indicator (too dark/bright)
- Stability indicator (motion blur warning)
- Level/tilt indicator (angle correction)

---

### Task 1.7: Build ScanProgressView
**File**: `BookshelfScanning/Views/ScanProgressView.swift`
**Duration**: Displays during 25-40s AI processing

**States**:
- Compressing image (spinner)
- Uploading to AI (progress bar if determinable)
- Processing with AI (spinner + "Analyzing bookshelf...")
- Parsing results (quick)

**Features**:
- Cancel button (cancels network request)
- Theme-aware (iOS26ThemeStore)
- Estimated time remaining

---

### Task 1.8: Build ScanResultsView
**File**: `BookshelfScanning/Views/ScanResultsView.swift`
**Layout**:
- Top: Captured image with bounding boxes
- Bottom: ScrollView list of detected books

**Book Row**:
- Title + Author
- Confidence indicator (color-coded)
- Enrichment status (spinner/checkmark/error)
- Cover thumbnail (once enriched)

**Actions**:
- Tap book → `DetectedBookDetailSheet`
- Toolbar: "Add All", "Clear All", "Re-scan"

**Progressive Updates**: Rows update as enrichment completes

---

### Task 1.9: Build DetectedBookDetailSheet
**File**: `BookshelfScanning/Views/DetectedBookDetailSheet.swift`
**Presentation**: Half-sheet (`.presentationDetents([.medium, .large])`)

**Content**:
- Cover image (if enriched)
- Title, Author, Publisher, Year
- Confidence score
- Enrichment status
- Raw OCR text (expandable)

**Actions**:
- "Add to Library" → creates Work + Edition + UserLibraryEntry in SwiftData
- "Search Manually" → opens SearchView with pre-filled query
- "Report Incorrect" (Phase 3)

---

### Task 1.10: Integration & Testing
**Entry Point**: `SettingsView.swift` (or dedicated scan tab)

```swift
Button("Scan Bookshelf (Beta)") {
    showingBookshelfCamera = true
}
.sheet(isPresented: $showingBookshelfCamera) {
    BookshelfCameraView()
}
```

**Complete Flow**:
1. User taps "Scan Bookshelf"
2. Camera permission → BookshelfCameraView
3. Capture photo → ScanProgressView (25-40s)
4. AI results → ScanResultsView (unenriched)
5. Enrichment (background) → progressive updates
6. Tap book → DetectedBookDetailSheet → "Add to Library"
7. Book added to SwiftData → dismiss

---

## Phase 1: Quality Gates (Go/No-Go)

### Build Verification
- [ ] Zero build warnings
- [ ] Zero build errors
- [ ] Swift 6 strict concurrency passes
- [ ] All files have `public` access modifiers (SPM package)

### Unit Tests (Swift Testing)
```swift
@Test func imageCompressionStaysUnder10MB() async throws
@Test func aiServiceParsesValidResponse() async throws
@Test func enrichmentCoordinatorHandlesErrors() async throws
@Test func scanModelStateTransitions() async throws
```

### Simulator Testing
- [ ] Camera permission flow
- [ ] Mock AI responses display
- [ ] Progressive enrichment updates UI
- [ ] Memory <200MB during scan

### Real Device Testing (CRITICAL)
- [ ] Camera capture (iPhone + iPad)
- [ ] Image compression (2-5 MB output)
- [ ] Network upload succeeds
- [ ] 25-40s AI processing (no freeze)
- [ ] Enrichment TaskGroup completes
- [ ] Camera cleanup (no memory leak)

### Accessibility (WCAG AA)
- [ ] Buttons have accessibility labels
- [ ] VoiceOver reads progress states
- [ ] Dynamic Type support
- [ ] Color-coded indicators have text labels

### HIG Compliance
- [ ] Navigation uses push (not sheets) for exploration
- [ ] Loading states are informative
- [ ] Error messages are actionable
- [ ] Camera guidance doesn't overwhelm UI

---

## Phase 2: Interactive Improvements (POST-LAUNCH)

**Goal**: Enhance user interaction with scan results.

### Features
- Interactive bounding boxes (tap to highlight in list)
- Pinch-to-zoom on captured image
- Manual correction (edit title/author)
- Merge duplicate detections
- Delete false positives
- Batch selection ("Add Selected")
- Duplicate detection against existing library

---

## Phase 3: Advanced Features (FUTURE)

**Goal**: Power-user features and feedback loop.

### Features
- Multi-photo scanning (multiple shelves)
- User feedback integration (POST /feedback)
- Offline mode (queue scans)
- Multi-language support
- Rotation detection (vertical spines)

---

## Risk Assessment

### Launch-Blocking (HIGH)

| Risk | Mitigation |
|------|------------|
| Camera hardware exclusivity violation | Single CameraManager instance via dependency injection |
| Memory leak during image processing | autoreleasepool, immediate UIImage release |
| Network timeout (40s AI processing) | 60s timeout, retry button, cancel button |
| Actor isolation deadlock | Follow CLAUDE.md: @MainActor (UI), @CameraSessionActor (camera) |

### Medium Priority

| Risk | Mitigation |
|------|------------|
| AI detection accuracy <80% | Beta labeling, manual correction (Phase 2) |
| Enrichment API failures | Retry logic, manual search fallback |
| Duplicate books in library | Reuse CSVImportService duplicate detection |

### Low Priority

| Risk | Mitigation |
|------|------------|
| Multi-language OCR | Future: language detection in AI prompt |
| Vertical spines | Future: rotation detection |
| Glare/reflections | Camera guidance: "Avoid glare" |

---

## Success Criteria (Phase 1)

**Functional**:
- [ ] User can capture bookshelf photo
- [ ] AI detects visible spines (>80% rate)
- [ ] Results display within 45s
- [ ] High-confidence books enrich
- [ ] User can add books to library

**Performance**:
- [ ] Memory <200MB
- [ ] No memory leaks (5 consecutive scans)
- [ ] UI responsive during AI processing
- [ ] Enrichment completes within 30s (10 books)

**Quality**:
- [ ] Zero build warnings
- [ ] 100% Swift 6 compliance
- [ ] WCAG AA accessibility
- [ ] Real device validation (2+ devices)

---

## Next Steps

1. **Specialist Reviews** (In Progress):
   - ios26-hig-designer: Camera UI, loading states, HIG compliance
   - ask-gemini: Swift 6.1 concurrency architecture
   - mobile-code-reviewer: File structure, access modifiers, tests

2. **Phase 1 Kickoff** (After approvals):
   - Tasks 1.1-1.5 (Models + Services) - parallel development
   - Tasks 1.6-1.9 (Views) - sequential
   - Task 1.10 (Integration) - final assembly

3. **Real Device Testing**: 2-3 days on-device validation

---

**Document Version**: 1.0
**Last Updated**: October 13, 2025
**Status**: Awaiting specialist reviews
