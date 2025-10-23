# iOS AI Provider Settings Integration Guide

**Last Updated:** October 22, 2025
**Status:** Ready for Implementation
**Related:** Phase 2 AI Provider Abstraction (#36)

---

## Overview

This guide documents how to add AI provider selection to the iOS Settings UI, allowing users to choose between Gemini (accurate, slow) and Cloudflare (fast, experimental).

## User Story

**As a user**, I want to choose my preferred AI provider so that I can:
- Use **Gemini** when I need maximum accuracy and don't mind waiting (25-40s)
- Use **Cloudflare** when I need fast results and accuracy is "good enough" (3-8s)
- Experiment with different providers to find what works best for my bookshelves

---

## Settings UI Design

### Location
`SettingsView.swift` → "Experimental Features" section → "AI Provider" picker

### UI Components

```swift
import SwiftUI

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case cloudflare = "cloudflare"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:
            return "Gemini (Accurate)"
        case .cloudflare:
            return "Cloudflare (Fast)"
        }
    }

    var description: String {
        switch self {
        case .gemini:
            return "Google Gemini 2.5 Flash - Best accuracy, especially for ISBNs. Processing time: 25-40 seconds."
        case .cloudflare:
            return "Cloudflare Workers AI - Experimental fast mode. Processing time: 3-8 seconds."
        }
    }

    var icon: String {
        switch self {
        case .gemini:
            return "sparkles" // or "star.fill"
        case .cloudflare:
            return "bolt.fill"
        }
    }
}

// Settings View
struct SettingsView: View {
    @AppStorage("aiProvider") private var selectedProvider: AIProvider = .gemini

    var body: some View {
        Form {
            Section {
                Picker("AI Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label {
                            VStack(alignment: .leading) {
                                Text(provider.displayName)
                                    .font(.headline)
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: provider.icon)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Experimental Features")
            } footer: {
                Text("Choose which AI model processes your bookshelf scans. Gemini provides best accuracy but takes longer. Cloudflare is faster but experimental.")
            }
        }
    }
}
```

---

## Backend Integration

### Sending Provider to Worker

Update `BookshelfAIService.swift` to send selected provider in request:

```swift
@MainActor
public class BookshelfAIService {
    // Read user preference
    @AppStorage("aiProvider") private var selectedProvider: AIProvider = .gemini

    public func processBookshelfImageWithWebSocket(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {

        // Prepare image data
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw .imageCompressionFailed
        }

        // Build request with provider header
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(selectedProvider.rawValue, forHTTPHeaderField: "X-AI-Provider") // NEW
        request.httpBody = jsonData

        // ... rest of implementation
    }
}
```

### Worker Handling Provider Header

Update `index.js` to read `X-AI-Provider` header:

```javascript
// In fetch() handler, before calling processBookshelfScan
const requestedProvider = request.headers.get('X-AI-Provider') || env.AI_PROVIDER;

// Override env.AI_PROVIDER for this request only
const requestEnv = { ...env, AI_PROVIDER: requestedProvider };

// Pass modified env to processBookshelfScan
await processBookshelfScan(requestEnv, /* ... */);
```

---

## Testing Checklist

Before shipping AI provider selection:

- [ ] Add AIProvider enum to iOS project
- [ ] Add Settings UI picker with descriptions
- [ ] Update BookshelfAIService to send X-AI-Provider header
- [ ] Update worker to read X-AI-Provider header
- [ ] Test Gemini provider selection (scan completes in 25-40s)
- [ ] Test Cloudflare provider selection (scan completes in 3-8s)
- [ ] Test provider switching mid-session (no crashes)
- [ ] Test with poor network (both providers handle errors gracefully)
- [ ] Verify @AppStorage persists selection across app restarts
- [ ] Add analytics event: `user_switched_ai_provider`

---

## User Communication

### In-App Messaging

When user switches to Cloudflare for the first time:

```swift
.alert("Experimental Feature", isPresented: $showCloudflareWarning) {
    Button("Try It") {
        // Proceed with Cloudflare
    }
    Button("Cancel", role: .cancel) {
        selectedProvider = .gemini
    }
} message: {
    Text("Cloudflare AI is 5-8x faster than Gemini but may have lower accuracy. This is an experimental feature. You can always switch back to Gemini in Settings.")
}
```

### Settings Footer Text

```
"Gemini (Accurate) is recommended for most users. Cloudflare (Fast) is experimental and may miss some books, but provides results much faster. Try both and see which works better for your bookshelves!"
```

---

## Analytics & Monitoring

Track provider usage to inform future defaults:

```swift
// Analytics events
Analytics.logEvent("bookshelf_scan_started", parameters: [
    "ai_provider": selectedProvider.rawValue,
    "scan_id": scanID
])

Analytics.logEvent("bookshelf_scan_completed", parameters: [
    "ai_provider": selectedProvider.rawValue,
    "books_detected": detectedBooks.count,
    "processing_time_seconds": processingTime,
    "scan_id": scanID
])

Analytics.logEvent("ai_provider_switched", parameters: [
    "from_provider": previousProvider.rawValue,
    "to_provider": selectedProvider.rawValue
])
```

**Key metrics to track:**
- Provider distribution (% Gemini vs % Cloudflare)
- Success rates by provider
- User retention after trying Cloudflare
- Processing time distributions
- Books detected per scan (by provider)

---

## Future Enhancements

### Phase 1: Basic Selection (Described Above)
- Settings toggle
- Manual provider selection
- Header-based routing

### Phase 2: Smart Defaults
- Auto-detect based on network speed (slow network → Cloudflare)
- Auto-detect based on image size (large image → Cloudflare)
- A/B test default provider for new users

### Phase 3: Hybrid Mode
- Try Cloudflare first (fast)
- If confidence <0.7, retry with Gemini (accurate)
- Best of both worlds: fast when possible, accurate when needed

### Phase 4: Per-Scan Selection
- Quick toggle on scanner camera view
- "Fast Mode" button for quick scans
- "Accurate Mode" button for detailed scans

---

## Related Files

- `SettingsView.swift` - Settings UI
- `BookshelfAIService.swift` - API communication
- `cloudflare-workers/bookshelf-ai-worker/src/index.js` - Worker routing
- `docs/guides/ios-image-preprocessing-for-ai.md` - Preprocessing guide
- `docs/research/cloudflare-ai-models-evaluation.md` - Provider comparison

---

**Document Version:** 1.0
**Status:** Ready for Implementation
**Estimated Effort:** 2-3 hours
