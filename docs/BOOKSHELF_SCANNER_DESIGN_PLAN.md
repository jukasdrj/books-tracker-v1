# Bookshelf Scanner - iOS 26 UI/UX Design Plan
**BooksTracker v3.0+** | **iOS 26.0+** | **Liquid Glass Design System**
**Created:** October 12, 2025

---

## 🎯 Executive Summary

This document specifies the complete UI/UX design for BooksTracker's AI-powered bookshelf scanning feature. The design balances technical constraints (30-40s AI processing time) with iOS 26 HIG best practices to create a delightful, accessible user experience.

**Key Design Principles:**
- **Proactive Guidance:** Help users capture optimal photos before upload
- **Engaging Wait Experience:** Make 30-40s feel faster with progressive feedback
- **Familiar Patterns:** Leverage iOS 26 conventions (Live Text, Visual Look Up)
- **Full Control:** Users can correct AI mistakes and manage confidence levels
- **Accessibility First:** VoiceOver, Dynamic Type, WCAG AA contrast throughout

---

## 📱 User Flow Overview

```
Settings Menu
    ↓
[Tap "Scan Bookshelf"]
    ↓
Sheet Presents: Camera Interface
    ├─ Framing guide overlay
    ├─ Real-time quality feedback
    └─ Level/tilt indicator
    ↓
[Capture Photo]
    ↓
Processing View (30-40s)
    ├─ Dimmed photo with animated bounding boxes
    ├─ Live Activity + Dynamic Island
    └─ Educational tips carousel
    ↓
Results View
    ├─ Interactive photo overlay (tap boxes)
    ├─ Toggle to list view
    └─ Bulk actions (Add All/Clear All)
    ↓
[User adds books to library]
    ↓
Sheet Dismisses → Return to Settings
```

---

## 🎨 Phase 1: Camera Capture Interface

### Screen: BookshelfCameraView

**Layout:**
```
┌─────────────────────────────────────┐
│  [×] Close          [Grid Toggle]   │ ← Navigation bar
│                                     │
│  ┌───────────────────────────────┐ │
│  │                               │ │
│  │   ╔═══════════════════════╗   │ │ ← Framing guide (semi-transparent)
│  │   ║                       ║   │ │   "Align bookshelf within frame"
│  │   ║                       ║   │ │
│  │   ║   [Live Preview]      ║   │ │
│  │   ║                       ║   │ │
│  │   ║                       ║   │ │
│  │   ╚═══════════════════════╝   │ │
│  │                               │ │
│  └───────────────────────────────┘ │
│                                     │
│  ─────── Level Indicator ───────   │ ← Tilt feedback (turns green when level)
│  🌙 More light needed               │ ← Quality warnings (conditional)
│  📷 Hold steady                     │
│                                     │
│         [🔘 Capture]                │ ← Shutter button (large, accessible)
│                                     │
└─────────────────────────────────────┘
```

### Design Elements

**1. Framing Guide Overlay**
- Semi-transparent rectangle (40% screen width, 60% height)
- Color: Theme primary color @ 30% opacity
- Material: `.ultraThinMaterial` with `.blendMode(.overlay)`
- Instructional text: "Align bookshelf within frame" (fades out after 3s)
- Aspect ratio: 4:3 (matches optimal AI input)

**2. Level/Tilt Indicator**
- Two-line indicator (like Apple Camera app)
- White lines turn yellow → green when device is level
- Uses Core Motion (CMMotionManager) for real-time angle detection
- Haptic feedback: `.selectionChanged` when level achieved
- VoiceOver: "Device is level" / "Tilt left" / "Tilt right"

**3. Real-time Quality Feedback**
- Small, non-blocking icons near shutter button
- **Moon icon** 🌙: "More light needed" (when ISO > 1000 or lux < 50)
- **Shaky hand** 📷: "Hold steady" (when motion > threshold)
- **Focus ring**: Animates when tap-to-focus completes
- Icons use `.secondary` foreground color for subtlety

**4. Grid Toggle**
- Standard 3x3 grid overlay (optional)
- Toggle button in top-right: SF Symbol "square.grid.3x3"
- Persists preference via `@AppStorage`

