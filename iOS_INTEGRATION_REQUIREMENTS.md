# iOS Integration Requirements: AI Provider Selection

**Status:** Ready for Implementation
**Priority:** High
**Estimated Effort:** 2-3 hours
**Related Issue:** #36 (cf - swap-in ai worker)

---

## Overview

Enable users to choose between **Gemini** (accurate, slow) and **Cloudflare** (fast, experimental) AI providers for bookshelf scanning directly in the iOS app Settings.

**Backend Status:** ✅ Complete and deployed
**iOS Status:** ⏳ Pending implementation

---

## User Story

**As a user**, I want to choose my AI provider in Settings so that:
- I can use **Gemini** when accuracy matters most (25-40s, 95%+ accuracy)
- I can use **Cloudflare** when speed matters most (3-8s, 80-90% accuracy)
- I can experiment to find what works best for my bookshelves

---

## Implementation Checklist

### Step 1: Add AIProvider Enum

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProvider.swift` (NEW)

```swift
import Foundation

/// AI provider options for bookshelf scanning
public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case gemini = "gemini"
    case cloudflare = "cloudflare"

    public var id: String { rawValue }

    /// User-facing display name
    public var displayName: String {
        switch self {
        case .gemini:
            return "Gemini (Accurate)"
        case .cloudflare:
            return "Cloudflare (Fast)"
        }
    }

    /// Detailed description for Settings UI
    public var description: String {
        switch self {
        case .gemini:
            return "Google Gemini 2.5 Flash - Best accuracy, especially for ISBNs and small text. Processing time: 25-40 seconds."
        case .cloudflare:
            return "Cloudflare Workers AI (Llama 3.2) - Experimental fast mode. Processing time: 3-8 seconds. May miss some books."
        }
    }

    /// SF Symbol icon name
    public var icon: String {
        switch self {
        case .gemini:
            return "sparkles"
        case .cloudflare:
            return "bolt.fill"
        }
    }

    /// Image preprocessing configuration
    public var preprocessingConfig: ImagePreprocessingConfig {
        switch self {
        case .gemini:
            return ImagePreprocessingConfig(
                maxDimension: 3072,
                jpegQuality: 0.90,
                targetFileSizeKB: 400...600
            )
        case .cloudflare:
            return ImagePreprocessingConfig(
                maxDimension: 1536,
                jpegQuality: 0.85,
                targetFileSizeKB: 150...300
            )
        }
    }
}

/// Image preprocessing configuration per provider
public struct ImagePreprocessingConfig: Sendable {
    let maxDimension: CGFloat
    let jpegQuality: CGFloat
    let targetFileSizeKB: ClosedRange<Int>
}
```

**Checklist:**
- [ ] Create `AIProvider.swift` in Common directory
- [ ] Add to Xcode project target
- [ ] Verify enum conforms to Sendable (Swift 6)
- [ ] Build succeeds with zero warnings

---

### Step 2: Add Settings UI

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift`

**Add to existing Experimental Features section:**

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("aiProvider") private var selectedProvider: AIProvider = .gemini
    @State private var showCloudflareWarning = false
    @Environment(iOS26ThemeStore.self) private var themeStore

    var body: some View {
        Form {
            // ... existing sections ...

            Section {
                Picker("AI Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: provider.icon)
                                .foregroundStyle(themeStore.primaryColor)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: selectedProvider) { oldValue, newValue in
                    // Show warning when switching to Cloudflare for first time
                    if newValue == .cloudflare && oldValue == .gemini {
                        showCloudflareWarning = true
                    }
                }
            } header: {
                Text("Experimental Features")
            } footer: {
                Text("Choose which AI model processes your bookshelf scans. Gemini provides best accuracy but takes longer. Cloudflare is faster but experimental.")
            }

            // ... existing sections ...
        }
        .alert("Experimental Feature", isPresented: $showCloudflareWarning) {
            Button("Try It") {
                // User confirmed, keep Cloudflare selection
            }
            Button("Cancel", role: .cancel) {
                selectedProvider = .gemini
            }
        } message: {
            Text("Cloudflare AI is 5-8x faster than Gemini but may have lower accuracy. This is an experimental feature. You can always switch back to Gemini in Settings.")
        }
    }
}
```

**Checklist:**
- [ ] Add Picker to Experimental Features section
- [ ] Add @AppStorage for persistence
- [ ] Add alert for first-time Cloudflare usage
- [ ] Test picker navigation works
- [ ] Test alert shows correctly
- [ ] Test @AppStorage persists across app restarts
- [ ] Verify iOS 26 HIG compliance (Liquid Glass theme)

---

### Step 3: Update BookshelfAIService

**File:** `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`

**Add provider header to API requests:**

```swift
import SwiftUI // For @AppStorage

