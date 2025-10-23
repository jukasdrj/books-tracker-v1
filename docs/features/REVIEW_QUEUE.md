# Review Queue (Human-in-the-Loop) Feature

**Status:** ✅ Shipped (Build 49+)
**Last Updated:** October 23, 2025
**Related Issues:** #112, #113, #114, #115, #116, #117, #118, #119, #120

---

## Overview

The Review Queue allows users to review and correct AI-detected book metadata from bookshelf scans when the AI confidence is below 60%. This human-in-the-loop workflow ensures data quality while maintaining the speed benefits of automated detection.

**Problem Solved:**
Gemini 2.5 Flash AI can misread book spines due to blur, glare, or unusual fonts. The Review Queue surfaces these low-confidence detections for human verification, preventing incorrect data from entering the library.

---

## User Flow

```
Bookshelf Scan (Gemini AI)
           ↓
   Confidence Check
           ↓
  ├─ ≥60%: Auto-import as .verified
  └─ <60%: Import as .needsReview
           ↓
   User opens Library
           ↓
   Sees Review Queue badge (🔴 indicator)
           ↓
   Taps Review Queue button
           ↓
   Views list of books needing review
           ↓
   Taps book → CorrectionView
           ↓
   Sees cropped spine image + edit fields
           ↓
   ├─ Edits title/author → Saves → .userEdited
   └─ No changes → Mark as Verified → .verified
           ↓
   Book removed from queue
           ↓
   All books reviewed → Image cleanup on next launch
```

---

## Architecture

### Data Model

**ReviewStatus Enum:**
```swift
public enum ReviewStatus: String, Codable, Sendable {
    case verified       // AI or user confirmed accuracy
    case needsReview    // Low confidence (< 60%)
    case userEdited     // Human corrected AI result
}
```

**Work Model Extensions:**
```swift
@Model
public class Work {
    // Review workflow properties
    public var reviewStatus: ReviewStatus = .verified
    public var originalImagePath: String?  // Temp file path
    public var boundingBox: CGRect?        // Normalized (0.0-1.0)
}
```

**DetectedBook:**
```swift
public struct DetectedBook {
    public var confidence: Double
    public var boundingBox: CGRect
    public var originalImagePath: String?

    // Computed property
    public var needsReview: Bool {
        confidence < 0.60  // 60% threshold
    }
}
```

### Components

| Component | Responsibility | Lines of Code |
|-----------|---------------|---------------|
| **ReviewQueueModel** | State management, queue loading | 93 |
| **ReviewQueueView** | Queue list UI, navigation | 315 |
| **CorrectionView** | Editing interface with image cropping | 310 |
| **ImageCleanupService** | Automatic temp file cleanup | 145 |

**Total:** ~863 lines of production code

---

## Key Features

### 1. Automatic Queue Population

**Trigger:** ScanResultsView import (BookshelfScanning/ScanResultsView.swift:545-550)

```swift
// Set review status based on confidence threshold
work.reviewStatus = detectedBook.needsReview ? .needsReview : .verified

// Store image metadata for correction UI
work.originalImagePath = detectedBook.originalImagePath
work.boundingBox = detectedBook.boundingBox
```

### 2. Visual Queue Indicator

**Location:** iOS26LiquidLibraryView toolbar (iOS26LiquidLibraryView.swift:91-109)

```swift
Button {
    showingReviewQueue.toggle()
} label: {
    ZStack(alignment: .topTrailing) {
        Image(systemName: "exclamationmark.triangle")

        if reviewQueueCount > 0 {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: 4, y: -4)
        }
    }
}
.foregroundStyle(reviewQueueCount > 0 ? .orange : .primary)
```

### 3. Image Cropping

**Algorithm:** (CorrectionView.swift:209-236)

```swift
// Convert normalized coordinates to pixel coordinates
let imageWidth = CGFloat(cgImage.width)
let imageHeight = CGFloat(cgImage.height)

let cropRect = CGRect(
    x: boundingBox.origin.x * imageWidth,
    y: boundingBox.origin.y * imageHeight,
    width: boundingBox.width * imageWidth,
    height: boundingBox.height * imageHeight
)

guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
    return nil
}

return UIImage(cgImage: croppedCGImage)
```

### 4. Automatic Cleanup

**Trigger:** App launch (ContentView.swift:71-74)

```swift
.task {
    // Clean up temporary scan images after all books reviewed
    await ImageCleanupService.shared.cleanupReviewedImages(in: modelContext)
}
```

**Logic:** (ImageCleanupService.swift:42-68)
- Groups works by `originalImagePath`
- Checks if all books from scan are `.verified` or `.userEdited`
- Deletes image file and clears Work references
- Saves ModelContext changes

---

## Analytics Events

| Event | Properties | Trigger |
|-------|-----------|---------|
| `review_queue_viewed` | `queue_count` | Queue opened |
| `review_queue_correction_saved` | `had_title_change`, `had_author_change` | User saves edits |
| `review_queue_verified_without_changes` | None | User verifies without editing |

**Current Implementation:** Placeholder print statements (📊 Analytics: event_name)
**TODO:** Replace with Firebase Analytics or Mixpanel SDK

---

## iOS 26 Design Compliance

### Liquid Glass Styling

