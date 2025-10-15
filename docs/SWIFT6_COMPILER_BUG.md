# Swift 6 Compiler Bug: @MainActor TaskGroup Capture List

**Status:** ✅ RESOLVED
**Filed:** October 15, 2025
**Resolved:** October 15, 2025
**Severity:** Was High (blocked progress tracking feature)

## Issue Summary

Swift 6.1 region isolation checker failed to verify `@MainActor` closures with capture lists inside `TaskGroup` contexts.

## Resolution

**Root Cause:** The pattern was fundamentally incorrect. TaskGroup with Timer.publish + @MainActor [self] capture lists violates Swift 6 isolation rules.

**Solution:** Use `Task` with `Task.sleep` instead of `TaskGroup` with `Timer.publish`. This properly separates concerns:
- Background Task handles polling loop with `Task.sleep(for: .milliseconds(100))`
- Calls `await progressHandler(...)` to update MainActor-isolated UI
- Calls `await self.pollJobStatus(...)` to access actor-isolated methods
- Uses `withTaskCancellationHandler` for clean cancellation

**Pattern:**
```swift
nonisolated func animateProgressWithPolling(...) async throws -> BookshelfAIResponse {
    return try await withTaskCancellationHandler {
        try await Task<BookshelfAIResponse, Error> {
            while !Task.isCancelled {
                let progress = calculateExpectedProgress(...)  // nonisolated method
                await progressHandler(progress, stage, elapsed, booksDetected)  // MainActor callback

                if shouldPoll {
                    let status = try await pollJobStatus(...)  // actor method
                    if status.isDone { return status.result }
                }

                try await Task.sleep(for: .milliseconds(100))  // ← Key: replaces Timer.publish
            }
        }.value
    } onCancel: { }
}
```

**Key Insight:** Don't force a closure to live in two isolation domains (actor + MainActor). Let the Task boundary handle isolation transitions naturally.

## Compiler Error

**File:** `BookshelfAIService.swift:322`
**Error:** `pattern that the region based isolation checker does not understand how to check. Please file a bug`

## Minimal Reproduction

```swift
actor BookshelfAIService {
    nonisolated private func animateProgressWithPolling(...) async throws -> BookshelfAIResponse {
        return try await withThrowingTaskGroup(of: BookshelfAIResponse?.self) { group in
            group.addTask { @MainActor [self] in  // ← LINE 322: COMPILER BUG
                var currentStageIndex = 0  // MainActor-isolated state
                var lastPollTime: TimeInterval = 0

                for await _ in Timer.publish(...).values {
                    let progress = self.calculateExpectedProgress(...)  // Needs self
                    if self.shouldPollNow(...) {  // Needs self
                        let status = try? await self.pollJobStatus(...)  // Needs self
                    }
                }
                return nil
            }
        }
    }

    nonisolated private func calculateExpectedProgress(...) -> Double { ... }
    nonisolated private func shouldPollNow(...) -> Bool { ... }
    private func pollJobStatus(...) async throws -> JobStatusResponse { ... }
}
```

## Attempts Made

| Approach | Result |
|----------|--------|
| `@MainActor [self]` | ❌ Compiler bug |
| `@MainActor [weak self]` | ❌ Compiler bug |
| `@MainActor [unowned self]` | ❌ Compiler bug |
| `let service = self; @MainActor in (use service)` | ❌ Still fails |
| Removing capture list entirely | ❌ "requires explicit use of 'self'" errors |
| `@MainActor` without capture + implicit self | ❌ Same error |

## Why This Pattern Exists

**Context:** Bookshelf AI scanner with 40-70 second processing time needs live progress updates.

**Architecture:**
1. POST /scan → Returns jobId immediately (202 Accepted)
2. Background AI processing updates KV state
3. iOS polls GET /scan/status/:jobId every 5-10s
4. Local timer animates progress smoothly between polls

**Why @MainActor Task:**
- Timer.publish requires main thread
- ProgressState is @Observable (@MainActor isolated)
- UI updates via progressHandler callback

**Why [self] Capture:**
- Need to call `self.calculateExpectedProgress()` (nonisolated method)
- Need to call `self.shouldPollNow()` (nonisolated method)
- Need to call `self.pollJobStatus()` (async actor method)

**Why TaskGroup:**
- Need to await completion or timeout
- Need cancellation when result arrives
- Need error propagation

## Impact

### Backend: ✅ COMPLETE & DEPLOYED

```javascript
// POST /scan
{
  "jobId": "ee0e157f-559d-4b65-b474-587e9ae86973",
  "stages": [
    { "name": "uploading", "typicalDuration": 5, "progress": 0.0 },
    { "name": "analyzing", "typicalDuration": 35, "progress": 0.1 },
    { "name": "enriching", "typicalDuration": 10, "progress": 0.8 }
  ],
  "estimatedRange": [40, 70]
}

// GET /scan/status/:jobId
{
  "stage": "analyzing",
  "elapsedTime": 25,
  "booksDetected": 12,
  "result": null  // Populated when complete
}
```

