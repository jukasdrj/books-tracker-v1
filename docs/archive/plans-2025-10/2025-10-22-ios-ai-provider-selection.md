# iOS AI Provider Selection Implementation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Enable users to choose between Gemini (accurate, 25-40s) and Cloudflare (fast, 3-8s) AI providers for bookshelf scanning directly in iOS Settings.

**Architecture:** Add AIProvider enum with preprocessing configs, create AIProviderSettings (@Observable) matching FeatureFlags pattern, update BookshelfAIService actor to read UserDefaults directly, add Settings UI with @Environment injection and confirmation alert.

**Tech Stack:** SwiftUI, @Observable + @Environment, Swift 6 Sendable + actors, UIKit (image preprocessing), Cloudflare Workers (backend header reading)

---

## Prerequisites

**Required Files to Review:**
- `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift` - Existing Settings structure
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift` - Current API implementation
- `cloudflare-workers/bookshelf-ai-worker/src/index.js` - Backend scan endpoint

**Testing Environment:**
- Xcode 16.0+
- iOS 26.0+ Simulator (iPhone 16)
- Physical device for real-world validation
- Cloudflare Workers deployed backend

**Success Criteria:**
- Zero Swift 6 concurrency warnings
- Provider selection persists across app restarts
- Both providers work end-to-end with correct processing times
- Settings UI follows iOS 26 HIG (Liquid Glass design)

---

## Task 1: Create AIProvider Enum and Settings (TDD)

**Files:**
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProvider.swift`
- Create: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProviderSettings.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/AIProviderTests.swift`

**Step 1: Write failing test for enum basic properties**

```swift
import Testing
@testable import BooksTrackerFeature

@Suite("AIProvider Tests")
struct AIProviderTests {
    @Test("Provider has correct raw values")
    func testRawValues() {
        #expect(AIProvider.gemini.rawValue == "gemini")
        #expect(AIProvider.cloudflare.rawValue == "cloudflare")
    }

    @Test("Provider has correct display names")
    func testDisplayNames() {
        #expect(AIProvider.gemini.displayName == "Gemini (Accurate)")
        #expect(AIProvider.cloudflare.displayName == "Cloudflare (Fast)")
    }

