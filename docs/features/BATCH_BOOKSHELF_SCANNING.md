# Batch Bookshelf Scanning

**Status:** Beta (v3.1.0+)

## Overview

Users can capture up to 5 bookshelf photos in one scanning session. Photos upload in parallel, then process sequentially through Gemini 2.0 Flash with real-time WebSocket progress updates.

## Architecture

### iOS Flow
1. User enables "Batch Mode" toggle
2. Captures photos with "Submit now" or "Take more" workflow
3. Thumbnail strip shows captured photos (deletable)
4. Submit triggers batch upload → WebSocket connection
5. Real-time progress: "Photo 2/5 processing... 8 books found"
6. Results deduplicated by ISBN, low-confidence → Review Queue

### Backend Flow
1. `POST /api/scan-bookshelf/batch` receives array of base64 images
2. Parallel R2 upload (all photos simultaneously)
3. Sequential Gemini processing (avoid rate limits)
4. ProgressWebSocketDO tracks per-photo status
5. WebSocket sends updates after each photo completes
6. Final deduplication by ISBN before delivery

### WebSocket Messages

**Progress Update:**
```json
{
  "type": "batch-progress",
  "jobId": "abc-123",
  "currentPhoto": 1,
  "totalPhotos": 3,
  "photoStatus": "processing",
  "booksFound": 8,
  "totalBooksFound": 20,
  "photos": [
    { "index": 0, "status": "complete", "booksFound": 12 },
    { "index": 1, "status": "processing", "booksFound": 0 },
    { "index": 2, "status": "queued", "booksFound": 0 }
  ]
}
```

**Completion:**
```json
{
  "type": "batch-complete",
  "jobId": "abc-123",
  "totalBooks": 28,
  "photoResults": [...],
  "books": [...]
}
```

## Key Implementation Details

**Photo Limit:** 5 photos maximum per batch (enforced in UI and backend)

**Compression:** Each photo compressed to ~500KB (3072px @ 90% quality)

**Memory Management:**
- Clear photos from memory after upload
- WebSocket handler auto-disconnects on completion

**Cancellation:**
- User can cancel mid-batch via "Cancel Batch" button
- Backend checks `isCanceled()` before each photo
- Returns partial results from completed photos

**Error Handling:**
- Individual photo failures don't fail entire batch
- Partial success: return books from successful photos
- Complete failure: only if ALL photos fail

**Deduplication:**
- Backend deduplicates by ISBN before final delivery
- Fallback to title+author for books without ISBN
- Keeps book with highest confidence score

## Testing

**iOS:**
- `BatchScanModelTests.swift` - Data models
- `BatchCaptureUITests.swift` - UI logic
- `BatchUploadTests.swift` - Network layer

**Backend:**
- `batch-scan.test.js` - Endpoint validation
- Durable Object state management

**Manual Test Checklist:**
- [ ] 5-photo limit enforcement
- [ ] Thumbnail deletion
- [ ] Progress updates accuracy
- [ ] Cancellation with partial results
- [ ] Background/foreground resilience
- [ ] Deduplication correctness

## Performance

- **Upload:** ~2-3s for 5 photos (parallel)
- **Processing:** 25-40s per photo (Gemini)
- **Total batch time:** ~2-3 minutes for 5 photos
- **Memory:** ~2-3MB during upload, cleared after

## Known Limitations

1. Maximum 5 photos per batch
2. No photo editing/cropping in batch mode
3. Can't add photos after submission starts
4. WebSocket disconnection requires manual retry

## Future Enhancements

- [ ] Photo cropping/rotation before submit
- [ ] Add more photos during processing
- [ ] Save incomplete batches for later
- [ ] Parallel Gemini processing (with rate limiting)
