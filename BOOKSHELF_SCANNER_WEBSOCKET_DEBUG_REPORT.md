# Bookshelf Scanner WebSocket Debugging Report
**Date:** October 23, 2025
**Issue:** NSURLErrorDomain -1011 (Bad Server Response)
**Status:** ✅ RESOLVED - All issues fixed with server-side keep-alive pings

## Executive Summary

The bookshelf scanner feature was failing with `NSURLErrorDomain error -1011` when processing images. Investigation revealed two distinct issues, both now resolved:

1. ✅ **FIXED:** Durable Object RPC configuration (Cloudflare Workers deployment issue)
2. ✅ **RESOLVED:** WebSocket closes prematurely - Fixed with 30s keep-alive pings during AI processing

## Root Cause Analysis

### ✅ RESOLVED: WebSocket Premature Closure

**Solution Implemented:** Server-side keep-alive pings (Phase A)

**Date Resolved:** October 23, 2025

**Fix:** Added 30-second periodic progress updates during AI processing to prevent iOS (60s timeout) and Cloudflare (100s idle timeout) disconnections.

**Code Changes:**
- `bookshelf-ai-worker/src/index.js:167-181` - Keep-alive ping loop with `setInterval`
- `WebSocketProgressManager.swift:293` - Added `keepAlive: Bool?` field to `ProgressData`
- `JobModels.swift:43,55` - Added `keepAlive: Bool?` field to `JobProgress`
- `BookshelfAIService.swift:202-206` - UI optimization to skip keep-alive re-renders

**Verification:**
- ✅ No more NSURLError -1011 failures
- ✅ No more WebSocket code 1006 disconnections
- ✅ Successful scans with 30+ books (40s AI processing)
- ✅ Cloudflare logs show keep-alive pings every 30s
- ✅ iOS logs show "🔁 Keep-alive ping received (skipping UI update)"

---

### Issue 1: Durable Object RPC Error (FIXED)

**Symptom:**
```
TypeError: The receiving Durable Object does not support RPC, because its class was
not declared with `extends DurableObject`
```

**Root Cause:**
The `progress-websocket-durable-object` worker was deployed with outdated code that didn't extend the `DurableObject` class properly, preventing RPC method calls from `books-api-proxy`.

**Fix Applied:**
```bash
# Redeployed all three workers in correct order:
cd cloudflare-workers/progress-websocket-durable-object && wrangler deploy  # v45749f3a
cd cloudflare-workers/books-api-proxy && wrangler deploy                     # vfbe5657e
cd cloudflare-workers/bookshelf-ai-worker && wrangler deploy                 # v8bcdfacd
```

**Verification:**
RPC calls now succeed - no more "does not support RPC" errors in logs.

---

### Issue 2: WebSocket Premature Closure (ONGOING)

**Symptom:**
```
[66BAEB52-FFDD-4BD0-948A-388D38209DF0] WebSocket closed: 1006
WebSocket disconnected without sending Close frame.
```

**Observed Behavior:**
1. WebSocket connects successfully ✅
2. Progress update 0.1 (10%) - "Analyzing image quality..." ✅
3. Progress update 0.3 (30%) - "Processing with AI..." ✅
4. **WebSocket closes with code 1006** ❌
5. iOS never receives completion message
6. iOS `withCheckedContinuation` waits indefinitely
7. HTTP POST request times out (70s) → NSURLError -1011

**Evidence from Logs:**
```javascript
// Durable Object successfully sends progress:
[ProgressDO] pushProgress called for job 66BAEB52-FFDD-4BD0-948A-388D38209DF0 {
  hasWebSocket: true,
  progressData: { progress: 0.3, currentStatus: 'Processing with AI...' }
}
[66BAEB52-FFDD-4BD0-948A-388D38209DF0] Progress sent successfully

// Then immediately closes:
[66BAEB52-FFDD-4BD0-948A-388D38209DF0] WebSocket closed: 1006
```

**WebSocket Code 1006:** "Abnormal closure - connection closed without sending/receiving a Close frame"

**Possible Causes:**

1. **iOS URLSession Timeout (Most Likely)**
   - iOS has a default WebSocket timeout
   - AI processing takes 25-40s, enrichment adds 5-10s
   - Total: 30-50s processing time
   - WebSocket may have stricter timeout than HTTP request

2. **iOS App Background/Foreground Transition**
   - User may be switching apps during long scan
   - iOS suspends WebSocket connections in background

3. **Network Interruption**
   - Weak cellular connection
   - WiFi handoff during scan
   - Proxy/firewall dropping long-lived WebSocket

4. **iOS WebSocketProgressManager Configuration**
   - `WebSocketProgressManager.swift:36` sets `connectionTimeout: TimeInterval = 10.0`
   - This is for initial handshake, but may affect overall connection
   - No explicit timeout for ongoing connection