**5. Shutter Button**
- Large circular button (80pt diameter)
- Theme primary color with glass effect
- Disabled state when quality warnings active
- VoiceOver label: "Capture bookshelf photo"

### Camera Configuration

**AVFoundation Settings:**
```swift
// High-resolution photo capture
photoSettings.isHighResolutionPhotoEnabled = true
photoSettings.photoQualityPrioritization = .quality

// Session preset
captureSession.sessionPreset = .photo

// Focus mode
device.focusMode = .continuousAutoFocus
device.exposureMode = .continuousAutoExposure
```

**Quality Validation (Pre-Capture):**
- Brightness check: ISO < 1500, exposure duration reasonable
- Sharpness: Motion sensor variance < threshold
- Level check: Device angle within ±5° of vertical/horizontal

### Accessibility

- **VoiceOver**: Full camera control via custom accessibility actions
  - "Capture photo"
  - "Toggle grid"
  - "Close camera"
- **Haptics**: Level achieved, photo captured
- **Dynamic Type**: All text scales appropriately
- **Reduced Motion**: Disable framing guide animations

---

## ⏳ Phase 2: AI Processing View

### Screen: BookshelfProcessingView

**Layout:**
```
┌─────────────────────────────────────┐
│      Analyzing Your Bookshelf       │ ← Title
│                                     │
│  ┌───────────────────────────────┐ │
│  │                               │ │
│  │   [Captured Photo - Dimmed]   │ │ ← Original photo @ 70% opacity
│  │                               │ │
│  │   ╔═══╗ ╔═══╗                 │ │ ← Bounding boxes animate in
│  │   ║ 1 ║ ║ 2 ║ ...             │ │   as AI finds books
│  │   ╚═══╝ ╚═══╝                 │ │
│  │                               │ │
│  └───────────────────────────────┘ │
│                                     │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │ ← Progress bar (indeterminate)
│  Found 5 of ~15 books...            │ ← Live count update
│                                     │
│  ✨ Tip: Well-lit photos help AI    │ ← Educational tip (rotates every 5s)
│     find more books accurately      │
│                                     │
│  [Cancel Upload]                    │ ← Escape hatch (bottom)
└─────────────────────────────────────┘
```

### Design Elements

**1. Dimmed Photo Display**
- Original captured photo at 70% opacity
- Positioned at top of screen (maintains aspect ratio)
- `.overlay` modifier with `.background(.black.opacity(0.3))`

**2. Animated Bounding Boxes**
- Boxes appear one-by-one as AI detects books
- Animation: `.spring(response: 0.6, dampingFraction: 0.8)`
- Color: Theme primary color with glow effect
- Each box includes a small number label (1, 2, 3...)
- VoiceOver announces: "Detected book 3: [Title]"

**3. Progress Indicator**
- Indeterminate progress bar at start
- Switches to determinate when book count stabilizes
- Text updates: "Found X of ~Y books..."
- VoiceOver updates every 5 books detected

**4. Educational Tips Carousel**
- Rotates through 5-7 tips/facts every 5 seconds
- Examples:
  - "✨ Tip: Well-lit photos help AI find more books"
  - "📚 Did you know? The Library of Congress holds 173 million items"
  - "🎯 Best results: Hold phone straight-on at bookshelf"
- Fade transition animation
- VoiceOver reads tips as they appear

**5. Cancel Button**
- Secondary button style (outlined, not filled)
- Alert confirmation: "Are you sure? Processing will stop."
- VoiceOver: "Cancel upload and return to camera"

### Live Activity Integration

**Dynamic Island (iPhone 15+):**
```
┌──────────────────────────────┐
│  📚 [Progress Ring]  5/15    │ ← Minimal compact view
└──────────────────────────────┘

┌──────────────────────────────┐
│  📚 Scanning Bookshelf       │ ← Expanded view
│  [Photo Thumbnail]           │
│  ━━━━━━━━━ 33%              │
│  Found 5 of ~15 books...     │
└──────────────────────────────┘
```

**Lock Screen Widget:**
```
┌────────────────────────────────────┐
│  📚 BooksTracker - Scanning        │
│  ┌──────────┐                      │
│  │  [Photo] │  Found 5 of ~15 books│
│  │  Thumb   │  ━━━━━━━━━ 33%      │
│  └──────────┘                      │
│  Tap to open →                     │
└────────────────────────────────────┘
```