- ✅ `.ultraThinMaterial` backgrounds on all cards
- ✅ `themeStore.backgroundGradient` full-screen backdrop
- ✅ `themeStore.primaryColor` for action buttons
- ✅ 16pt corner radius (standard)
- ✅ 8pt shadow on spine images

### Accessibility (WCAG AA)

- ✅ System semantic colors (`.primary`, `.secondary`, `.tertiary`)
- ✅ VoiceOver labels on all interactive elements
- ✅ Orange warning color for review badge (4.5:1+ contrast)
- ✅ Keyboard toolbar for number pad (page count fields)

### Known HIG Concerns

See Issue #120 for toolbar button design review:
- Visual hierarchy (all 3 buttons equal weight)
- Semantic grouping (alert vs info vs preference)
- Badge visibility (8pt red dot may be too small)

---

## Performance Metrics

| Metric | Value | Note |
|--------|-------|------|
| Confidence Threshold | 60% | Balances automation vs accuracy |
| Image Cleanup Delay | App relaunch | Ensures all books reviewed |
| Queue Load Time | <100ms | In-memory filtering (no predicates) |
| Image Crop Time | <50ms | CGImage operation, async |

**SwiftData Limitation:** Enum case comparison not supported in predicates
**Solution:** Fetch all works, filter in-memory with `.filter { $0.reviewStatus == .needsReview }`

---

## Testing Strategy

### Unit Testing

**Recommended Tests:**
```swift
@Test func lowConfidenceBooksFlaggedForReview() {
    let detected = DetectedBook(confidence: 0.55, ...)
    #expect(detected.needsReview == true)
}

@Test func highConfidenceBooksBypassReview() {
    let detected = DetectedBook(confidence: 0.85, ...)
    #expect(detected.needsReview == false)
}

@Test func imageCleanupOnlyAfterAllBooksReviewed() async {
    // Create 3 works with same imagePath
    // Mark 2 as .verified, 1 as .needsReview
    // Run cleanup
    // #expect(imageExists == true)
}
```

### Manual Testing Checklist

- [ ] Scan bookshelf with mix of high/low confidence books
- [ ] Verify Review Queue badge appears in Library toolbar
- [ ] Tap Review Queue → See list of books needing review
- [ ] Tap book → CorrectionView shows cropped spine image
- [ ] Edit title → Save → Book marked as `.userEdited`
- [ ] No edits → Verify → Book marked as `.verified`
- [ ] Book disappears from queue after action
- [ ] Relaunch app → Image cleanup runs (check console logs)
- [ ] Test across all 5 themes (liquidBlue, cosmicPurple, etc.)
- [ ] VoiceOver navigation works correctly

---

## Common Issues & Solutions

### Issue: "Could not cast value to ReviewStatus"

**Cause:** Existing database doesn't have `reviewStatus` column
**Solution:** Uninstall app to reset database (simulator only)

```bash
xcrun simctl uninstall <UDID> Z67H8Y8DW.com.oooefam.booksV3
```

### Issue: Images not deleting after review

**Check:** Console logs on app launch
```
✅ ImageCleanupService: Deleted <path> (3 books reviewed)
🧹 ImageCleanupService: Cleaned up 1 image(s), 0 error(s)
```

**Debug:**
- Verify all books from scan are `.verified` or `.userEdited`
- Check `ImageCleanupService.getActiveImageCount()` returns 0
- Ensure file permissions allow deletion

### Issue: Review Queue always shows 0

**Check:** Import logic in `ScanResultsView.addAllToLibrary()`
```swift
work.reviewStatus = detectedBook.needsReview ? .needsReview : .verified
```

Verify `DetectedBook.confidence < 0.60` for low-confidence books.

---

## Future Enhancements

### Planned (Backlog)

1. **Batch Review Mode** - Swipe through multiple books without dismissing
2. **Confidence Score Display** - Show AI confidence % in CorrectionView
3. **Manual Recrop** - Adjust bounding box if AI cropped incorrectly
4. **Review History** - Track accuracy improvements over time
5. **Smart Suggestions** - Offer alternatives from OpenLibrary API

### Considered (Deferred)

- Auto-retry with OpenLibrary API for low-confidence detections
- ML model retraining based on user corrections
- Bulk verify (mark all as verified without individual review)

---

## Related Documentation

- **Bookshelf Scanner:** `docs/features/BOOKSHELF_SCANNER.md`
- **SwiftData Guide:** `docs/CONCURRENCY_GUIDE.md`
- **iOS 26 HIG:** CLAUDE.md "iOS 26 Liquid Glass Design System"
- **API Contracts:** `docs/API.md` (Gemini 2.5 Flash integration)

---

## Changelog

**Build 49 (October 23, 2025):**
- ✅ Core workflow implementation (Issues #112-115)
- ✅ ImageCleanupService automatic cleanup (#116)
- ✅ iOS 26 Liquid Glass styling (#117)
- ✅ Analytics placeholder events (#118)
- ✅ Feature documentation (#119)
- ⏳ Toolbar button HIG review (#120) - Pending ios26-hig-designer

**Build 48 (October 17, 2025):**
- Added `reviewStatus`, `originalImagePath`, `boundingBox` to Work model
- Added `needsReview` computed property to DetectedBook

---

**Maintainers:** @jukasdrj
**Status:** Production-ready, pending HIG review (#120)