5. **Backend Context Timeout**
   - `bookshelf-ai-worker/src/index.js:144-145` - AI processing blocks event loop
   - Cloudflare Workers may timeout WebSocket context during long operations
   - Warning seen: `IoContext timed out due to inactivity, waitUntil tasks were cancelled`

## Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ iOS App (BookshelfScannerView)                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Generate jobId (UUID)                                           │
│  2. Establish WebSocket (wss://books-api-proxy/ws/progress)        │
│  3. Upload image (POST /scan?jobId=UUID)                           │
│  4. Wait for progress via WebSocket                                │
│  5. withCheckedContinuation waits for "complete" message           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                            ↓ Upload
┌─────────────────────────────────────────────────────────────────────┐
│ bookshelf-ai-worker (Cloudflare Worker)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Receive image + jobId                                           │
│  2. Start background processing (processBookshelfScan)             │
│  3. Push progress 0.1 → books-api-proxy.pushJobProgress()         │
│  4. Process with Gemini AI (25-40s) 🕐                             │
│  5. Push progress 0.3 ← WEBSOCKET CLOSES HERE ❌                   │
│  6. Enrich books (5-10s) [NEVER REACHED]                           │
│  7. Push progress 1.0 + "complete" [NEVER SENT]                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                            ↓ RPC Call
┌─────────────────────────────────────────────────────────────────────┐
│ books-api-proxy (RPC Service)                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  pushJobProgress(jobId, progressData) {                            │
│    const stub = env.PROGRESS_WEBSOCKET_DO.get(doId)               │
│    await stub.pushProgress(progressData)  ✅ RPC WORKS NOW        │
│  }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                            ↓ RPC Call
┌─────────────────────────────────────────────────────────────────────┐
│ ProgressWebSocketDO (Durable Object)                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  pushProgress(progressData) {                                       │
│    this.webSocket.send(JSON.stringify(progressData))              │
│    ✅ Messages sent successfully                                   │
│    ❌ Connection closes at 0.3 (code 1006)                         │
│  }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Code Locations

### iOS Client
- **Main Service:** `BooksTrackerPackage/Sources/BooksTrackerFeature/BookshelfScanning/Services/BookshelfAIService.swift`
  - Line 153-248: `processBookshelfImageWithWebSocket()` - WebSocket flow
  - Line 198-237: `withCheckedContinuation` waiting for "complete" message
  - Line 85: `timeout: TimeInterval = 70.0` - HTTP request timeout

- **WebSocket Manager:** `BooksTrackerPackage/Sources/BooksTrackerFeature/Common/WebSocketProgressManager.swift`
  - Line 36: `connectionTimeout: TimeInterval = 10.0` - Initial handshake timeout
  - Line 216-227: `startReceiving()` - Message receive loop
  - Line 220-224: Error handling that calls `disconnect()` on any error

### Backend Workers
- **AI Worker:** `cloudflare-workers/bookshelf-ai-worker/src/index.js`
  - Line 94-209: `processBookshelfScan()` - Background processing function
  - Line 124-142: Progress stage 1 & 2 (0.1 → 0.3)
  - Line 144-145: **AI processing (blocks here 25-40s)**
  - Line 156-169: Progress stage 3 & 4 (0.7 → 1.0) - Never reached

- **API Proxy:** `cloudflare-workers/books-api-proxy/src/index.js`
  - Line 65-79: `pushJobProgress()` - RPC method (now working)

- **Durable Object:** `cloudflare-workers/progress-websocket-durable-object/src/index.js`
  - Line 7: `extends DurableObject` - Fixed!
  - Line 89-118: `pushProgress()` - RPC method implementation

## Attempted Fixes

### ✅ Successfully Fixed
1. Redeployed `progress-websocket-durable-object` with proper `DurableObject` extension
2. Redeployed `books-api-proxy` to bind to updated Durable Object
3. Redeployed `bookshelf-ai-worker` to bind to updated API proxy
4. **Result:** RPC errors eliminated, progress updates now flowing

### ❌ Didn't Resolve NSURLError -1011
- WebSocket still closes at 30% progress
- iOS never receives completion message
- HTTP request times out waiting for response

## Proposed Solutions

### Option 1: Increase iOS WebSocket Timeout (Quick Fix)
**Change:** Modify `WebSocketProgressManager.swift` to keep connection alive longer
```swift
// Current (implicit timeout)
private var webSocketTask: URLSessionWebSocketTask?

// Proposed (explicit configuration)
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 120.0  // 2 minutes
config.timeoutIntervalForResource = 120.0
let session = URLSession(configuration: config)
```

**Pros:** Simple change, may resolve timeout issue
**Cons:** Doesn't address root cause of slow processing

### Option 2: Server-Side Keep-Alive Pings (Recommended)
**Change:** Have Durable Object send periodic PING messages during AI processing
```javascript
// In processBookshelfScan(), during AI processing:
const pingInterval = setInterval(async () => {
  await pushProgress(env, jobId, {
    progress: 0.3,
    currentStatus: 'Still processing...',
    keepAlive: true
  });
}, 5000);  // Every 5 seconds

const result = await worker.scanBookshelf(imageData);
clearInterval(pingInterval);
```

**Pros:** Prevents WebSocket idle timeout, shows activity
**Cons:** More network traffic

### Option 3: Switch to HTTP Polling (Fallback)
**Change:** Use `pollJobStatus()` instead of WebSocket for progress
```swift
// Already implemented! BookshelfAIService.swift:440-473
func pollJobStatus(jobId: String) async throws -> JobStatusResponse
```

**Pros:** More reliable, simpler
**Cons:** Higher latency (polling delay), more server requests

### Option 4: Hybrid Approach (Most Robust)
**Change:** Use WebSocket as primary, fallback to polling if WebSocket fails
```swift
func processBookshelfImageWithWebSocket(...) async throws {
    do {
        // Try WebSocket first
        return try await processViaWebSocket(image, progressHandler)
    } catch {
        print("⚠️ WebSocket failed, falling back to polling")
        // Fallback to polling
        return try await processViaPolling(image, progressHandler)
    }
}
```

**Pros:** Best of both worlds, resilient
**Cons:** More complex implementation

### Option 5: Optimize AI Processing Speed (Long-term)
**Change:** Reduce AI processing time to stay under timeout
- Use smaller Gemini model (2.5 Flash Lite vs 2.5 Flash)
- Reduce image resolution before upload
- Pre-process image on client (crop, enhance)
- Cache common bookshelf patterns

**Pros:** Better UX overall
**Cons:** May reduce accuracy

## Additional Observations

### Cloudflare Worker Context Timeout
The warning `IoContext timed out due to inactivity` suggests the worker execution context expires during long AI calls. This might be related to:
- Cloudflare Workers CPU time limits (30s for Paid tier)
- The `await worker.scanBookshelf(imageData)` call blocks event loop
- WebSocket context may be separate from main request context

**Potential Fix:** Move AI processing to a separate worker triggered by `ctx.waitUntil()`:
```javascript
// Don't await AI processing in main request handler
ctx.waitUntil(processBookshelfScan(jobId, imageData, env));

// Return immediately after starting job
return new Response(JSON.stringify({ jobId, status: 'processing' }), {
  status: 202
});
```

This matches the current architecture but may need WebSocket context preservation.

## Recommended Next Steps

### Immediate (Quick Win)
1. **Add server-side keep-alive pings** (Option 2) during AI processing
2. **Test with new deployment** to confirm WebSocket stays alive

### Short-term (Resilience)
3. **Implement hybrid WebSocket + polling fallback** (Option 4)
4. **Add explicit iOS URLSession timeout configuration** (Option 1)
5. **Add WebSocket reconnection logic** if connection drops

### Long-term (Optimization)
6. **Profile AI processing time** - measure Gemini API latency
7. **Consider worker architecture change** - separate HTTP from WebSocket context
8. **Investigate Cloudflare Workers AI** as alternative to external Gemini API
9. **Implement client-side image preprocessing** to reduce processing time

## Testing Checklist

When implementing fixes, test these scenarios:
- [ ] Normal scan with good network (should work if timeout fixed)
- [ ] Scan with slow network (tests resilience)
- [ ] Scan then switch to another app (tests background behavior)
- [ ] Scan with airplane mode toggle mid-process (tests reconnection)
- [ ] Large bookshelf image (30+ books) to maximize processing time
- [ ] Monitor all three worker logs simultaneously during test

## Deployment Versions

**Current Production Versions:**
- `progress-websocket-durable-object`: v45749f3a-49a7-49c3-b9e2-0f6c7c0d18f3
- `books-api-proxy`: vfbe5657e-b6c8-4458-9374-5abf8a158b10
- `bookshelf-ai-worker`: v8bcdfacd-a2a1-4e2e-9e76-ed4d461f4403

**Deployed:** October 23, 2025, 2:45 PM PST

## Conclusion

The RPC infrastructure is now working correctly (progress updates successfully flowing from worker → Durable Object). The remaining issue is WebSocket connection stability during long-running AI processing (25-40s).

**Most Likely Cause:** iOS URLSession WebSocket has an implicit timeout that's shorter than AI processing time, causing premature disconnection and NSURLError -1011 when the HTTP request can't complete.

**Recommended Fix:** Implement server-side keep-alive pings + hybrid WebSocket/polling fallback for maximum reliability.
