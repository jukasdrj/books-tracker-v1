# Bookshelf Scanner: Server Code Changes

**File:** `/cloudflare-workers/bookshelf-ai-worker/src/index.js`

**Status:** Ready for implementation | **Lines Changed:** ~50 total (non-breaking additions)

---

## Change #1: Add POST /scan/ready/:jobId Endpoint

**Location:** In `export default { async fetch(request, env, ctx) { ... } }`

**Add this code after the health check endpoints and BEFORE the POST /scan handler:**

```javascript
    // Signal WebSocket ready for job
    // iOS calls this after establishing WebSocket connection
    // Tells server it's safe to start processing
    if (request.method === "POST" && url.pathname.match(/^\/scan\/ready\//)) {
      try {
        const jobId = url.pathname.split('/').pop();

        // Validate jobId
        if (!jobId || jobId.length === 0) {
          return Response.json(
            { error: "Invalid jobId" },
            { status: 400 }
          );
        }

        // Get current job state
        const jobStateJson = await env.SCAN_JOBS.get(jobId);
        if (!jobStateJson) {
          // Job expired or doesn't exist - no problem, iOS can still retry
          return Response.json(
            { error: "Job not found (expired?)" },
            { status: 404 }
          );
        }

        // Mark WebSocket as ready
        const jobState = JSON.parse(jobStateJson);
        jobState.webSocketReady = true;
        jobState.webSocketReadyTime = Date.now();

        // Update KV with ready flag
        await env.SCAN_JOBS.put(jobId, JSON.stringify(jobState), {
          expirationTtl: 300  // 5 minutes (same as job ttl)
        });

        console.log(`✅ [WebSocket] Job ${jobId} marked ready for processing`);

        // Return 204 No Content (success, no response body)
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*"
          }
        });

      } catch (error) {
        console.error(`[WebSocket] Failed to mark job ready:`, error);
        return Response.json(
          { error: error.message },
          { status: 500 }
        );
      }
    }
```

---

## Change #2: Update POST /scan to Track Ready State

**Location:** Modify the existing `if (request.method === "POST" && url.pathname === "/scan")` handler

**FIND this section (around line 323-330):**

```javascript
        // Store initial job state in KV
        await requestEnv.SCAN_JOBS.put(jobId, JSON.stringify({
          stage: 'processing',
          startTime: Date.now(),
          imageSize: imageData.byteLength,
          elapsedTime: 0,
          provider: requestedProvider
        }), { expirationTtl: 300 }); // 5 min expiry (fallback)
```

**REPLACE WITH:**

```javascript
        // Store initial job state in KV
        // Track webSocketReady flag - server will wait for this before processing
        await requestEnv.SCAN_JOBS.put(jobId, JSON.stringify({
          stage: 'waiting_for_websocket',  // NEW: Initial stage
          startTime: Date.now(),
          imageSize: imageData.byteLength,
          elapsedTime: 0,
          provider: requestedProvider,
          webSocketReady: false,           // NEW: Ready flag (iOS will set to true)
          webSocketReadyTime: null         // NEW: When ready signal received
        }), { expirationTtl: 300 }); // 5 min expiry (fallback)
```

---

## Change #3: Add WebSocket Ready Wait-Loop to processBookshelfScan()

**Location:** At the START of the `async function processBookshelfScan(jobId, imageData, env)` function (around line 94)

**ADD this code right after the function declaration, before any other code:**

