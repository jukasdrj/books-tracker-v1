# Cloudflare WebSocket Hibernation API Research

**Date:** October 23, 2025
**Status:** Phase C Planning

## Overview

WebSocket Hibernation API extends Web Standard WebSocket API to reduce billing costs during idle periods. Durable Objects with hibernating WebSockets do NOT incur GB-seconds charges while hibernated.

## Key Concepts

### Standard WebSocket (Current)
```javascript
export class ProgressWebSocketDO extends DurableObject {
  async fetch(request) {
    const [client, server] = Object.values(new WebSocketPair());
    this.webSocket = server;
    this.webSocket.accept();

    // Event listeners
    this.webSocket.addEventListener('message', (event) => { ... });
    this.webSocket.addEventListener('close', (event) => { ... });
    this.webSocket.addEventListener('error', (event) => { ... });

    return new Response(null, { status: 101, webSocket: client });
  }
}
```

**Billing:** GB-seconds accumulate for entire connection duration (0s - scan complete).

### Hibernatable WebSocket (Phase C)
```javascript
export class ProgressWebSocketDO extends DurableObject {
  async fetch(request) {
    const [client, server] = Object.values(new WebSocketPair());

    // Accept with hibernation enabled
    this.state.acceptWebSocket(server);

    return new Response(null, { status: 101, webSocket: client });
  }

  // Hibernation API handlers (called when events occur)
  async webSocketMessage(ws, message) {
    // Handle messages from client
  }

  async webSocketClose(ws, code, reason, wasClean) {
    // Handle disconnection
  }

  async webSocketError(ws, error) {
    // Handle errors
  }
}
```

**Billing:** GB-seconds accumulate ONLY when handlers execute. During idle periods (AI processing), Durable Object hibernates and billing stops.

## Cost Savings

### Current (Standard WebSocket)
- Connection duration: 40s (typical scan)
- Active GB-seconds: 40s * [memory usage]
- Cost per scan: ~$0.0001 (varies by memory)

### With Hibernation API
- Connection duration: 40s
- Active GB-seconds: ~0.5s (only when sending progress updates)
- Cost per scan: ~$0.000001 (99% reduction!)

**Annual savings (10,000 scans):** ~$1.00 → $0.01

## API Methods

### this.state.acceptWebSocket(ws)
Accepts WebSocket with hibernation enabled. Unlike `ws.accept()`, this allows the Durable Object to be hibernated without disconnecting clients.

### async webSocketMessage(ws, message)
Called when client sends message. Durable Object wakes from hibernation to handle the event.

### async webSocketClose(ws, code, reason, wasClean)
Called when connection closes. Durable Object wakes to handle cleanup.

### async webSocketError(ws, error)
Called on WebSocket error. Durable Object wakes to handle error.

### this.state.getWebSockets()
Returns array of all active WebSocket connections for this Durable Object.

## State Persistence

**Critical:** When a Durable Object hibernates, in-memory state (instance variables) is lost.

**Options for persistence:**
1. **Small data (<2KB):** Use `WebSocket.serializeAttachment(value)` and `WebSocket.deserializeAttachment()`
2. **Large data:** Use Storage API (`this.ctx.storage.put()`) and store key in attachment

**Example:**
```javascript
// Store jobId to survive hibernation
async fetch(request) {
  const [client, server] = Object.values(new WebSocketPair());
  server.serializeAttachment({ jobId: 'abc-123' });
  this.state.acceptWebSocket(server);
  return new Response(null, { status: 101, webSocket: client });
}

async webSocketMessage(ws, message) {
  const { jobId } = ws.deserializeAttachment();
  console.log(`Message for job ${jobId}`);
}
```

## Compatibility Notes

- Hibernation API is opt-in (backward compatible)
- Standard `webSocket.addEventListener()` NOT used with hibernation
- Must migrate all event handlers to hibernation API methods
- `this.webSocket` reference no longer needed (use `this.ctx.getWebSockets()`)
- Wrangler 3.13.2+ required for local development hibernation support

## Keep-Alive Behavior

**CRITICAL CHANGE:** Cloudflare's Hibernation API handles connection stability automatically via TCP keep-alive.

**Phase A Keep-Alive Pings (20s interval):** Must be REMOVED when migrating to hibernation. Application-level pings wake the Durable Object every 20s, preventing hibernation and negating cost savings.

**New Approach:**
- Trust Cloudflare's automatic TCP keep-alive
- No application-level pings needed
- Durable Object hibernates during entire AI processing period (25-40s)
- Wakes only for progress updates

## Migration Strategy

1. ✅ Remove application-level keep-alive pings (Phase A)
2. ✅ Add hibernation API handlers alongside existing event listeners
3. ✅ Switch `webSocket.accept()` to `this.state.acceptWebSocket()`
4. ✅ Add state serialization for jobId persistence
5. ✅ Test with hibernation handlers
6. ✅ Remove old event listeners once hibernation confirmed working
7. ✅ Deploy to production with feature flag for gradual rollout

## Limitations

- Only server-side WebSocket connections can hibernate
- Outgoing WebSocket clients cannot use hibernation
- Serialized attachment size limit: 2,048 bytes
- Older Wrangler versions (<3.13.2) don't support local hibernation testing

---

**Sources:**
- https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- https://blog.cloudflare.com/durable-objects-easy-fast-correct-choose-three/
- Gemini 2.5 Pro technical consultation (October 23, 2025)
