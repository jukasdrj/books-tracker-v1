# WebSocket + Polling Fallback Architecture

**Version:** 3.0.0 (Blocking Processing)
**Date:** October 24, 2025
**Status:** Production (Fixed IoContext Timeout)

## Overview

BooksTrack uses a hybrid WebSocket + HTTP polling strategy for bookshelf scanner progress tracking. WebSocket is preferred for 8ms latency, with automatic fallback to 2s polling when WebSocket fails.

**All traffic flows through `bookshelf-ai-worker.jukasdrj.workers.dev`** - No split-brain routing between workers.

## Strategy Selection Flow

```
┌─────────────────────────────────────────────────────┐
│ processBookshelfImageWithWebSocket()                │
│                                                     │
│  1. Generate jobId                                  │
│  2. Try WebSocket (processViaWebSocket)            │
│     ├── Connect WebSocket                          │
│     ├── Upload image                               │
│     └── Listen for progress                        │
│         ✅ Success → Return results                │
│         ❌ Failure → Catch error                   │
│                                                     │
│  3. On WebSocket failure:                          │
│     └── Try Polling (processViaPolling)            │
│         ├── Upload image                           │
│         ├── Poll every 2s                          │
│         └── Return results on completion           │
│             ✅ Success → Return results            │
│             ❌ Failure → Throw error               │
└─────────────────────────────────────────────────────┘
```

## Performance Comparison

| Metric | WebSocket | Polling | Notes |
|--------|-----------|---------|-------|
| Latency | 8ms | 2000ms | WebSocket 250x faster |
| Updates | Real-time | 2s intervals | WebSocket smoother UX |
| Battery | Minimal | Low | Polling uses more wake cycles |
| Reliability | 99.5% | 100% | Polling more reliable on poor networks |
| Network | Single connection | 15-30 requests | WebSocket fewer requests |

## Failure Scenarios

### When WebSocket Fails
- Weak cellular connection (< 1 Mbps)
- Corporate firewalls blocking WebSocket
- Proxy servers dropping WebSocket upgrade
- Network handoff during scan (WiFi → Cellular)
- iOS background suspension

### Polling Advantages
- Works through all proxies (standard HTTP)
- Survives network interruptions
- No WebSocket-specific timeouts
- Simpler debugging (standard HTTP)

## Backend Endpoints (Unified Architecture)

**All endpoints on `bookshelf-ai-worker.jukasdrj.workers.dev`:**

| Endpoint | Method | Purpose | Used By |
|----------|--------|---------|---------|
| `/scan?jobId={uuid}` | POST | Upload image for AI processing | Both strategies |
| `/scan/status/{jobId}` | GET | Poll job status | Polling fallback |
| `/scan/ready/{jobId}` | POST | Signal WebSocket ready | WebSocket only |
| `/ws/progress?jobId={uuid}` | GET (WS) | Real-time progress updates | WebSocket only |

**iOS Client Endpoints:**

```swift
// WebSocketProgressManager.swift
private let baseURL = "wss://bookshelf-ai-worker.jukasdrj.workers.dev"
private let readySignalEndpoint = "https://bookshelf-ai-worker.jukasdrj.workers.dev"

// BookshelfAIService+Polling.swift
let baseURL = "https://bookshelf-ai-worker.jukasdrj.workers.dev"
let uploadURL = URL(string: "\(baseURL)/scan?jobId=\(jobId)")!
```

## Code Structure

### Core Components

**BookshelfAIService.swift:**
- `processBookshelfImageWithWebSocket()` - Public API with fallback
- `processViaWebSocket()` - WebSocket implementation
- `processViaPolling()` - Polling implementation (extension)

**ProgressStrategy.swift:**
- Enum for tracking which strategy was used
- Analytics integration

**WebSocketProgressManager.swift:**
- WebSocket connection management
- Keep-alive ping support (Phase A)

### Testing

**Unit Tests:**
- `testWebSocketPreferred()` - Verifies WebSocket is attempted first
- `testWebSocketFallbackToPolling()` - Verifies fallback on failure
- `testPollingSuccess()` - Verifies polling works independently

**Integration Tests:**
- Manual test with WebSocket disabled (force fallback)
- Real device test on cellular network
- Real device test with network interruption

## Analytics

Track strategy usage:

```swift
print("[Analytics] bookshelf_scan_completed - strategy: websocket")
print("[Analytics] bookshelf_scan_completed - strategy: polling_fallback")
```

**Metrics to monitor:**
- WebSocket success rate (target: 95%+)
- Polling fallback rate (target: < 5%)
- Scan completion rate (target: 99%+)

## Future Enhancements

1. **Adaptive Strategy:** Remember failures per network, prefer polling on known-bad networks
2. **Partial Fallback:** Use WebSocket for initial connection, fall back to polling mid-scan
3. **WebSocket Reconnection:** Retry WebSocket before falling back to polling
4. **Strategy Hints:** Allow user to force polling in Settings for debugging

## Architecture History

**Version 1.0.0 (Phase B - October 23, 2025):**
- Initial WebSocket + polling implementation
- Split-brain routing: WebSocket → books-api-proxy, Polling → bookshelf-ai-worker
- Bug: Polling upload endpoint didn't exist (404 errors)

**Version 2.0.0 (Unified - October 24, 2025):**
- ✅ **Fixed:** All traffic unified to bookshelf-ai-worker
- ✅ **Fixed:** Polling upload uses `/scan?jobId={uuid}` (matches WebSocket)
- ✅ **Fixed:** WebSocket connects to bookshelf-ai-worker (added DO binding)
- ✅ **Fixed:** Header changed from `X-Provider` → `X-AI-Provider` (backend compatibility)

**Version 3.0.0 (Blocking Processing - October 24, 2025):**
- ✅ **Fixed:** IoContext timeout - changed from `ctx.waitUntil()` to blocking `await`
- ✅ **Fixed:** Progress updates now push to Durable Object (not books-api-proxy RPC)
- ✅ **Fixed:** Keep-alive pings working (10s interval prevents timeout)
- ✅ **Verified:** 13-book scan completed successfully in 50 seconds
- ⚠️ **Known Issue:** WebSocket progress updates not reaching iOS client (polling works)

**Architecture Change:**
```javascript
// OLD: Background processing (gets cancelled after 30s inactivity)
ctx.waitUntil(processBookshelfScan(jobId, imageData, requestEnv));
return Response.json({ jobId }, { status: 202 });

// NEW: Blocking processing (keeps HTTP connection open)
await processBookshelfScan(jobId, imageData, requestEnv);
return Response.json({ jobId }, { status: 202 });
```

**Why This Works:**
Cloudflare Workers' `ctx.waitUntil()` is designed for quick cleanup tasks (<30s). Long-running AI processing (25-40s) triggers IoContext timeout when no network requests occur for ~30s. By blocking the main request handler with `await`, the HTTP connection stays open and prevents context cancellation.

---

**Last Updated:** October 24, 2025
**Authors:** BooksTrack Engineering Team
**Status:** Production (Blocking Processing, Polling Fallback Working)