**Implementation:**
- Use ActivityKit framework (iOS 16.1+)
- Update every time a book is detected (max 50 updates/hour)
- Deep link opens app to processing view
- Auto-dismisses when complete or after 60s timeout

### Accessibility

- **VoiceOver**: Progress announcements every 5 books
- **Haptics**: Subtle tap when each book detected (if enabled)
- **Reduced Motion**: Disable bounding box spring animations
- **Dynamic Type**: All text scales

---

## 🎉 Phase 3: Interactive Results View

### Screen: BookshelfResultsView

**Layout (Photo Overlay Mode):**
```
┌─────────────────────────────────────┐
│  [<] Back     Results     [List]    │ ← Navigation + view toggle
│                                     │
│  ┌───────────────────────────────┐ │
│  │                               │ │
│  │   ╔═══╗ ╔═══╗ ╔═══╗          │ │ ← Tappable bounding boxes
│  │   ║ 1 ║ ║ 2 ║ ║ 3 ║          │ │   Solid = high confidence
│  │   ╚═══╝ ╚═══╝ ╚═══╝          │ │   Dashed = low confidence
│  │                               │ │
│  │   ╔═══╗ ╔═══╗ ╔═══╗          │ │
│  │   ║ 4 ║ ║ 5 ║ ║ 6?║          │ │ ← Question mark = uncertain
│  │   ╚═══╝ ╚═══╝ ╚═══╝          │ │
│  │                               │ │
│  └───────────────────────────────┘ │
│                                     │
│  Found 13 books • 11 high confidence│ ← Summary stats
│                                     │
│  [Add All (13)]  [Clear All]       │ ← Bulk actions
└─────────────────────────────────────┘
```

**Layout (List View Mode):**
```
┌─────────────────────────────────────┐
│  [<] Back     Results     [Photo]   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [Cover] The Great Gatsby    │   │ ← Book row (high confidence)
│  │         F. Scott Fitzgerald │   │
│  │         ✓ Added             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [Cover] 1984                │   │
│  │         George Orwell       │   │
│  │         [+ Add]             │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ [?]     Unknown Title       │   │ ← Low confidence (dashed border)
│  │         Unknown Author      │   │
│  │         ⚠️ Review            │   │
│  └─────────────────────────────┘   │
│                                     │
│  [Add All (13)]  [Clear All]       │
└─────────────────────────────────────┘
```

### Design Elements

**1. Bounding Box Interactions**

**High Confidence (≥0.7):**
- Solid border (3pt stroke)
- Theme primary color
- Tap → half-sheet with book details

**Medium Confidence (0.4-0.7):**
- Solid border with slightly lower opacity (70%)
- Small ⚠️ warning icon in corner
- Tap → half-sheet with "Review this detection" banner

**Low Confidence (<0.4):**
- Dashed border (3pt stroke, [6, 4] dash pattern)
- Question mark icon (❓) in corner
- Lower opacity (50%)
- Tap → half-sheet with prominent "Uncertain Detection" warning

**Tap Animation:**
- Scale effect: `.scaleEffect(tapped ? 1.05 : 1.0)`
- Haptic: `.impact(.medium)`
- Half-sheet slides up from bottom

**2. Book Detail Half-Sheet**

```
┌─────────────────────────────────────┐
│       ━━━━━━━━━                     │ ← Drag handle
│                                     │
│  ┌─────────┐                        │
│  │ [Cover] │  The Great Gatsby      │ ← AsyncImage + metadata
│  │ Image   │  by F. Scott Fitzgerald│
│  └─────────┘  Scribner • 1925      │
│               180 pages             │
│                                     │
│  ⭐️⭐️⭐️⭐️⭐️ 4.5 (1.2M ratings)      │ ← Optional: API-enriched data
│                                     │
│  [✓ Added to Library]              │ ← Primary action
│                                     │
│  [Edit Details]  [❌ Not a Book]    │ ← Secondary actions
└─────────────────────────────────────┘
```

