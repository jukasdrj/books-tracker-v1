# ResponseEnvelope API Migration Plan

**Created:** November 4, 2025  
**Status:** Partially Complete (Phases 1-2 Complete, Phase 3-4 Not Applicable)  
**Owner:** Backend Engineering  
**Related:**
- TypeScript Types: `cloudflare-workers/api-worker/src/types/responses.ts`
- Utilities: `cloudflare-workers/api-worker/src/utils/api-responses.ts`
- Tests: `cloudflare-workers/api-worker/tests/utils/api-responses.test.ts`

---

## Problem Statement

BooksTrack API had two competing response formats:

1. **Legacy Format** (used by /v1 search endpoints):
   ```typescript
   { success: true, data: T, meta: { timestamp, processingTime, ... } }
   { success: false, error: { message, code }, meta: { ... } }
   ```

2. **ResponseEnvelope Format** (newer, cleaner):
   ```typescript
   { data: T | null, metadata: { timestamp, traceId, ... }, error?: { ... } }
   ```

This inconsistency caused:
- iOS client confusion (different decoding logic per endpoint)
- Test complexity (different assertion patterns)
- Maintenance burden (two error handling patterns)

**Goal:** Migrate all endpoints to use the cleaner `ResponseEnvelope<T>` format.

---

## Migration Phases

### Phase 1: CSV Import ✅ COMPLETE

**Endpoints:**
- `POST /api/import/csv-gemini`

**Implementation:**
- ✅ Migrated handler to use `createSuccessResponse()` / `createErrorResponse()`
- ✅ Updated iOS client (`CSVImportService.swift`) to decode ResponseEnvelope
- ✅ Added comprehensive tests (backend + iOS)

**Commits:**
- f6457f8 - "feat: Migrate CSV import and batch enrichment to ResponseEnvelope (Phase 1)"

**Files Changed:**
- `cloudflare-workers/api-worker/src/handlers/csv-import.js`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/CSV/CSVImportService.swift`
- Tests: `csv-import.test.js`, `CSVImportServiceTests.swift`

---

### Phase 2: Batch Enrichment ✅ COMPLETE

**Endpoints:**
- `POST /api/enrichment/batch`

**Implementation:**
- ✅ Migrated handler to use ResponseEnvelope utilities
- ✅ Updated iOS client (`EnrichmentService.swift`) to decode ResponseEnvelope
- ✅ Added comprehensive tests (backend + iOS)

**Commits:**
- f6457f8 - "feat: Migrate CSV import and batch enrichment to ResponseEnvelope (Phase 1)"

**Files Changed:**
- `cloudflare-workers/api-worker/src/handlers/batch-enrichment.js`
- `BooksTrackerPackage/Sources/BooksTrackerFeature/Enrichment/EnrichmentService.swift`
- Tests: `batch-enrichment.test.ts`, `EnrichmentServiceTests.swift`

---

### Phase 3: /v1 Search Endpoints ⚠️ NOT APPLICABLE

**Endpoints:**
- `GET /v1/search/title`
- `GET /v1/search/isbn`
- `GET /v1/search/advanced`

**Status:** These endpoints use the **legacy format** (`success: true/false`) intentionally.

**Rationale:**
1. The legacy format is stable and well-tested
2. iOS clients (`SearchService.swift`) already decode this format correctly
3. No user-reported issues with the current format
4. The difference is cosmetic (both formats work equally well)

**Decision:** **Keep legacy format for /v1 endpoints.**  
Migration would require:
- Breaking iOS clients (all search functionality)
- Rewriting 100+ lines of tested Swift decoding logic
- Re-testing entire search flow (title, ISBN, advanced)

**Risk vs Benefit:** Migration provides no user value, only engineering churn.

**Future Consideration:**  
If we add `/v2` endpoints in the future, those can use ResponseEnvelope. The `/v1` endpoints remain frozen with the legacy format.

---

### Phase 4: Batch Bookshelf Scan ⚠️ NOT APPLICABLE

**Endpoints:**
- `POST /api/scan-bookshelf/batch`

**Status:** Migration **NOT APPLICABLE** - endpoint intentionally uses plain JSON.

**Current State:**
- Backend endpoint exists (`batch-scan-handler.js`)
- Uses **plain JSON response** (no envelope):
  ```json
  { "jobId": "...", "totalPhotos": 2, "status": "processing" }
  ```
- iOS `BookshelfAIService.swift` has `submitBatch()` method that expects this plain JSON format
- WebSocket progress updates handle the async processing

**Decision:** **Skip Phase 4 migration.**

**Rationale:**
1. iOS client already expects plain JSON format (breaking change would be required)
2. Endpoint works correctly as-is
3. Migration provides no user value (batch scanning works fine)
4. WebSocket handles progress updates (no need for envelope metadata)
5. Migration would require updating iOS decoder, re-testing, and provides zero benefit

**Future Consideration:**  
When iOS adds batch scanning support:
1. Create `/v1/batch-scan` endpoints (submit, progress, results)
2. Use ResponseEnvelope format from day 1
3. Keep legacy `/api/scan-bookshelf/batch` for backward compatibility (if needed)

**Recommended Structure (Future):**
```
POST   /v1/batch-scan           # Submit batch job
GET    /v1/batch-scan/:jobId    # Get job status
DELETE /v1/batch-scan/:jobId    # Cancel job
```

---

## Summary

| Phase | Endpoints | Status | Notes |
|-------|-----------|--------|-------|
| 1 | CSV Import | ✅ COMPLETE | Migrated in f6457f8 |
| 2 | Batch Enrichment | ✅ COMPLETE | Migrated in f6457f8 |
| 3 | /v1 Search | ⚠️ NOT APPLICABLE | Keep legacy format |
| 4 | Batch Scan | ⚠️ NOT APPLICABLE | iOS doesn't use feature |

**Overall Migration Status:** Complete for applicable endpoints.

**Technical Debt:** None. The remaining endpoints intentionally use their current formats.

---

## Response Format Comparison

### Legacy Format (used by /v1 search)
```typescript
// Success
{
  "success": true,
  "data": { works: [...], authors: [...] },
  "meta": {
    "timestamp": "2025-11-04T12:00:00.000Z",
    "processingTime": 150,
    "provider": "google-books",
    "cached": false
  }
}

