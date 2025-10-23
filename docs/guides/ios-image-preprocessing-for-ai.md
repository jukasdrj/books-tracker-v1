# iOS Image Preprocessing for AI Vision Models

**Last Updated:** October 22, 2025
**Related:** Bookshelf Scanner, CloudflareProvider, GeminiProvider

---

## Overview

This guide documents recommended image preprocessing steps for the iOS app to optimize AI vision model performance (Gemini 2.5 Flash and Llama 3.2 11B Vision).

## Current Implementation

**Location:** `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Camera/BookshelfCameraSessionManager.swift`

**Current preprocessing:**
- JPEG compression to ~200-500KB
- Resolution: Up to 4032x3024 (12MP, iPhone native)
- Quality: Auto-determined by iOS compression

## Recommended Optimizations

### For Cloudflare Workers AI (Llama 3.2 Vision)

**Resolution:**
- **Target:** 1536x1536 max (recommended for Llama 3.2)
- **Why:** Llama 3.2 processes faster at 1.5K resolution vs 4K, with minimal accuracy loss
- **Implementation:** Resize longer dimension to 1536px, preserve aspect ratio

```swift
extension UIImage {
    func resizeForAI(maxDimension: CGFloat = 1536) -> UIImage {
        let scale = maxDimension / max(size.width, size.height)
        if scale >= 1 { return self } // Don't upscale

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

**JPEG Quality:**
- **Target:** 85% (0.85 compressionQuality)
- **Why:** Balances file size (150-300KB) with text readability
- **Current:** Likely using default (varies by iOS)

```swift
let imageData = image.jpegData(compressionQuality: 0.85)
```

**Format:**
- **Keep:** JPEG (not PNG)
- **Why:** Smaller file size, faster upload, AI models expect JPEG

**Aspect Ratio:**
- **Keep:** Original (don't force square)
- **Why:** Bookshelves are typically landscape or vertical rectangles

**Estimated Impact:**
- File size: 500KB → 200KB (2.5x smaller, faster upload)
- AI latency: Same or faster (smaller image = faster processing)
- Accuracy: 95%+ preserved (1536px is sufficient for book spines)

---

### Optimized Settings for Google Gemini 2.5 Flash

**Resolution:**
- **Target:** 3072x3072 max (Gemini excels at high-resolution text detection)
- **Why:** Gemini's vision model is optimized for fine details (ISBNs, small text on spines)
- **Implementation:** Only resize if image exceeds 3072px on longest dimension

```swift
extension UIImage {
    func resizeForGemini(maxDimension: CGFloat = 3072) -> UIImage {
        let scale = maxDimension / max(size.width, size.height)
        if scale >= 1 { return self } // Don't upscale

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
```

**JPEG Quality:**
- **Target:** 90% (0.90 compressionQuality)
- **Why:** Gemini is more sensitive to JPEG compression artifacts, especially on text edges
- **Trade-off:** Slightly larger files (300-500KB) but better accuracy on ISBNs and small text

```swift
let imageData = image.jpegData(compressionQuality: 0.90)
```

**Format:**
- **Keep:** JPEG (Gemini expects JPEG for bookshelf photos)
- **Why:** Optimized for photographic content with text overlays

**Aspect Ratio:**
- **Keep:** Original (don't crop or force square)
- **Why:** Bookshelves are rarely square (usually landscape or portrait)

**Estimated Impact:**
- File size: 400-600KB (larger than Cloudflare due to higher quality)
- AI latency: 25-40s (current, no change expected)
- Accuracy: 95%+ (maximized for ISBN detection and small text)
- ISBN detection rate: ~30-40% (Gemini's strength over Cloudflare)

**When to Use Gemini Preprocessing:**
- User prioritizes accuracy over speed
- Bookshelf has many books with visible ISBNs
- Small text or dense shelf (20+ books visible)
- User has good internet connection (larger file uploads acceptable)

---

## Provider-Specific Preprocessing (Future Enhancement)

**Concept:** Optimize image preprocessing based on selected AI provider

```swift
enum AIProvider {
    case gemini
    case cloudflare

    var imagePreprocessing: ImagePreprocessingConfig {
        switch self {
        case .gemini:
            return ImagePreprocessingConfig(
                maxDimension: 3072,
                jpegQuality: 0.90,
                targetFileSize: 400...600 // KB
            )
        case .cloudflare:
            return ImagePreprocessingConfig(
                maxDimension: 1536,
                jpegQuality: 0.85,
                targetFileSize: 150...300 // KB
            )
        }
    }
}

struct ImagePreprocessingConfig {
    let maxDimension: CGFloat
    let jpegQuality: CGFloat
    let targetFileSize: ClosedRange<Int> // KB
}
```

---

## Implementation Checklist

**Phase 1: Baseline Optimization (Recommended Now)**
- [ ] Add `resizeForAI(maxDimension:)` extension to UIImage
- [ ] Set explicit JPEG quality to 0.85
- [ ] Update `BookshelfCameraSessionManager` to use optimized preprocessing
- [ ] Test with 20 bookshelf images (verify readability preserved)
- [ ] Measure file size reduction (target: 200-300KB)

**Phase 2: Provider-Specific Optimization (Future)**
- [ ] Add AIProvider enum to settings
- [ ] Implement ImagePreprocessingConfig pattern
- [ ] Allow user to choose provider (Gemini vs Cloudflare)
- [ ] Apply provider-specific preprocessing before upload
- [ ] Add "Fast Mode" toggle (uses Cloudflare + aggressive compression)

**Phase 3: Advanced Optimization (Future)**
- [ ] Add sharpening filter for slightly blurry images
- [ ] Add contrast enhancement for low-light images
- [ ] Add automatic rotation correction (straighten shelves)
- [ ] Add glare detection and warning before upload

---

## Testing Guidelines

**Before deployment, test preprocessing changes with:**

1. **Resolution Test:** Verify 1536px resize preserves text readability
   - Test with smallest book spine text (typically 8-12pt)
   - Zoom in on resized image, confirm text is readable
   - Compare original vs resized detection rates

2. **JPEG Quality Test:** Verify 85% quality doesn't introduce artifacts
   - Look for blockiness around text edges
   - Check color accuracy (some book spines have color-coded series)
   - Confirm no visible compression artifacts

3. **File Size Test:** Verify target 150-300KB range
   - Test with various shelf sizes (5 books vs 20 books)
   - Test with different lighting conditions (bright vs dim)
   - Measure average file size across 20 images

4. **Upload Speed Test:** Measure improvement
   - Before: 500KB @ 10 Mbps = ~400ms upload
   - After: 200KB @ 10 Mbps = ~160ms upload (2.5x faster)

5. **Accuracy Test:** Verify no regression
   - Baseline: Current detection rate with 4K images
   - After: Detection rate with 1536px images
   - Success criteria: ≥95% of baseline accuracy

---

## Performance Benchmarks

**Expected improvements with optimization:**

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| File Size | 400-600 KB | 150-300 KB | 2x smaller |
| Upload Time (10 Mbps) | 320-480ms | 120-240ms | 2x faster |
| AI Processing | 25-40s (Gemini) | 3-8s (Cloudflare) | 5-8x faster |
| **Total Latency** | **26-41s** | **4-9s** | **~6x faster** |

**User Experience Impact:**
- Current: 26-41 seconds from photo to results
- Optimized: 4-9 seconds from photo to results
- **Result:** Users see results 6x faster, dramatically better UX

---

## References

- [Cloudflare Llama 3.2 Vision Tutorial](https://developers.cloudflare.com/workers-ai/guides/tutorials/llama-vision-tutorial/)
- [iOS Image Compression Best Practices](https://developer.apple.com/documentation/uikit/uiimage)
- [JPEG Quality Settings Guide](https://stackoverflow.com/questions/44462087/what-is-the-best-jpegdata-compressionquality-value)

---

## Related Files

- `BookshelfCameraSessionManager.swift` - Camera capture and image processing
- `BookshelfAIService.swift` - API communication with worker
- `cloudflare-workers/bookshelf-ai-worker/src/providers/cloudflareProvider.js` - Llama 3.2 implementation
- `docs/research/cloudflare-ai-models-evaluation.md` - Model selection rationale

---

**Document Version:** 1.0
**Status:** Ready for Implementation
**Priority:** Medium (optimize after Phase 2 baseline testing)
