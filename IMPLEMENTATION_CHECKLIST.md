# Bookshelf Scanner Fixes: Implementation Checklist

**Owner:** [Your name] | **Start Date:** [Date] | **Target Completion:** [Date + 1 week]

---

## Pre-Implementation Review

- [ ] Read EXECUTIVE_SUMMARY_BOOKSHELF_SCANNER_FIXES.md
- [ ] Read BOOKSHELF_SCANNER_RACE_CONDITION_ANALYSIS.md
- [ ] Review BOOKSHELF_SCANNER_FIXES_IMPLEMENTATION_GUIDE.md
- [ ] Review BOOKSHELF_SCANNER_SERVER_CODE.md
- [ ] Get stakeholder approval on approach

---

## iOS Implementation (2-3 hours)

### Code Changes
- [ ] Review WebSocketProgressManager.swift changes
  - [ ] New `ConnectionToken` struct added
  - [ ] `establishConnection()` method implemented
  - [ ] `configureForJob()` method implemented
  - [ ] `waitForConnection()` helper added
  - [ ] `signalWebSocketReady()` helper added
  - [ ] PING/PONG messages filtered in handleMessage()

- [ ] Review BookshelfAIService.swift changes
  - [ ] `processBookshelfImageWithWebSocket()` reordered (5 steps)
  - [ ] Step 1: establishConnection() before upload
  - [ ] Step 2: compressImageAdaptive() with cascade
  - [ ] Step 3: startScanJob() with image upload
  - [ ] Step 4: configureForJob() with ready signal
  - [ ] Step 5: connect() with progress handler
  - [ ] `compressImageAdaptive()` method implemented
  - [ ] Fallback `compressImage()` delegates to new method

### Build & Test
- [ ] `xcodebuild clean` - Clear derived data
- [ ] `xcodebuild -workspace BooksTracker.xcworkspace -scheme BooksTracker build`
- [ ] Verify zero warnings
- [ ] Verify zero errors
- [ ] Simulator test: App launches without crashes

### Local Testing
- [ ] Open BooksTrackerView in Xcode
- [ ] Click "Scan Bookshelf (Beta)"
- [ ] Monitor console logs:
  - [ ] "WebSocket established (ready for job configuration)"
  - [ ] "Image uploaded successfully"
  - [ ] "Server notified WebSocket ready"
  - [ ] Progress updates flowing (10%, 30%, 70%, 100%)

---

## Server Implementation (1-2 hours)

### Code Review
- [ ] Read existing `/cloudflare-workers/bookshelf-ai-worker/src/index.js`
- [ ] Understand POST /scan handler (line ~297)
- [ ] Understand processBookshelfScan() function (line ~94)
- [ ] Understand updateJobState() function (line ~190)