@MainActor
public final class BookshelfAIService: Sendable {
    public static let shared = BookshelfAIService()

    // Read user-selected provider
    @AppStorage("aiProvider") private var selectedProvider: AIProvider = .gemini

    private init() {}

    public func processBookshelfImageWithWebSocket(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {

        // Apply provider-specific preprocessing
        let config = selectedProvider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let imageData = processedImage.jpegData(compressionQuality: config.jpegQuality) else {
            throw .imageCompressionFailed
        }

        // Build request with provider header
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(selectedProvider.rawValue, forHTTPHeaderField: "X-AI-Provider") // NEW
        request.httpBody = /* ... build JSON ... */

        // ... rest of implementation
    }
}

// Add UIImage extension for preprocessing
extension UIImage {
    func resizeForAI(maxDimension: CGFloat) -> UIImage {
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

**Checklist:**
- [ ] Add @AppStorage for selectedProvider
- [ ] Add X-AI-Provider header to all scan requests
- [ ] Apply provider-specific image preprocessing
- [ ] Add resizeForAI() extension to UIImage
- [ ] Test Gemini provider (default)
- [ ] Test Cloudflare provider (opt-in)
- [ ] Verify image preprocessing works (check file sizes)

---

### Step 4: Add Analytics Events

**File:** Track provider usage for product decisions

```swift
// In BookshelfAIService.processBookshelfImageWithWebSocket()

// At scan start
Analytics.logEvent("bookshelf_scan_started", parameters: [
    "ai_provider": selectedProvider.rawValue,
    "scan_id": UUID().uuidString,
    "image_width": Int(image.size.width),
    "image_height": Int(image.size.height)
])

// At scan completion
Analytics.logEvent("bookshelf_scan_completed", parameters: [
    "ai_provider": selectedProvider.rawValue,
    "books_detected": detectedBooks.count,
    "processing_time_seconds": processingTime,
    "scan_id": scanID,
    "success": true
])

// When user switches providers (in SettingsView)
Analytics.logEvent("ai_provider_switched", parameters: [
    "from_provider": oldValue.rawValue,
    "to_provider": newValue.rawValue,
    "timestamp": Date().timeIntervalSince1970
])
```

**Key Metrics to Track:**
- Provider distribution (% Gemini vs % Cloudflare)
- Success rate by provider
- Books detected per scan (by provider)
- Processing time distributions
- User retention after trying Cloudflare

**Checklist:**
- [ ] Add scan_started event
- [ ] Add scan_completed event
- [ ] Add provider_switched event
- [ ] Verify events fire correctly in Firebase/Analytics dashboard

---

### Step 5: Update Worker (Backend)

**File:** `cloudflare-workers/bookshelf-ai-worker/src/index.js`

**Read X-AI-Provider header and override env:**

```javascript
// In fetch() handler, before calling processBookshelfScan
async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // ... existing health endpoint handling ...

    if (url.pathname === '/scan' && request.method === 'POST') {
        // Read provider preference from header (iOS sends this)
        const requestedProvider = request.headers.get('X-AI-Provider') || env.AI_PROVIDER;

        // Override env.AI_PROVIDER for this request only
        const requestEnv = { ...env, AI_PROVIDER: requestedProvider };

        // Log provider selection
        console.log(`[Worker] Processing scan with provider: ${requestedProvider}`);

        // Pass modified env to processBookshelfScan
        return await processBookshelfScan(requestEnv, request, ctx);
    }

    // ... existing routes ...
}
```

**Checklist:**
- [ ] Add X-AI-Provider header reading
- [ ] Override env.AI_PROVIDER per-request
- [ ] Test with Gemini header (should use GeminiProvider)
- [ ] Test with Cloudflare header (should use CloudflareProvider)
- [ ] Verify logs show correct provider selection

---

### Step 6: End-to-End Testing

**Test Matrix:**

| Provider | Image Size | Expected File Size | Expected Latency | Expected Accuracy |
|----------|------------|-------------------|------------------|-------------------|
| Gemini | 3024x4032 | 400-600KB | 25-40s | 95%+ |
| Cloudflare | 3024x4032 | 150-300KB | 3-8s | 80-90% |

**Test Cases:**

1. **Default Provider (Gemini)**
   - [ ] Open app (fresh install)
   - [ ] Scan bookshelf
   - [ ] Verify 25-40s processing time
   - [ ] Verify high accuracy (95%+)
   - [ ] Verify Settings shows "Gemini" selected

2. **Switch to Cloudflare**
   - [ ] Go to Settings → Experimental Features
   - [ ] Tap "AI Provider" picker
   - [ ] Select "Cloudflare (Fast)"
   - [ ] See warning alert
   - [ ] Tap "Try It"
   - [ ] Scan bookshelf
   - [ ] Verify 3-8s processing time
   - [ ] Verify faster results (may have lower accuracy)

3. **Switch Back to Gemini**
   - [ ] Go to Settings
   - [ ] Select "Gemini (Accurate)"
   - [ ] No warning alert (switching back is safe)
   - [ ] Scan bookshelf
   - [ ] Verify 25-40s processing time
   - [ ] Verify high accuracy restored

4. **App Restart Persistence**
   - [ ] Select Cloudflare provider
   - [ ] Force quit app
   - [ ] Reopen app
   - [ ] Scan bookshelf
   - [ ] Verify still uses Cloudflare (persisted via @AppStorage)

5. **Network Error Handling**
   - [ ] Enable airplane mode
   - [ ] Scan bookshelf with Gemini
   - [ ] Verify graceful error message
   - [ ] Scan with Cloudflare
   - [ ] Verify same graceful error message

6. **Image Preprocessing**
   - [ ] Scan with Gemini → Check file size (should be 400-600KB)
   - [ ] Scan with Cloudflare → Check file size (should be 150-300KB)
   - [ ] Verify both produce readable results

**Checklist:**
- [ ] All 6 test cases pass
- [ ] Zero crashes or errors
- [ ] Analytics events fire correctly
- [ ] User experience is smooth

---

## Acceptance Criteria

**Must Have:**
- [ ] Settings UI allows provider selection
- [ ] Gemini is default (proven accuracy)
- [ ] Cloudflare shows warning on first use
- [ ] Selection persists across app restarts
- [ ] Both providers work end-to-end
- [ ] Analytics track provider usage

**Should Have:**
- [ ] Provider-specific image preprocessing (file size optimization)
- [ ] Clear descriptions in Settings UI
- [ ] Icons differentiate providers (sparkles vs bolt)

**Nice to Have:**
- [ ] "Fast Mode" quick toggle in camera UI
- [ ] Show processing time in results view
- [ ] Display provider name in scan results

---

## Files to Create/Modify

**New Files:**
- [ ] `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProvider.swift`

**Modified Files:**
- [ ] `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift`
- [ ] `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
- [ ] `cloudflare-workers/bookshelf-ai-worker/src/index.js`

---

## Documentation References

**Full Implementation Guide:**
- `docs/guides/ios-ai-provider-settings.md` - Complete Swift code examples

**Image Preprocessing:**
- `docs/guides/ios-image-preprocessing-for-ai.md` - Provider-specific optimization

**Backend Architecture:**
- `docs/plans/2025-10-22-ai-provider-abstraction.md` - Full implementation plan
- `docs/research/cloudflare-ai-models-evaluation.md` - Model selection rationale

---

## Success Metrics (30 Days Post-Launch)

**Usage:**
- 10%+ users try Cloudflare (Fast Mode)
- 5%+ users stay on Cloudflare (satisfied with accuracy)

**Performance:**
- Cloudflare scans complete in <8s (95th percentile)
- Gemini scans maintain 95%+ accuracy

**Quality:**
- <5% crash rate on provider switching
- <10% negative feedback on Cloudflare accuracy

**Business:**
- 2x cost reduction for Cloudflare users
- Zero customer support tickets about provider confusion

---

## Rollback Plan

**If Cloudflare accuracy is insufficient (<75%):**

1. **Immediate:** Hide Cloudflare option in Settings (server-side flag)
2. **Week 1:** Collect user feedback on accuracy issues
3. **Week 2:** Optimize Cloudflare prompt based on failure patterns
4. **Week 3:** Re-enable for beta users only
5. **Week 4:** Make data-driven decision (keep, improve, or remove)

**If Cloudflare works well (>80% accuracy):**

1. **Month 1:** Keep Gemini as default, offer Cloudflare as opt-in
2. **Month 2:** A/B test: 50% users see "Try Fast Mode" prompt
3. **Month 3:** Evaluate data, consider making Cloudflare default
4. **Month 4:** Implement hybrid mode (Cloudflare first, Gemini fallback)

---

## Related Issues

- #36: cf - swap-in ai worker (Phase 2 complete)
- #35: shelf - modularize the ai (Phase 1 complete, closed)

---

## Quick Start Command

```bash
# 1. Create AIProvider.swift
# Copy code from Step 1 above

# 2. Update SettingsView.swift
# Add Picker code from Step 2

# 3. Update BookshelfAIService.swift
# Add X-AI-Provider header from Step 3

# 4. Update index.js (backend)
# Add header reading from Step 5

# 5. Test end-to-end
# Follow test matrix from Step 6

# 6. Ship iOS update
# Version bump, App Store submission
```

---

**Document Version:** 1.0
**Last Updated:** October 22, 2025
**Status:** Ready for Implementation
**Blocked By:** None (backend already deployed)