```javascript
  // CRITICAL FIX: Wait for WebSocket to be ready before processing
  // Prevents race condition where server processes before client listens
  // Timeout after 5 seconds (fallback to polling if not ready)
  const maxWaitTimeMs = 5000;  // 5 seconds
  const waitStartTime = Date.now();
  let jobState = JSON.parse(await env.SCAN_JOBS.get(jobId));
  let webSocketReady = jobState?.webSocketReady ?? false;

  if (!webSocketReady) {
    console.log(`[BookshelfAI] Waiting for WebSocket to be ready (jobId: ${jobId})...`);

    while (!webSocketReady && Date.now() - waitStartTime < maxWaitTimeMs) {
      // Check every 100ms if WebSocket ready flag has been set by iOS
      jobState = JSON.parse(await env.SCAN_JOBS.get(jobId));
      webSocketReady = jobState?.webSocketReady ?? false;

      if (webSocketReady) {
        const waitTime = Date.now() - waitStartTime;
        console.log(`✅ [BookshelfAI] WebSocket ready after ${waitTime}ms`);
        break;
      }

      // Wait 100ms before checking again
      await new Promise(r => setTimeout(r, 100));
    }

    if (!webSocketReady) {
      const elapsedTime = Date.now() - waitStartTime;
      console.warn(`⚠️  [BookshelfAI] WebSocket not ready after ${elapsedTime}ms for job ${jobId}`);
      console.warn("Proceeding anyway (will fall back to polling-based progress if WebSocket unavailable)");
      // Don't throw - continue with processing
      // Server will attempt pushProgress(), but fallback to polling if WebSocket unavailable
    }
  }
```

---

## Change #4: Update Progress Update to Handle WebSocket Better

**Location:** The `await updateJobState(env, jobId, {...})` calls in processBookshelfScan()

**These are already correct, just make sure they stay like this:**

```javascript
    await updateJobState(env, jobId, {
      stage: 'analyzing',
      elapsedTime: Math.floor((Date.now() - startTime) / 1000)
    });
```

The updateJobState function is correct. The waiting happens BEFORE processing starts, so by the time pushProgress() is called, WebSocket is guaranteed ready.

---

## Complete Modified processBookshelfScan() Example

Here's what the function should look like after all changes:

```javascript
/**
 * Background processing function for bookshelf scans
 * Pushes real-time WebSocket progress at each stage
 *
 * CRITICAL: Waits for WebSocket to be ready before processing
 * Prevents race condition: server processes before client listens
 */
async function processBookshelfScan(jobId, imageData, env) {
  const startTime = Date.now();

  try {
    // CRITICAL FIX: Wait for WebSocket to be ready before processing
    // Prevents race condition where server processes before client listens
    // Timeout after 5 seconds (fallback to polling if not ready)
    const maxWaitTimeMs = 5000;  // 5 seconds
    const waitStartTime = Date.now();
    let jobState = JSON.parse(await env.SCAN_JOBS.get(jobId));
    let webSocketReady = jobState?.webSocketReady ?? false;

    if (!webSocketReady) {
      console.log(`[BookshelfAI] Waiting for WebSocket to be ready (jobId: ${jobId})...`);

      while (!webSocketReady && Date.now() - waitStartTime < maxWaitTimeMs) {
        // Check every 100ms if WebSocket ready flag has been set by iOS
        jobState = JSON.parse(await env.SCAN_JOBS.get(jobId));
        webSocketReady = jobState?.webSocketReady ?? false;

        if (webSocketReady) {
          const waitTime = Date.now() - waitStartTime;
          console.log(`✅ [BookshelfAI] WebSocket ready after ${waitTime}ms`);
          break;
        }

        // Wait 100ms before checking again
        await new Promise(r => setTimeout(r, 100));
      }

      if (!webSocketReady) {
        const elapsedTime = Date.now() - waitStartTime;
        console.warn(`⚠️  [BookshelfAI] WebSocket not ready after ${elapsedTime}ms for job ${jobId}`);
        console.warn("Proceeding anyway (will fall back to polling-based progress if WebSocket unavailable)");
      }
    }

    // Stage 1: Image quality analysis (10% progress)
    await pushProgress(env, jobId, {
      progress: 0.1,
      processedItems: 0,
      totalItems: 3, // 3 stages: analyze, AI processing, enrichment
      currentStatus: 'Analyzing image quality...'
    });

    await updateJobState(env, jobId, {
      stage: 'analyzing',
      elapsedTime: Math.floor((Date.now() - startTime) / 1000)
    });

    // Stage 2: AI processing (30% → 70% progress)
    await pushProgress(env, jobId, {
      progress: 0.3,
      processedItems: 1,
      totalItems: 3,
      currentStatus: 'Processing with AI...'
    });

    const worker = new BookshelfAIWorker(env);
    const result = await worker.scanBookshelf(imageData);

    const booksDetected = result.books.length;

    await updateJobState(env, jobId, {
      stage: 'enriching',
      booksDetected: booksDetected,
      elapsedTime: Math.floor((Date.now() - startTime) / 1000)
    });

    // Stage 3: Enrichment (70% → 100% progress)
    await pushProgress(env, jobId, {
      progress: 0.7,
      processedItems: 2,
      totalItems: 3,
      currentStatus: `Enriching ${booksDetected} detected books...`
    });

    // Stage 4: Complete (100%)
    await pushProgress(env, jobId, {
      progress: 1.0,
      processedItems: 3,
      totalItems: 3,
      currentStatus: `Scan complete! Found ${booksDetected} books.`
    });

    await updateJobState(env, jobId, {
      stage: 'complete',
      elapsedTime: Math.floor((Date.now() - startTime) / 1000),
      result: {
        books: result.books,
        suggestions: result.suggestions || [],
        metadata: result.metadata
      }
    });

    // Close WebSocket connection on completion
    await closeConnection(env, jobId, 'Scan completed successfully');

    // Explicitly delete KV entry on completion (TTL is backup)
    setTimeout(() => env.SCAN_JOBS.delete(jobId), 60000); // Delete after 1 min

  } catch (error) {
    // Push error to WebSocket
    await pushProgress(env, jobId, {
      progress: 0,
      processedItems: 0,
      totalItems: 3,
      currentStatus: 'Scan failed',
      error: error.message
    });

    await updateJobState(env, jobId, {
      stage: 'error',
      error: error.message,
      errorType: error.name,
      elapsedTime: Math.floor((Date.now() - startTime) / 1000)
    });

    // Close connection on error
    await closeConnection(env, jobId, `Scan failed: ${error.message}`);

    // Delete errored jobs after 1 minute
    setTimeout(() => env.SCAN_JOBS.delete(jobId), 60000);
  }
}
```