### Code Changes
- [ ] Add POST /scan/ready/:jobId endpoint
  - [ ] Exact code from BOOKSHELF_SCANNER_SERVER_CODE.md (Change #1)
  - [ ] Location: After health check endpoints, before POST /scan
  - [ ] Verify: Updates job state with webSocketReady flag
  - [ ] Verify: Returns 204 No Content

- [ ] Update POST /scan handler
  - [ ] Exact code from BOOKSHELF_SCANNER_SERVER_CODE.md (Change #2)
  - [ ] Location: Store initial job state (line ~324)
  - [ ] Add: webSocketReady: false flag
  - [ ] Verify: No other changes to POST /scan logic

- [ ] Add WebSocket ready wait-loop
  - [ ] Exact code from BOOKSHELF_SCANNER_SERVER_CODE.md (Change #3)
  - [ ] Location: Start of processBookshelfScan() function
  - [ ] Add: 5-second max wait time
  - [ ] Verify: Checks every 100ms
  - [ ] Verify: Logs "WebSocket ready after Xms"

### Build & Test
- [ ] `npm run build` in bookshelf-ai-worker directory
- [ ] Verify zero build errors
- [ ] Verify zero TypeScript/syntax errors

### Local Testing (with wrangler)
- [ ] `wrangler dev` - Start local worker
- [ ] Test POST /scan endpoint
  - [ ] Upload test image
  - [ ] Receive 202 with jobId
  - [ ] Verify response includes stages metadata
- [ ] Test POST /scan/ready/:jobId endpoint
  - [ ] Call with valid jobId
  - [ ] Receive 204 No Content
  - [ ] Verify KV updates webSocketReady flag
- [ ] Test processBookshelfScan() wait-loop
  - [ ] Monitor logs for "Waiting for WebSocket..."
  - [ ] Call POST /scan/ready/:jobId
  - [ ] Monitor logs for "WebSocket ready after Xms"

### Deploy to Staging
- [ ] Deploy bookshelf-ai-worker to staging environment
- [ ] Verify: No errors in Cloudflare dashboard
- [ ] Verify: POST /scan returns 202 with jobId
- [ ] Verify: POST /scan/ready returns 204

---

## Integration Testing (1-2 hours)

### E2E Test 1: Race Condition Fix
- [ ] iOS and server both updated
- [ ] Start bookshelf scan on real device
- [ ] Verify: WebSocket connects immediately (log: "established")
- [ ] Verify: Image uploads successfully
- [ ] Verify: "WebSocket ready" signal sent (log in server)
- [ ] Verify: All 22 progress updates received
  - [ ] Progress: 10%, 30%, 70%, 100% visible in UI
  - [ ] Time delta: 10% arrives within 500ms
- [ ] Verify: No "WebSocket not ready" errors in Cloudflare logs

### E2E Test 2: Image Compression
- [ ] On iPhone 15 Pro (12MP camera)
- [ ] Take bookshelf photo (largest possible)
- [ ] Monitor compression logs:
  - [ ] "Compression: Image size: XXXkB"
  - [ ] Should show final size <10MB
  - [ ] Should show resolution used (1920px, 1280px, etc.)
- [ ] Verify: Image uploads successfully
- [ ] Verify: Scan completes normally (30-50 seconds)

### E2E Test 3: Backward Compatibility
- [ ] Old iOS app (before WebSocket-first changes)
- [ ] Start scan
- [ ] Verify: Server waits 5 seconds for ready signal
- [ ] Verify: Timeout, falls back to polling
- [ ] Verify: Scan still completes (just slower progress)

### Real Device Testing
- [ ] iPhone 15 Pro (12MP): Full scan cycle
  - [ ] WebSocket connection: ~100ms
  - [ ] Image upload: ~5-10s
  - [ ] Processing: 30-50s
  - [ ] Total: 35-60s
  
- [ ] iPhone SE (8MP): Full scan cycle
  - [ ] Verify: Smaller image, faster upload
  - [ ] Verify: Compression uses 1920px quality
  
- [ ] iPad (landscape): Full scan cycle
  - [ ] Verify: Wide aspect ratio handled
  - [ ] Verify: Compression adapts to dimensions

### Cellular Network Testing
- [ ] Disable WiFi, use 4G/5G only
- [ ] Start scan
- [ ] Monitor upload time (may be slower)
- [ ] Verify: Compression not impacted
- [ ] Verify: WebSocket connects despite higher latency

---

## Monitoring & Verification (Ongoing)

### Cloudflare Logs (First 24 hours)
- [ ] Monitor: Zero "WebSocket not ready" errors
- [ ] Monitor: All scans reach "complete" stage
- [ ] Monitor: No pushProgress() failures
- [ ] Monitor: WebSocket ready times (should be <500ms)

### iOS Console Logs (First 24 hours)
- [ ] Monitor: "WebSocket connection established" 100%
- [ ] Monitor: "Image uploaded successfully" 100%
- [ ] Monitor: "Server notified WebSocket ready" 100%
- [ ] Monitor: No compression fallback warnings

### Success Metrics (After 48 hours)
- [ ] Scan success rate: >99%
- [ ] Progress updates received: 22/22 (100%)
- [ ] Compression rejections: 0%
- [ ] Average scan time: 30-50s (unchanged)
- [ ] User complaints about "no progress": Zero

---

## Performance Validation

### Compression Metrics
- [ ] Average image size before: 2-5MB
- [ ] Average image size after: 1.5-2.5MB (30% reduction)
- [ ] Compression algorithm cascade usage:
  - [ ] 1920px used: ~90% of scans
  - [ ] 1280px used: ~9% of scans
  - [ ] 960px or less: <1% of scans

### WebSocket Metrics
- [ ] Connection time: <200ms (new)
- [ ] Ready signal response: <100ms
- [ ] Progress update latency: 50-200ms (near real-time)
- [ ] Total overhead: <500ms (acceptable)

### Detection Accuracy
- [ ] Compare detection rates before/after compression
- [ ] Should be identical (compression transparent to AI)
- [ ] Monitor: Any change in book detection rate
- [ ] Expected: <0.1% variance (statistical noise only)

---

## Rollback Plan

### If Critical Issues Found

#### Option 1: Fast Rollback (Server only)
- [ ] Stop iOS deployment
- [ ] Revert server POST /scan/ready endpoint (keep silent)
- [ ] Remove wait-loop from processBookshelfScan()
- [ ] Old iOS clients fall back to polling (works fine)
- [ ] Time: <30 minutes

#### Option 2: Full Rollback (Both)
- [ ] Pull iOS from production
- [ ] Revert all server changes
- [ ] Redeploy old code
- [ ] All clients revert to original behavior
- [ ] Time: <1 hour

---

## Documentation Updates

- [ ] CHANGELOG.md: Document fixes and improvements
- [ ] Update README.md if instructions changed
- [ ] Update any API documentation
- [ ] Create post-mortem if issues occurred
- [ ] Add metrics to project metrics tracker

---

## Stakeholder Communication

### Pre-Deployment
- [ ] Notify team of upcoming changes
- [ ] Share executive summary with stakeholders
- [ ] Get approval from tech lead
- [ ] Notify support team (prepare FAQ)

### During Deployment
- [ ] Post status updates every 2 hours
- [ ] Alert if any rollback triggered
- [ ] Share real-time metrics link

### Post-Deployment
- [ ] Send success notification to team
- [ ] Share before/after metrics
- [ ] Schedule retrospective meeting
- [ ] Update project documentation

---

## Sign-Off

- [ ] **iOS Lead:** Code review approved
  - Name: ___________________
  - Date: ___________________

- [ ] **Backend Lead:** Server code review approved
  - Name: ___________________
  - Date: ___________________

- [ ] **QA Lead:** Testing plan approved
  - Name: ___________________
  - Date: ___________________

- [ ] **Project Lead:** Ready to deploy
  - Name: ___________________
  - Date: ___________________

---

## Timeline

| Phase | Task | Timeline | Owner | Status |
|-------|------|----------|-------|--------|
| 1 | iOS implementation | 2-3 hours | Frontend | [ ] |
| 1 | Server implementation | 1-2 hours | Backend | [ ] |
| 2 | Integration testing | 1-2 hours | QA | [ ] |
| 2 | Server staging deploy | 30 mins | Devops | [ ] |
| 3 | iOS TestFlight | 24 hours | Release | [ ] |
| 3 | Monitor & verify | 48 hours | QA + Ops | [ ] |
| 4 | Gradual rollout | 1 week | Release | [ ] |
| 4 | Full production | 1 week | Release | [ ] |

**Target Completion:** 1 week from start

---

## Notes

- Backward compatible - old clients continue working
- Feature flag recommended for gradual rollout
- Monitor logs heavily first 48 hours
- Have rollback plan ready (but shouldn't need it)
- Celebrate success! This fixes critical production issues

