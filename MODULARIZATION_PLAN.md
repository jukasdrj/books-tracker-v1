### **Consolidated Plan: AI Modularization & Human-in-the-Loop Review**

This plan integrates the AI provider abstraction and the user review queue into the project's existing RPC-based microservice architecture.

#### **Phase 1: Foundational Refactoring (AI Worker)**

**Objective:** Decouple the `bookshelf-ai-worker` from Gemini and align it with the project's established RPC patterns.

1.  **Create AI Provider Abstraction:**
    *   **Action:** In `bookshelf-ai-worker/src`, create a `providers` directory.
    *   **Details:** Define a standard `AIProvider` interface with a `scanImage(imageData, env)` method.

2.  **Implement `GeminiProvider`:**
    *   **Action:** Create `src/providers/geminiProvider.js`.
    *   **Details:** Move the Gemini-specific API call logic from `index.js` into this new module. It will implement the `AIProvider` interface.

3.  **Create `AIProviderFactory`:**
    *   **Action:** In `index.js`, create a factory that reads `env.AI_PROVIDER` from `wrangler.toml` (e.g., `"gemini"` or `"cloudflare"`) and returns the correct provider instance.

4.  **Refactor the Main Worker Logic:**
    *   **Action:** Update the `BookshelfAIWorker` class in `index.js`.
    *   **Details:** The `scanBookshelf` RPC method will now use the factory to get the current provider and call `provider.scanImage()`. This removes all direct knowledge of Gemini from the main logic.

5.  **Add `needsReview` Flag:**
    *   **Action:** In the `scanBookshelf` method, after receiving results from the provider, iterate through the detected books.
    *   **Details:** Add the `needsReview: true` flag to any book with a confidence score below a configurable threshold (e.g., `env.CONFIDENCE_THRESHOLD || 0.4`). This prepares the backend for the HITL feature.

---

#### **Phase 2: Cloudflare Workers AI Integration**

**Objective:** Implement a high-performance AI provider using Cloudflare's native AI and make it the default.

1.  **Implement `CloudflareProvider`:**
    *   **Action:** Create `src/providers/cloudflareProvider.js`.
    *   **Details:** Implement the `AIProvider` interface using the `env.AI` binding to call a suitable Cloudflare Workers AI vision model. This will involve formatting the request and parsing the response according to the Cloudflare AI API.

2.  **Update `wrangler.toml`:**
    *   **Action:** Modify `bookshelf-ai-worker/wrangler.toml`.
    *   **Details:**
        *   Add the `[ai]` binding to grant the worker access to the Workers AI model.
        *   Change the default provider by setting `[vars] AI_PROVIDER = "cloudflare"`.

3.  **Benchmark and Validate:**
    *   **Action:** Deploy and test both providers.
    *   **Details:** Measure the end-to-end latency (from app upload to final result) for both the `gemini` and `cloudflare` configurations to quantify the performance gains.

---

#### **Phase 3: iOS Data Model & UI Foundation**

**Objective:** Prepare the iOS application to handle and store books requiring human review.

1.  **Update SwiftData Model:**
    *   **Action:** Modify the `Book` entity in the `BooksTrackerPackage`.
    *   **Details:** Add a `reviewStatus` property using a `ReviewStatus` enum (`verified`, `needsReview`, `userEdited`).

2.  **Update App's Network & Persistence Layer:**
    *   **Action:** Modify the code that calls the `/scan` endpoint and saves the results.
    *   **Details:** When parsing the JSON response, check for the `needsReview` flag and map it to the appropriate `ReviewStatus` before saving the `Book` object to SwiftData.

3.  **Create the "Review Queue" View:**
    *   **Action:** Build a new SwiftUI view, `ReviewQueueView.swift`.
    *   **Details:** This view will display a list of all books fetched from SwiftData where `reviewStatus == .needsReview`.

4.  **Add UI Entry Point:**
    *   **Action:** Add a non-intrusive button or link to the main library screen.
    *   **Details:** This button will navigate to the `ReviewQueueView` and should be badged with a count of items needing review to draw user attention without being disruptive.

---

#### **Phase 4: Interactive Correction UI (The Loop)**

**Objective:** Build the user interface that allows users to easily correct low-confidence AI results.

1.  **Implement the Correction View:**
    *   **Action:** Create the `CorrectionView.swift` UI.
    *   **Details:** This view will be presented when a user selects a book from the review queue. It must feature:
        *   The cropped spine image, rendered using the book's stored `boundingBox` coordinates.
        *   Editable text fields for `title` and `author`, pre-filled with the AI's best guess.

2.  **Implement Correction Logic:**
    *   **Action:** Add the saving and data update logic to `CorrectionView`.
    *   **Details:** On save, the app will update the book's `title` and `author` in SwiftData and change its `reviewStatus` to `.userEdited` or `.verified`. The book will then automatically disappear from the review queue.

3.  **Image Persistence Strategy:**
    *   **Action:** Decide on and implement a strategy for storing the original photo.
    *   **Details:** For the correction view to work, the original bookshelf photo must be available. It should be saved to temporary local storage on the device after a scan, and its file path should be associated with the books from that scan session. The file can be deleted once all books from that session are marked as `.verified` or `.userEdited`.