**Sheet Content:**
- **Cover Image**: `AsyncImage` with placeholder → search API
- **Metadata**: Title (`.title`), Author (`.body`), Publisher/Year (`.caption`)
- **Rating** (optional): From Google Books API enrichment
- **Actions**:
  - Primary: "Add to Library" (filled button, theme color)
  - Secondary: "Edit Details" (outlined button)
  - Destructive: "Not a Book" (trash icon, red color)

**States:**
- **Not Added**: "Add to Library" button
- **Added**: "✓ Added to Library" (checkmark, disabled)
- **Low Confidence**: "⚠️ Review Detection" banner at top

**3. View Toggle (Photo ↔ List)**

- Segmented control in navigation bar
- SF Symbols: "photo" / "list.bullet"
- Smooth transition animation (`.transition(.opacity)`)
- State persists during session
- VoiceOver: "Switch to list view" / "Switch to photo view"

**4. List View Rows**

**Standard Row:**
```swift
HStack(spacing: 12) {
    AsyncImage(url: coverURL) // 60x90pt
        .frame(width: 60, height: 90)
        .cornerRadius(6)

    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundColor(.primary)
        Text(author)
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    Spacer()

    // State indicator or action button
    addedCheckmark or addButton
}
.padding()
.background(Material.thin)
```

**Low Confidence Row:**
- Dashed border (`.overlay(DashedRoundedRectangle())`)
- ⚠️ icon before title
- "Review" button instead of "Add"

**5. Bulk Actions**

- Fixed bottom bar with two buttons
- **Add All**: Adds all high-confidence books (≥0.7) to library
  - Shows count: "Add All (11)" if 11 high-confidence
  - Confirmation alert if >20 books
  - VoiceOver: "Add 11 books to library"
- **Clear All**: Removes all detections and returns to camera
  - Confirmation alert: "Discard 13 detected books?"
  - Destructive action style

**6. Summary Stats**

- Below photo/list: "Found 13 books • 11 high confidence • 2 need review"
- Updates dynamically as user adds/removes books
- `.caption` font size, `.secondary` color
- VoiceOver reads full summary

### Accessibility

**VoiceOver:**
- Each bounding box: "Book 1: [Title] by [Author]. High confidence. Tap to view details."
- Low confidence: "Book 3: Uncertain detection. May need review. Tap to view."
- List rows: "The Great Gatsby by F. Scott Fitzgerald. Not added. Double-tap to add."
- Actions clearly labeled with hints

**Dynamic Type:**
- All text scales (test at Accessibility sizes)
- Book covers maintain aspect ratio, adapt spacing

**Contrast:**
- Bounding boxes: 4.5:1 against photo (use theme color with sufficient luminance)
- Text: `.primary` and `.secondary` guarantee WCAG AA
- Buttons: Minimum 44x44pt touch targets

**Reduced Motion:**
- Disable spring animations on boxes
- Use `.transition(.opacity)` instead of scale effects

---

## 🎨 Liquid Glass Theme Integration

### Theme-Aware Colors

All UI elements adapt to the current theme (liquidBlue, cosmicPurple, forestGreen, sunsetOrange, moonlightSilver):

```swift
@Environment(iOS26ThemeStore.self) private var themeStore

// Bounding boxes
.stroke(themeStore.primaryColor, lineWidth: 3)

// Buttons
.background(themeStore.primaryColor.gradient)

// Overlays
.background(.ultraThinMaterial)
```

### Liquid Glass Effects

**Framing Guide:**
```swift
RoundedRectangle(cornerRadius: 16)
    .stroke(themeStore.primaryColor, lineWidth: 2)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(themeStore.primaryColor.opacity(0.1))
            .background(.ultraThinMaterial)
            .blendMode(.overlay)
    )
```

**Processing View Background:**
```swift
Color.black.opacity(0.3)
    .background(.thinMaterial)
```

**Result Cards (List View):**
```swift
.background(Material.thin)
.overlay {
    RoundedRectangle(cornerRadius: 12)
        .stroke(themeStore.primaryColor.opacity(0.2), lineWidth: 1)
}
```

### Typography