**Workers Deployed:**
- ✅ KV namespace: `SCAN_JOBS` (5min TTL)
- ✅ POST /scan returns jobId < 500ms
- ✅ Background processing via `ctx.waitUntil()`
- ✅ Status polling with 404 handling

**Local Testing:** Verified with `wrangler dev`

### iOS: ✅ COMPLETE

**Completed:**
- ✅ Progress models (`ScanProgressModels.swift`)
  - `ScanJobResponse`: POST /scan response
  - `JobStatusResponse`: GET /scan/status response
  - `ScanProgressState`: @Observable UI state
- ✅ Service integration (`BookshelfAIService.swift` - Task 5)
  - `processBookshelfImageWithProgress()` method
  - `animateProgressWithPolling()` using Swift 6.2 Task pattern
  - `startScanJob()`, `pollJobStatus()` networking
  - Zero compiler errors, zero warnings

**Remaining Tasks:**
- ⏸️ View integration (Task 6 - ready to implement)
- ⏸️ Model integration (Task 7 - ready to implement)
- ⏸️ Error UI (Task 8 - ready to implement)

## Files Affected

### Implementation (✅ FIXED)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
  - Lines 125-159: `processBookshelfImageWithProgress()` public API
  - Lines 278-456: Progress tracking methods using Swift 6.2 Task pattern

### Models (Ready to Use)
- `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/ScanProgressModels.swift`

### Backend (Deployed)
- `cloudflare-workers/bookshelf-ai-worker/src/index.js`
  - Lines 200-259: POST /scan (async job creation)
  - Lines 261-314: GET /scan/status/:jobId (polling)
  - Lines 112-175: Background processing (`processBookshelfScan`)

### Documentation
- `docs/plans/2025-10-15-bookshelf-progress-tracking.md`
- `cloudflare-workers/bookshelf-ai-worker/wrangler.toml` (KV binding)

## Timeline

| Date | Event |
|------|-------|
| Oct 15, 2025 | Backend deployed (Tasks 1-3) ✅ |
| Oct 15, 2025 | iOS models created (Task 4) ✅ |
| Oct 15, 2025 | Compiler bug discovered (Task 5) |
| Oct 15, 2025 | Implementation commented out |
| Oct 15, 2025 | **Pattern rewrite with Task + Task.sleep** ✅ |
| Oct 15, 2025 | **Build succeeds - Task 5 COMPLETE** ✅ |

## Implementation Notes

**What Didn't Work:**
- TaskGroup + Timer.publish + @MainActor [self] → Compiler bug
- Any variation of capture lists in TaskGroup (@MainActor context)

**What Worked:**
- Single `Task` with `while !Task.isCancelled` loop
- `Task.sleep(for: .milliseconds(100))` replaces `Timer.publish`
- `await progressHandler(...)` for MainActor callbacks
- `await self.pollJobStatus(...)` for actor methods
- `withTaskCancellationHandler` for cleanup

**Next Steps:**
- ✅ Task 5 complete - service layer ready
- ⏸️ Task 6: Update `BookshelfScannerView` with progress UI
- ⏸️ Task 7: Update `BookshelfScanModel` integration
- ⏸️ Task 8: Add error UI for failed scans

## Lessons Learned

**❌ Don't try to force multiple isolation domains into one closure:**
```swift
// BAD: Mixing actor isolation + MainActor in TaskGroup
group.addTask { @MainActor [self] in
    // Compiler can't verify this is safe
}
```

**✅ Let Task boundaries handle isolation transitions:**
```swift
// GOOD: Single Task with natural await points
Task {
    while !Task.isCancelled {
        let data = calculateSomething()  // nonisolated
        await updateUI(data)  // MainActor transition
        await fetchData()  // actor transition
        try await Task.sleep(...)  // suspension point
    }
}
```

**Key Takeaway:** Swift 6 concurrency is about **separation of concerns**. Don't fight the type system - redesign the pattern to work with isolation domains, not against them.

## References

- Plan: `docs/plans/2025-10-15-bookshelf-progress-tracking.md`
- Backend: `cloudflare-workers/bookshelf-ai-worker/` (✅ Deployed)
- Models: `BooksTrackerPackage/.../ScanProgressModels.swift` (✅ Complete)
- Service: `BooksTrackerPackage/.../BookshelfAIService.swift` (✅ Fixed)

---

**Documentation Purpose:** This file remains as a case study for Swift 6 concurrency patterns. The blocker is resolved, but the learnings are valuable for future development.