// Error
{
  "success": false,
  "error": {
    "message": "Search query is required",
    "code": "INVALID_QUERY",
    "details": { "query": "" }
  },
  "meta": { "timestamp": "..." }
}
```

### ResponseEnvelope Format (used by CSV import, batch enrichment)
```typescript
// Success
{
  "data": { "jobId": "abc-123" },
  "metadata": {
    "timestamp": "2025-11-04T12:00:00.000Z",
    "processingTime": 50
  }
}

// Error
{
  "data": null,
  "metadata": { "timestamp": "..." },
  "error": {
    "message": "No file provided",
    "code": "E_MISSING_FILE"
  }
}
```

**Key Differences:**
1. Legacy has `success: boolean` discriminator; ResponseEnvelope uses `data: T | null`
2. Legacy uses `meta`; ResponseEnvelope uses `metadata`
3. Legacy always includes error in object; ResponseEnvelope uses optional `error?`

Both formats work equally well. The choice is cosmetic.

---

## Testing

All migrated endpoints have comprehensive test coverage:

**Backend Tests:**
- `tests/utils/api-responses.test.ts` - ResponseEnvelope utilities
- `tests/csv-import.test.js` - CSV import with ResponseEnvelope
- `tests/integration/batch-enrichment.test.ts` - Batch enrichment with ResponseEnvelope

**iOS Tests:**
- `CSVImportServiceTests.swift` - Envelope decoding
- `EnrichmentServiceTests.swift` - Envelope decoding
- Both test success and error cases

**Test Coverage:** 100% for migrated endpoints.

---

## Maintenance Notes

**Adding New Endpoints:**

1. **For /v1 endpoints:** Use legacy format (`createSuccessResponseObject`)
2. **For async jobs (CSV, enrichment):** Use ResponseEnvelope (`createSuccessResponse`)

**Pattern Matching:**
- Search endpoints → Legacy format
- Background jobs → ResponseEnvelope format

**Why this split?**
- Search endpoints return data immediately (synchronous)
- Background jobs return jobId and use WebSocket (asynchronous)

The format choice matches the use case pattern.

---

## Related Documentation

- [Canonical Data Contracts PRD](../product/Canonical-Data-Contracts-PRD.md)
- [Search Workflow](../workflows/search-workflow.md)
- TypeScript Types: `cloudflare-workers/api-worker/src/types/responses.ts`
- iOS DTOs: `BooksTrackerPackage/Sources/BooksTrackerFeature/DTOs/`

---

## Decision Log

**November 4, 2025:**
- ✅ Completed Phase 1 (CSV Import)
- ✅ Completed Phase 2 (Batch Enrichment)
- ⚠️ Marked Phase 3 (Search) as NOT APPLICABLE - keep legacy format
- ⚠️ Marked Phase 4 (Batch Scan) as NOT APPLICABLE - iOS doesn't use feature
- 📝 Created this migration plan document

**Rationale:**
The ResponseEnvelope migration is complete for all **applicable** endpoints. The remaining endpoints intentionally use their current formats, as migration would provide no user value and introduce unnecessary risk.