    @Test("Provider is Codable")
    func testCodable() throws {
        let encoded = try JSONEncoder().encode(AIProvider.gemini)
        let decoded = try JSONDecoder().decode(AIProvider.self, from: encoded)
        #expect(decoded == .gemini)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AIProviderTests`

Expected: FAIL - "Cannot find type 'AIProvider' in scope"

**Step 3: Create minimal AIProvider enum**

Create file: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProvider.swift`

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
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter AIProviderTests`

Expected: PASS - All 3 tests pass

**Step 5: Add test for description property**

```swift
@Test("Provider has detailed descriptions")
func testDescriptions() {
    #expect(AIProvider.gemini.description.contains("25-40 seconds"))
    #expect(AIProvider.cloudflare.description.contains("3-8 seconds"))
}
```

**Step 6: Run test to verify it fails**

Expected: FAIL - "Value of type 'AIProvider' has no member 'description'"

**Step 7: Implement description property**

Add to `AIProvider.swift`:

```swift
/// Detailed description for Settings UI
public var description: String {
    switch self {
    case .gemini:
        return "Google Gemini 2.5 Flash - Best accuracy, especially for ISBNs and small text. Processing time: 25-40 seconds."
    case .cloudflare:
        return "Cloudflare Workers AI (Llama 3.2) - Experimental fast mode. Processing time: 3-8 seconds. May miss some books."
    }
}
```

**Step 8: Run test to verify it passes**

Expected: PASS

**Step 9: Add test for icon property**

```swift
@Test("Provider has correct SF Symbol icons")
func testIcons() {
    #expect(AIProvider.gemini.icon == "sparkles")
    #expect(AIProvider.cloudflare.icon == "bolt.fill")
}
```

**Step 10: Implement icon property**

```swift
/// SF Symbol icon name
public var icon: String {
    switch self {
    case .gemini:
        return "sparkles"
    case .cloudflare:
        return "bolt.fill"
    }
}
```

**Step 11: Run test to verify it passes**

Expected: PASS

**Step 12: Add test for preprocessing config**

```swift
@Test("Gemini has high-quality preprocessing config")
func testGeminiPreprocessing() {
    let config = AIProvider.gemini.preprocessingConfig
    #expect(config.maxDimension == 3072)
    #expect(config.jpegQuality == 0.90)
    #expect(config.targetFileSizeKB == 400...600)
}

@Test("Cloudflare has fast preprocessing config")
func testCloudflarePreprocessing() {
    let config = AIProvider.cloudflare.preprocessingConfig
    #expect(config.maxDimension == 1536)
    #expect(config.jpegQuality == 0.85)
    #expect(config.targetFileSizeKB == 150...300)
}
```

**Step 13: Run test to verify it fails**

Expected: FAIL - "Value of type 'AIProvider' has no member 'preprocessingConfig'"

**Step 14: Add ImagePreprocessingConfig struct**

Add to `AIProvider.swift`:

```swift
/// Image preprocessing configuration per provider
public struct ImagePreprocessingConfig: Sendable {
    public let maxDimension: CGFloat
    public let jpegQuality: CGFloat
    public let targetFileSizeKB: ClosedRange<Int>

    public init(maxDimension: CGFloat, jpegQuality: CGFloat, targetFileSizeKB: ClosedRange<Int>) {
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.targetFileSizeKB = targetFileSizeKB
    }
}
```

**Step 15: Implement preprocessingConfig property**

Add to `AIProvider` enum:

```swift
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
```

**Step 16: Run all tests to verify they pass**

Run: `swift test --filter AIProviderTests`

Expected: PASS - All 6 tests pass

**Step 17: Create AIProviderSettings (@Observable class)**

Create file: `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/AIProviderSettings.swift`

```swift
import SwiftUI

/// Settings for AI provider selection
///
/// This observable class manages AI provider preference that persists
/// via UserDefaults. Follows the same pattern as FeatureFlags.swift.
@Observable
public final class AIProviderSettings: Sendable {
    /// Currently selected AI provider
    ///
    /// Default: `.gemini` (proven accuracy)
    public var selectedProvider: AIProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
            return AIProvider(rawValue: raw) ?? .gemini
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "aiProvider")
        }
    }

    public static let shared = AIProviderSettings()

    private init() {}
}
```

**Step 18: Add test for AIProviderSettings persistence**

Add to test file:

```swift
@Test("AIProviderSettings persists to UserDefaults")
func testSettingsPersistence() {
    let settings = AIProviderSettings.shared

    // Set Cloudflare
    settings.selectedProvider = .cloudflare
    #expect(settings.selectedProvider == .cloudflare)

    // Verify UserDefaults
    let stored = UserDefaults.standard.string(forKey: "aiProvider")
    #expect(stored == "cloudflare")

    // Change back to Gemini
    settings.selectedProvider = .gemini
    #expect(settings.selectedProvider == .gemini)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "aiProvider")
}
```

**Step 19: Run test to verify persistence works**

Run: `swift test --filter AIProviderTests`

Expected: PASS - All 7 tests pass (6 enum + 1 persistence)

**Step 20: Add both files to Xcode project**

1. Open `BooksTracker.xcworkspace` in Xcode
2. Navigate to `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/`
3. Verify `AIProvider.swift` and `AIProviderSettings.swift` appear
4. Build project: Cmd+B

Expected: Build succeeds with zero warnings

**Step 21: Commit AIProvider enum and settings**

```bash
cd BooksTrackerPackage
git add Sources/BooksTrackerFeature/Common/AIProvider.swift
git add Sources/BooksTrackerFeature/Common/AIProviderSettings.swift
git add Tests/BooksTrackerFeatureTests/AIProviderTests.swift
git commit -m "feat(ai): add AIProvider enum and settings

- Add Gemini (accurate, 25-40s) and Cloudflare (fast, 3-8s) providers
- Include image preprocessing configs per provider
- Add AIProviderSettings (@Observable) matching FeatureFlags pattern
- Fully tested with Swift Testing (7 tests)
- Swift 6 Sendable compliant"
```

---

## Task 2: Add Settings UI (TDD)

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift`
- Test: Manual testing (UI tests are expensive for Settings views)

**Step 1: Read current SettingsView structure**

Run: `cat BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift | head -50`

Identify: Location of "Experimental Features" section

**Step 2: Add AIProviderSettings to BooksTrackerApp environment**

**CRITICAL:** Must inject AIProviderSettings into app environment (like FeatureFlags pattern).

In `BooksTracker/BooksTrackerApp.swift`, add:

```swift
@main
struct BooksTrackerApp: App {
    @State private var themeStore = iOS26ThemeStore()
    @State private var featureFlags = FeatureFlags.shared
    @State private var aiSettings = AIProviderSettings.shared  // NEW

    var body: some Scene {
        WindowGroup {
            ContentView()
                .iOS26ThemeStore(themeStore)
                .modelContainer(modelContainer)
                .environment(featureFlags)
                .environment(aiSettings)  // NEW
        }
    }
}
```

**Step 3: Build to verify environment injection**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds

**Step 4: Add @Environment property to SettingsView**

Add near top of `SettingsView` (after existing @Environment properties):

```swift
@Environment(AIProviderSettings.self) private var aiSettings
@State private var showCloudflareWarning = false
```

**Step 5: Build to verify no compilation errors**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds (zero warnings)

**Step 6: Add Picker to Experimental Features section**

Locate existing `Section { ... } header: { Text("Experimental Features") }` and add at the TOP of that section (before "Scan Bookshelf" button):

```swift
// Inside existing Experimental Features Section
Picker("AI Provider", selection: Binding(
    get: { aiSettings.selectedProvider },
    set: { aiSettings.selectedProvider = $0 }
)) {
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
```

Note: We use `Binding(get:set:)` to connect @Observable property to Picker.

**Step 7: Build to verify Picker compiles**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds

**Step 8: Add onChange handler for Cloudflare warning**

Add to Picker (after `.pickerStyle`):

```swift
.onChange(of: aiSettings.selectedProvider) { oldValue, newValue in
    // Show warning when switching to Cloudflare for first time
    if newValue == .cloudflare && oldValue == .gemini {
        showCloudflareWarning = true
    }
}
```

**Step 9: Add confirmation alert**

Add after `Form { ... }`:

```swift
.alert("Experimental Feature", isPresented: $showCloudflareWarning) {
    Button("Try It") {
        // User confirmed, keep Cloudflare selection
    }
    Button("Cancel", role: .cancel) {
        aiSettings.selectedProvider = .gemini
    }
} message: {
    Text("Cloudflare AI is 5-8x faster than Gemini but may have lower accuracy. This is an experimental feature. You can always switch back to Gemini in Settings.")
}
```

**Step 10: Build and run in simulator**

Run: `/sim` (or manual: Cmd+R in Xcode)

Expected: App launches successfully

**Step 11: Manual test - Navigate to Settings**

1. Tap Settings tab
2. Scroll to "AI Provider" section
3. Tap picker
4. Verify both options show with correct names and descriptions
5. Tap "Cloudflare (Fast)"
6. Verify alert appears
7. Tap "Cancel"
8. Verify selection reverts to Gemini

**Step 12: Manual test - Confirm Cloudflare selection**

1. Tap picker again
2. Select "Cloudflare (Fast)"
3. Tap "Try It"
4. Verify selection persists
5. Navigate away and back
6. Verify still shows Cloudflare

**Step 13: Manual test - Persistence across app restarts**

1. Select Cloudflare
2. Force quit app (swipe up in app switcher)
3. Relaunch app
4. Go to Settings
5. Verify Cloudflare still selected

Expected: AIProviderSettings persists selection via UserDefaults

**Step 14: Commit Settings UI and environment injection**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift
git add BooksTracker/BooksTrackerApp.swift
git commit -m "feat(settings): add AI provider picker with confirmation alert

- Add @Environment(AIProviderSettings.self) for provider selection
- Inject AIProviderSettings into app environment (matches FeatureFlags pattern)
- Show warning when switching to experimental Cloudflare provider
- Use iOS 26 Liquid Glass theme colors (primaryColor, .secondary)
- Manual testing: 3/3 test cases pass"
```

---

## Task 3: Update BookshelfAIService (Keep Actor Isolation!)

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
- Test: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/UIImageExtensionsTests.swift`

**CRITICAL:** BookshelfAIService MUST stay as `actor` (not @MainActor). UserDefaults is thread-safe and can be read directly from actor context.

**Step 1: Add helper method to read provider from UserDefaults**

In `BookshelfAIService` actor, add private method:

```swift
actor BookshelfAIService {
    // ... existing properties ...

    /// Read user-selected AI provider from UserDefaults
    /// UserDefaults is thread-safe, safe to call from actor context
    private func getSelectedProvider() -> AIProvider {
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        return AIProvider(rawValue: raw) ?? .gemini
    }

    // ... rest of implementation ...
}
```

**Step 2: Build to verify actor isolation**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds with zero warnings (UserDefaults is thread-safe)

**Step 3: Add UIImage.resizeForAI extension (TDD)**

Create test file: `BooksTrackerPackage/Tests/BooksTrackerFeatureTests/UIImageExtensionsTests.swift`

```swift
import Testing
import UIKit
@testable import BooksTrackerFeature

@Suite("UIImage Resize Tests")
struct UIImageResizeTests {
    @Test("Does not upscale smaller images")
    func testNoUpscaling() {
        let smallImage = createTestImage(size: CGSize(width: 100, height: 100))
        let resized = smallImage.resizeForAI(maxDimension: 1000)

        #expect(resized.size.width == 100)
        #expect(resized.size.height == 100)
    }

    @Test("Downscales larger images while preserving aspect ratio")
    func testDownscaling() {
        let largeImage = createTestImage(size: CGSize(width: 4000, height: 3000))
        let resized = largeImage.resizeForAI(maxDimension: 1536)

        let maxDim = max(resized.size.width, resized.size.height)
        #expect(maxDim <= 1536)

        // Aspect ratio preserved
        let originalRatio = 4000.0 / 3000.0
        let resizedRatio = resized.size.width / resized.size.height
        #expect(abs(originalRatio - resizedRatio) < 0.01)
    }

    private func createTestImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
```

**Step 4: Run test to verify it fails**

Run: `swift test --filter UIImageResizeTests`

Expected: FAIL - "Value of type 'UIImage' has no member 'resizeForAI'"

**Step 5: Implement UIImage.resizeForAI extension**

Add to bottom of `BookshelfAIService.swift`:

```swift
// MARK: - UIImage Extensions

extension UIImage {
    /// Resize image for AI processing without upscaling
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

**Step 6: Run test to verify it passes**

Run: `swift test --filter UIImageResizeTests`

Expected: PASS - Both tests pass

**Step 7: Update processBookshelfImageWithWebSocket to use provider**

Find the method in `BookshelfAIService.swift` and update. **IMPORTANT:** This is an actor method, so we read UserDefaults at the start:

```swift
func processBookshelfImageWithWebSocket(
    _ image: UIImage,
    progressHandler: @MainActor @escaping (Double, String) -> Void
) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {

    // Read user-selected provider (UserDefaults is thread-safe)
    let provider = getSelectedProvider()

    // Apply provider-specific preprocessing
    let config = provider.preprocessingConfig
    let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

    guard let imageData = processedImage.jpegData(compressionQuality: config.jpegQuality) else {
        throw .imageCompressionFailed
    }

    // Step 2: Start async scan job with provider header
    let jobResponse: ScanJobResponse
    do {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.rawValue, forHTTPHeaderField: "X-AI-Provider") // NEW

        // ... rest of request setup and send ...
        jobResponse = try await startScanJob(imageData, with: request)
    } catch {
        throw .networkError(error)
    }

    // ... rest of existing WebSocket implementation ...
}
```

Note: You'll need to update `startScanJob` to accept a pre-configured URLRequest or build the request inline.

**Step 8: Build to verify changes compile**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds with zero warnings

**Step 9: Commit BookshelfAIService changes**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
git add BooksTrackerPackage/Tests/BooksTrackerFeatureTests/UIImageExtensionsTests.swift
git commit -m "feat(ai): add provider-specific image preprocessing

- Read user-selected provider from UserDefaults (thread-safe in actor)
- Apply Gemini (3072px, 90% quality) or Cloudflare (1536px, 85% quality) configs
- Add X-AI-Provider header to all scan requests
- Add UIImage.resizeForAI extension with tests (2/2 passing)
- Maintains actor isolation (Swift 6 compliant)"
```

---

## Task 4: Add Analytics Events

**Files:**
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
- Modify: `BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift`

**Step 1: Add scan_started analytics (print + TODO)**

At the start of `processBookshelfImageWithWebSocket` (after reading provider):

```swift
// Read user-selected provider
let provider = getSelectedProvider()

// Log scan start (TODO: Replace with Firebase Analytics when configured)
let scanID = UUID().uuidString
print("[Analytics] bookshelf_scan_started - provider: \(provider.rawValue), scan_id: \(scanID), image_width: \(Int(image.size.width)), image_height: \(Int(image.size.height))")
// TODO: Add Firebase Analytics
// Analytics.logEvent("bookshelf_scan_started", parameters: [
//     "ai_provider": provider.rawValue,
//     "scan_id": scanID,
//     "image_width": Int(image.size.width),
//     "image_height": Int(image.size.height)
// ])
```

**Step 2: Add scan_completed analytics (print + TODO)**

At successful completion (after enrichment):

```swift
print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(detectedBooks.count), scan_id: \(scanID), success: true")
// TODO: Add Firebase Analytics
// Analytics.logEvent("bookshelf_scan_completed", parameters: [
//     "ai_provider": provider.rawValue,
//     "books_detected": detectedBooks.count,
//     "processing_time_seconds": processingTime,
//     "scan_id": scanID,
//     "success": true
// ])
```

**Step 3: Add provider_switched analytics (print + TODO)**

Update existing `.onChange(of: aiSettings.selectedProvider)` handler:

```swift
.onChange(of: aiSettings.selectedProvider) { oldValue, newValue in
    // Log provider switch (TODO: Replace with Firebase Analytics)
    print("[Analytics] ai_provider_switched - from: \(oldValue.rawValue), to: \(newValue.rawValue)")
    // TODO: Add Firebase Analytics
    // Analytics.logEvent("ai_provider_switched", parameters: [
    //     "from_provider": oldValue.rawValue,
    //     "to_provider": newValue.rawValue,
    //     "timestamp": Date().timeIntervalSince1970
    // ])

    // Show warning when switching to Cloudflare for first time
    if newValue == .cloudflare && oldValue == .gemini {
        showCloudflareWarning = true
    }
}
```

**Step 4: Build to verify analytics compile**

Run: `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`

Expected: Build succeeds

**Note:** Using print statements with TODO comments. When Firebase Analytics is configured, uncomment the Analytics.logEvent calls and remove print statements.

**Step 5: Commit analytics events**

```bash
git add BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift
git add BooksTrackerPackage/Sources/BooksTrackerFeature/SettingsView.swift
git commit -m "feat(analytics): add AI provider tracking placeholders

- Add print statements for scan_started, scan_completed, provider_switched
- Include TODO comments for Firebase Analytics integration
- Track provider, book count, timing for debugging
- Ready to upgrade to Firebase when configured"
```

---

## Task 5: Update Backend Worker

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/src/index.js`

**Step 1: Read current /scan endpoint handler**

Run: `cat cloudflare-workers/bookshelf-ai-worker/src/index.js | grep -A 20 "pathname === '/scan'"`

Identify: Location to add header reading logic

**Step 2: Add X-AI-Provider header reading**

Update `/scan` endpoint handler:

```javascript
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
```

**Step 3: Test locally with wrangler dev**

```bash
cd cloudflare-workers/bookshelf-ai-worker
npm run dev
```

In another terminal:

```bash
# Test Gemini header
curl -X POST http://localhost:8787/scan \
  -H "Content-Type: application/json" \
  -H "X-AI-Provider: gemini" \
  -d '{"image":"base64...","wsUrl":"ws://..."}'

# Test Cloudflare header
curl -X POST http://localhost:8787/scan \
  -H "Content-Type: application/json" \
  -H "X-AI-Provider: cloudflare" \
  -d '{"image":"base64...","wsUrl":"ws://..."}'
```

Expected: Console logs show correct provider selection

**Step 4: Deploy to production**

```bash
npm run deploy
```

Expected: Deployment succeeds

**Step 5: Test production endpoint**

```bash
curl -X POST https://bookshelf-ai-worker.jukasdrj.workers.dev/scan \
  -H "Content-Type: application/json" \
  -H "X-AI-Provider: gemini" \
  -d '{"image":"...","wsUrl":"..."}'
```

Expected: Worker processes with Gemini provider

**Step 6: Commit backend changes**

```bash
cd cloudflare-workers/bookshelf-ai-worker
git add src/index.js
git commit -m "feat(worker): read X-AI-Provider header from iOS

- Override env.AI_PROVIDER per-request based on iOS preference
- Log provider selection for debugging
- Tested locally and in production"
```

---

## Task 6: End-to-End Testing

**Test Environment:**
- iOS 26.0 Simulator (iPhone 16)
- Physical iPhone (for real-world validation)
- Production Cloudflare Workers backend

**Step 1: Test default provider (Gemini)**

1. Delete app from simulator (long press → Remove App)
2. Run app: `/sim`
3. Navigate to Settings
4. Verify "Gemini (Accurate)" is selected by default
5. Go to Bookshelf Scanner (Settings → Scan Bookshelf)
6. Take/select test photo of bookshelf
7. Time processing duration
8. Expected: 25-40 seconds
9. Verify high accuracy (95%+ books detected correctly)

**Step 2: Test switch to Cloudflare with warning**

1. Go to Settings → AI Provider
2. Tap "Cloudflare (Fast)"
3. Verify alert appears with "Experimental Feature" title
4. Verify alert message mentions "5-8x faster" and "lower accuracy"
5. Tap "Cancel"
6. Verify selection reverts to Gemini
7. Tap Cloudflare again
8. Tap "Try It"
9. Verify selection persists as Cloudflare

**Step 3: Test Cloudflare provider performance**

1. With Cloudflare selected, go to Bookshelf Scanner
2. Take/select same test photo
3. Time processing duration
4. Expected: 3-8 seconds (5-8x faster than Gemini)
5. Verify books detected (may have lower accuracy)
6. Compare results to Gemini scan
7. Expected: 80-90% accuracy (some books may be missed)

**Step 4: Test provider persistence**

1. Verify Cloudflare is selected in Settings
2. Force quit app (swipe up in app switcher)
3. Relaunch app
4. Go to Settings → AI Provider
5. Verify Cloudflare still selected
6. Perform scan
7. Verify uses Cloudflare (3-8s processing)

**Step 5: Test switch back to Gemini (no warning)**

1. Go to Settings → AI Provider
2. Tap "Gemini (Accurate)"
3. Verify NO alert appears (switching back is safe)
4. Perform scan
5. Verify uses Gemini (25-40s processing)
6. Verify high accuracy restored

**Step 6: Test on physical device**

1. Deploy to iPhone: `/device-deploy`
2. Repeat steps 1-5 on physical device
3. Verify keyboard works, touch interactions smooth
4. Test with real bookshelf photo (not simulator image)
5. Verify processing times match expectations

**Step 7: Test network error handling**

1. Enable airplane mode on device
2. Select Gemini provider
3. Attempt scan
4. Verify graceful error message (not crash)
5. Disable airplane mode
6. Retry scan
7. Verify works correctly

**Step 8: Test image preprocessing file sizes**

1. Add debug logging to BookshelfAIService:
   ```swift
   print("[Debug] Image size: \(imageData.count / 1024)KB")
   ```
2. Scan with Gemini
3. Check console logs
4. Expected: 400-600KB file size
5. Scan with Cloudflare
6. Expected: 150-300KB file size
7. Remove debug logging

**Step 9: Verify analytics events**

1. If Firebase Analytics configured:
   - Open Firebase Console → Events
   - Perform scan with Gemini
   - Verify `bookshelf_scan_started` event fires
   - Verify `bookshelf_scan_completed` event fires
   - Switch to Cloudflare
   - Verify `ai_provider_switched` event fires
2. If no analytics:
   - Skip this step

**Step 10: Document test results**

Create file: `docs/testing/2025-10-22-ai-provider-testing-results.md`

```markdown
# AI Provider Selection Testing Results

**Date:** October 22, 2025
**Tester:** [Your Name]
**Build:** [Build number]

## Test Matrix

| Test Case | Expected | Actual | Status |
|-----------|----------|--------|--------|
| Default provider (Gemini) | 25-40s | [X]s | ✅/❌ |
| Switch to Cloudflare | Alert shown | ✅/❌ | ✅/❌ |
| Cloudflare performance | 3-8s | [X]s | ✅/❌ |
| Persistence | Cloudflare after restart | ✅/❌ | ✅/❌ |
| Switch back to Gemini | No alert | ✅/❌ | ✅/❌ |
| Physical device | Works correctly | ✅/❌ | ✅/❌ |
| Network errors | Graceful handling | ✅/❌ | ✅/❌ |
| Image preprocessing | Correct file sizes | ✅/❌ | ✅/❌ |

## Notes

[Any issues, observations, or recommendations]

## Sign-Off

- [ ] All test cases pass
- [ ] Zero crashes or errors
- [ ] Ready for production
```

**Step 11: Commit test documentation**

```bash
git add docs/testing/2025-10-22-ai-provider-testing-results.md
git commit -m "test: document AI provider selection testing results

- 8/8 test cases pass
- Both providers work end-to-end
- Performance matches expectations
- Ready for production deployment"
```

---

## Task 7: Final Checklist & Deployment

**Step 1: Run full test suite**

```bash
swift test
```

Expected: All tests pass (including new AIProvider tests)

**Step 2: Build for release**

```bash
xcodebuild -workspace BooksTracker.xcworkspace \
  -scheme BooksTracker \
  -configuration Release \
  clean build
```

Expected: Build succeeds with zero warnings

**Step 3: Version bump**

```bash
./Scripts/update_version.sh patch
```

Expected: Version increments (e.g., 1.12.0 → 1.12.1)

**Step 4: Create release PR**

```bash
git checkout -b feature/ai-provider-selection
git push origin feature/ai-provider-selection
```

Create PR with description:

```markdown
# AI Provider Selection Feature

**Status:** ✅ Ready for Review

## Changes

- Add AIProvider enum (Gemini, Cloudflare)
- Add Settings UI with provider picker
- Update BookshelfAIService with X-AI-Provider header
- Add provider-specific image preprocessing
- Add analytics events for provider tracking
- Update backend worker to read X-AI-Provider header

## Testing

- 8/8 end-to-end test cases pass
- Zero warnings, zero errors
- Tested on simulator and physical device
- All providers work correctly

## Performance

| Provider | Processing Time | Accuracy | File Size |
|----------|----------------|----------|-----------|
| Gemini | 25-40s | 95%+ | 400-600KB |
| Cloudflare | 3-8s | 80-90% | 150-300KB |

## Checklist

- [x] Swift 6 concurrency compliant
- [x] iOS 26 HIG compliant
- [x] Zero warnings
- [x] All tests pass
- [x] Documentation complete
- [x] Analytics integrated
- [x] Backend deployed
```

**Step 5: Request code review**

Use `/superpowers:requesting-code-review` skill to request review from team.

**Step 6: Merge and deploy**

After approval:

```bash
git checkout main
git merge feature/ai-provider-selection
git push origin main
```

Deploy to App Store:

```bash
./Scripts/release.sh patch "Add AI provider selection (Gemini vs Cloudflare)"
```

**Step 7: Monitor production metrics**

After App Store release:

1. Monitor Firebase Analytics for 7 days
2. Track metrics:
   - % users trying Cloudflare
   - % users staying on Cloudflare
   - Processing times (p50, p95, p99)
   - Success rates per provider
   - Crash rates
3. Document findings in GitHub Issue #36

**Step 8: Final commit**

```bash
git add docs/plans/2025-10-22-ios-ai-provider-selection.md
git commit -m "docs: mark AI provider selection plan as completed

- Feature shipped in v1.12.1
- 8/8 test cases pass
- Ready for production monitoring"
```

---

## Success Metrics (Post-Launch)

**Week 1:**
- [ ] 5%+ users try Cloudflare provider
- [ ] <1% crash rate on provider switching
- [ ] Both providers maintain expected processing times

**Week 4:**
- [ ] 10%+ users try Cloudflare
- [ ] 5%+ users stay on Cloudflare
- [ ] <5% negative feedback on Cloudflare accuracy

**Month 3:**
- [ ] Data-driven decision: Keep, improve, or remove Cloudflare
- [ ] Consider A/B testing "Try Fast Mode" prompt
- [ ] Evaluate hybrid mode (Cloudflare first, Gemini fallback)

---

## Rollback Plan

**If Cloudflare accuracy is insufficient (<75%):**

1. Add server-side flag to hide Cloudflare option
2. Collect user feedback on accuracy issues
3. Optimize Cloudflare prompt based on failure patterns
4. Re-enable for beta users only
5. Make data-driven decision in Month 4

**If critical bugs discovered:**

1. Revert to previous version in App Store
2. Fix bugs in development
3. Re-test thoroughly
4. Redeploy with patch version

---

## Dependencies

**iOS:**
- SwiftUI (iOS 26+)
- @AppStorage (built-in)
- Swift Testing (Xcode 16+)

**Backend:**
- Cloudflare Workers
- Gemini 2.5 Flash API
- Cloudflare Workers AI (Llama 3.2)

**Tools:**
- Xcode 16.0+
- wrangler CLI
- Firebase Analytics (optional)

---

## Related Documentation

- `iOS_INTEGRATION_REQUIREMENTS.md` - Original requirements doc
- `docs/guides/ios-ai-provider-settings.md` - Full implementation guide
- `docs/guides/ios-image-preprocessing-for-ai.md` - Preprocessing details
- `docs/plans/2025-10-22-ai-provider-abstraction.md` - Backend architecture
- GitHub Issue #36: cf - swap-in ai worker

---

**Plan Status:** ✅ Ready for Execution
**Estimated Time:** 2-3 hours (with testing)
**Risk Level:** Low (backend already deployed, iOS changes isolated)
**Dependencies:** None (backend complete, backend tests passing)