- **Title**: `.title2` (22pt, semibold)
- **Body**: `.body` (17pt, regular)
- **Caption**: `.caption` (12pt, regular)
- **Buttons**: `.headline` (17pt, semibold)

All use SF Pro system font with automatic weight adjustments for Dark Mode.

---

## 🚨 Error States & Edge Cases

### Error Scenarios

**1. Camera Permission Denied**
```
┌─────────────────────────────────────┐
│                                     │
│         📷                          │
│                                     │
│  Camera Access Required             │
│                                     │
│  BooksTracker needs camera access   │
│  to scan your bookshelf.            │
│                                     │
│  [Open Settings]                    │
│                                     │
└─────────────────────────────────────┘
```

**2. Poor Image Quality (Pre-Upload)**
```
Alert:
  Title: "Photo Quality Issue"
  Message: "This photo is too dark/blurry for good results. Retake in better lighting?"
  Actions: [Retake] [Use Anyway]
```

**3. AI Processing Failed**
```
┌─────────────────────────────────────┐
│         ⚠️                          │
│                                     │
│  Scanning Failed                    │
│                                     │
│  We couldn't analyze this photo.    │
│  Try taking another in better       │
│  lighting with clear book spines.   │
│                                     │
│  [Retake Photo]  [Cancel]          │
└─────────────────────────────────────┘
```

**4. No Books Detected**
```
┌─────────────────────────────────────┐
│         📚                          │
│                                     │
│  No Books Found                     │
│                                     │
│  We couldn't find any books in      │
│  this photo. Tips:                  │
│  • Ensure book spines are visible   │
│  • Take photo straight-on           │
│  • Use good lighting                │
│                                     │
│  [Retake Photo]  [Cancel]          │
└─────────────────────────────────────┘
```

**5. Network Error**
```
Alert:
  Title: "Upload Failed"
  Message: "Check your internet connection and try again."
  Actions: [Retry] [Cancel]
```

### User Guidance

**First-Time Experience:**
- Show a brief tutorial overlay on first launch
- Highlight framing guide: "Align your bookshelf here"
- Explain level indicator: "Keep phone straight for best results"
- Dismissible with "Got It" button
- Never show again (stored in `@AppStorage`)

**Help Button:**
- Small "?" button in navigation bar
- Presents sheet with:
  - Photo tips (lighting, angle, distance)
  - Example photos (good vs bad)
  - FAQ (processing time, accuracy, privacy)

---

## ♿️ Accessibility Deep Dive

### VoiceOver Navigation

**Camera View:**
1. "Close button"
2. "Grid toggle button"
3. "Level indicator: Device is level" (dynamic)
4. "Quality warning: More light needed" (conditional)
5. "Capture button: Capture bookshelf photo"

**Processing View:**
6. "Processing image. Found 5 of approximately 15 books."
7. "Tip: Well-lit photos help AI find more books."
8. "Cancel button: Cancel upload"

**Results View (Photo Mode):**
9. "Back button"
10. "Switch to list view button"
11. "Book 1: The Great Gatsby by F. Scott Fitzgerald. High confidence. Tap to view details."
12. "Book 2: 1984 by George Orwell. High confidence. Already added to library."
13. "Book 3: Unknown title. Low confidence. Tap to review."
14. "Summary: Found 13 books, 11 high confidence, 2 need review"
15. "Add all 11 books button"
16. "Clear all detections button"

**Results View (List Mode):**
9-14. Individual book rows with clear labels and states
15-16. Same bulk action buttons

### Custom Accessibility Actions

**On Bounding Boxes:**
- Default: "Double-tap to view details"
- Custom actions:
  - "Add to library" (if not added)
  - "Remove from library" (if added)
  - "Mark as not a book"

**On List Rows:**
- Default: "Double-tap to view details"
- Custom actions: Same as bounding boxes

### Reduced Motion

- Disable spring animations
- Disable floating/pulsing effects
- Use crossfade transitions only
- Maintain spatial relationships

### Dynamic Type

- Test at all accessibility sizes (XS → XXXL)
- Multi-line text wraps properly
- Buttons scale to fit text
- Minimum touch targets: 44x44pt

### Color Accessibility

**Contrast Ratios (WCAG AA):**
- Text on background: ≥4.5:1 (body text), ≥3:1 (large text)
- Bounding boxes on photo: ≥3:1 (non-text UI)

