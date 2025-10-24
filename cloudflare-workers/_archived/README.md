# Archived Workers

**Status:** Archived on October 23, 2025

## Overview

These workers were consolidated into the unified `api-worker` monolith as part of the Cloudflare Workers Monolith Refactor.

**DO NOT DEPLOY these workers to production.**

They are preserved for historical reference only.

## Archived Workers

1. **books-api-proxy** - Book search orchestration and caching
2. **enrichment-worker** - Batch book enrichment with external APIs
3. **bookshelf-ai-worker** - AI-powered bookshelf scanning
4. **external-apis-worker** - External API integrations (Google Books, OpenLibrary)
5. **progress-websocket-durable-object** - WebSocket progress updates

## Migration Details

All functionality from these 5 distributed workers has been consolidated into a single monolith worker: `api-worker`

### Key Changes

- **Eliminated:** Service bindings and circular dependencies
- **Unified:** All status reporting via ProgressWebSocketDO
- **Simplified:** Direct function calls instead of RPC
- **Reduced:** Network latency from multiple worker hops

### Current Architecture

See `../DEPLOYMENT.md` for current architecture documentation.

All endpoints are now served from:
```
https://api-worker.jukasdrj.workers.dev
```

### Why Archived?

The distributed architecture had the following issues:
- Circular service binding dependencies
- Dual status systems (polling + WebSocket)
- Unnecessary network latency
- Complex deployment coordination

The monolith architecture resolves all these issues while maintaining the same functionality.

## Reference Documentation

- Migration Plan: `/docs/plans/2025-10-23-cloudflare-workers-monolith-refactor.md`
- Deployment Guide: `../DEPLOYMENT.md`
- Architecture Audit: `../MIGRATION_AUDIT.md`

---

**Last Updated:** October 23, 2025