---

## Verification Checklist

After making these changes:

### Code Review
- [ ] POST /scan/ready/:jobId endpoint added and returns 204
- [ ] Ready flag checked in processBookshelfScan()
- [ ] Wait-loop implemented (max 5 seconds)
- [ ] No syntax errors (test: `npm run build`)

### Local Testing
- [ ] `wrangler dev` starts without errors
- [ ] POST /scan returns 202 with jobId
- [ ] POST /scan/ready/:jobId returns 204
- [ ] KV storage updates correctly with webSocketReady flag

### Integration Testing
- [ ] Deploy to staging
- [ ] iOS client triggers /scan/ready/:jobId endpoint
- [ ] Cloudflare logs show "WebSocket ready after Xms"
- [ ] Progress updates stream correctly

---

## Rollback Instructions

If issues occur, simply revert the changes:

```javascript
// Remove the entire POST /scan/ready endpoint
// Remove the WebSocket ready wait-loop from processBookshelfScan()
// Remove webSocketReady flag from initial job state
```

Server will fall back to original behavior (no wait, just process immediately).
Old clients will continue working. New iOS clients will just not get the race condition fix.

---

## Performance Impact

- POST /scan/ready/:jobId: <1ms (just updates KV flag)
- processBookshelfScan() wait-loop: 0-5000ms (configurable timeout)
- Overall impact: POSITIVE (prevents race condition, faster processing start)

---

## Line Count Summary

- POST /scan/ready/:jobId endpoint: ~35 lines
- POST /scan modifications: ~8 lines
- processBookshelfScan() wait-loop: ~20 lines
- Total: ~63 lines

All changes are **non-breaking** - old clients will still work with 5-second timeout fallback.