**Color Blind Safe:**
- Don't rely on color alone for confidence indicators
- Use shapes/icons: solid box (high), dashed box (low), question mark (uncertain)
- Test with Color Blindness simulators

---

## 🧪 Testing Checklist

### Device Coverage

- **iPhone:** 15 Pro Max, 15 Pro, 15, SE (small screen)
- **iPad:** Pro 12.9", Air 11", Mini
- **Orientations:** Portrait (primary), Landscape (camera/results)

### Environmental Conditions

**Lighting:**
- ✅ Well-lit room (office, daytime)
- ✅ Dim lighting (evening, ambient light)
- ✅ Mixed lighting (window + lamp)
- ✅ Backlit shelves (window behind books)
- ⚠️ Very dark (should warn user)

**Bookshelf Scenarios:**
- ✅ Standard shelf (3-4 rows, clear spines)
- ✅ Dense shelf (15+ books)
- ✅ Sparse shelf (3-5 books)
- ✅ Mixed orientations (horizontal + vertical)
- ✅ Partial visibility (books at angle)
- ⚠️ Empty shelf (should detect 0 books)

**Camera Angles:**
- ✅ Straight-on (ideal)
- ✅ Slight angle (±15°)
- ⚠️ Extreme angle (±45°, should warn)

### Accessibility Testing

- ✅ VoiceOver full flow (Settings → Camera → Results → Add)
- ✅ Dynamic Type at max size (XXXL)
- ✅ Reduced Motion enabled
- ✅ Increase Contrast enabled
- ✅ Color Blindness simulation (protanopia, deuteranopia, tritanopia)

### Performance

- ✅ Camera preview runs at 60fps
- ✅ Real-time quality indicators update smoothly
- ✅ Bounding box animations don't stutter
- ✅ Live Activity updates reliably
- ✅ Memory usage <200MB during processing

### Error Handling

- ✅ Camera permission denied → Settings prompt
- ✅ Upload fails → Retry option
- ✅ AI timeout (>60s) → Error message
- ✅ No books detected → Helpful guidance
- ✅ Network offline → Queue for later (future)

---

## 📝 Implementation Notes

### Swift Concurrency Patterns

**Camera Setup:**
```swift
@MainActor
class BookshelfCameraViewModel: ObservableObject {
    @Published var isLevelHorizontal = false
    @Published var isLevelVertical = false
    @Published var lightingQuality: LightingQuality = .good

    private let cameraManager: CameraManager
    private let motionManager = CMMotionManager()

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        startMotionUpdates()
        startQualityMonitoring()
    }

    func startMotionUpdates() {
        Task {
            for await attitude in motionManager.deviceAttitudeStream {
                await updateLevelIndicators(attitude)
            }
        }
    }
}
```

**Processing with Live Activity:**
```swift
@MainActor
func processBookshelfImage(_ image: UIImage) async throws -> [DetectedBook] {
    // Start Live Activity
    let activity = try Activity<BookshelfScanAttributes>.request(
        attributes: BookshelfScanAttributes(photoData: imageData),
        contentState: BookshelfScanAttributes.ContentState(
            detectedCount: 0,
            estimatedTotal: 15
        )
    )

    // Upload and process
    let results = try await uploadToAIWorker(image)

    // Update Live Activity with each detection
    for (index, book) in results.enumerated() {
        await activity.update(
            using: BookshelfScanAttributes.ContentState(
                detectedCount: index + 1,
                estimatedTotal: results.count
            )
        )
        // Animate bounding box on screen
        await animateBoundingBox(book.boundingBox)
    }

    // End Live Activity
    await activity.end(dismissalPolicy: .immediate)

    return results
}
```

**List vs Photo View Toggle:**
```swift
enum ResultsViewMode {
    case photo, list
}

struct BookshelfResultsView: View {
    @State private var viewMode: ResultsViewMode = .photo

    var body: some View {
        NavigationStack {
            Group {
                switch viewMode {
                case .photo:
                    PhotoOverlayView(books: detectedBooks)
                case .list:
                    BookListView(books: detectedBooks)
                }
            }
            .animation(.easeInOut, value: viewMode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("View Mode", selection: $viewMode) {
                        Label("Photo", systemImage: "photo")
                            .tag(ResultsViewMode.photo)
                        Label("List", systemImage: "list.bullet")
                            .tag(ResultsViewMode.list)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}
```

### AVFoundation Quality Settings

```swift
// High-resolution capture configuration
let photoSettings = AVCapturePhotoSettings()
photoSettings.isHighResolutionPhotoEnabled = true
photoSettings.photoQualityPrioritization = .quality

// JPEG compression for AI processing
photoSettings.photoQualityPrioritization = .balanced // Trade-off for upload speed

// Optimal session preset
captureSession.sessionPreset = .photo // Highest resolution
```

### Live Activity Configuration

**Attributes (Static):**
```swift
struct BookshelfScanAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var detectedCount: Int
        var estimatedTotal: Int
    }

    var photoThumbnail: Data? // Small JPEG for widget
}
```

**ActivityKit Request:**
```swift
let activity = try Activity<BookshelfScanAttributes>.request(
    attributes: BookshelfScanAttributes(
        photoThumbnail: compressedImageData
    ),
    contentState: BookshelfScanAttributes.ContentState(
        detectedCount: 0,
        estimatedTotal: 15
    ),
    pushType: nil
)
```

---

## 🎯 Success Metrics

**User Experience:**
- **Task Completion Rate:** >90% of users successfully scan and add books
- **Retry Rate:** <20% of scans require retake
- **Time to First Result:** <35 seconds (P95)
- **User Satisfaction:** >4.5/5 stars in feedback

**Technical:**
- **Detection Accuracy:** >90% of visible books detected
- **False Positive Rate:** <5% non-books detected
- **App Responsiveness:** Camera preview never drops below 30fps
- **Crash-Free Rate:** >99.9% during scanning flow

**Accessibility:**
- **VoiceOver Completion:** >95% of VoiceOver users complete flow
- **Dynamic Type Support:** UI remains usable at XXXL size
- **Color Contrast:** 100% WCAG AA compliance

---

## 🚀 Future Enhancements (Post-v1)

### Phase 2 Features

**1. Batch Scanning (Multi-Shelf)**
- Capture multiple photos in sequence
- Aggregate results from all photos
- Deduplicate across scans

**2. Manual Correction Mode**
- Long-press on photo to draw custom bounding box
- Add books the AI missed
- Adjust existing bounding boxes

**3. Offline Queue**
- Scan photos offline
- Upload and process when network available
- Background fetch for results

**4. Smart Recommendations**
- "You scanned [Genre] books. Try these..."
- Series detection: "You have books 1-3 of [Series]. Missing book 4?"

**5. Export/Share**
- Share detected book list as text/CSV
- Generate shareable image with detected books highlighted

### Long-Term Vision

- **AR Mode:** Real-time book detection with live overlay
- **Multi-Language Support:** OCR for non-English titles
- **Library Analytics:** "You scanned 150 books this year!"
- **Social Features:** Compare scanned libraries with friends

---

## 📚 References

**Apple Documentation:**
- [AVFoundation Camera Capture](https://developer.apple.com/documentation/avfoundation/capture-setup)
- [ActivityKit Live Activities](https://developer.apple.com/documentation/activitykit)
- [VoiceOver Best Practices](https://developer.apple.com/accessibility/voiceover/)
- [iOS 26 Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

**WWDC Sessions:**
- WWDC 2025: Enhancing your camera experience with capture controls
- WWDC 2023: Create a more responsive camera experience
- WWDC 2021: Capture high-quality photos using video formats

**Internal Documentation:**
- `/docs/BOOKSHELF_SCANNING_API_ARCHITECTURE.md` - Backend API design
- `/docs/BOOKSHELF_SCANNING_EXECUTIVE_SUMMARY.md` - Quick reference
- `CLAUDE.md` - BooksTracker development standards

---

**Document Status:** ✅ Complete - Ready for Implementation
**Next Steps:** Review with team → Prototype camera view → Test with real bookshelves
**Estimated Implementation:** 2-3 sprints (camera: 1 week, processing: 1 week, results: 1 week)
