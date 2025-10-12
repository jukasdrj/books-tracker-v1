# API Migration Testing Checklist

**Version:** 3.0.2
**Date:** October 11, 2025
**Status:** Ready for Manual Testing

---

## Quick Test Commands

### 1. Backend Endpoint Verification

**Test EnrichmentService endpoint:**
```bash
# Test /search/advanced with title + author (EnrichmentService pattern)
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/advanced?title=The%20Martian&author=Andy%20Weir&maxResults=5" | jq '{
  totalItems: .totalItems,
  provider: .provider,
  firstResult: .items[0].volumeInfo.title
}'

# Expected:
# {
#   "totalItems": 1-5,
#   "provider": "advanced-search",
#   "firstResult": "The Martian"
# }
```

**Test SearchModel .all scope endpoint:**
```bash
# Test /search/title with book title (SearchModel .all pattern)
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian&maxResults=20" | jq '{
  totalItems: .totalItems,
  provider: .provider,
  searchContext: .searchContext
}'

# Expected:
# {
#   "totalItems": 10-20,
#   "provider": "orchestrated:google-books+openlibrary",
#   "searchContext": "title"
# }
```

**Test SearchModel .isbn scope endpoint:**
```bash
# Test /search/title with ISBN (SearchModel .isbn pattern)
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=9780345391803&maxResults=20" | jq '{
  totalItems: .totalItems,
  firstTitle: .items[0].volumeInfo.title,
  firstISBN: .items[0].volumeInfo.industryIdentifiers[0].identifier
}'

# Expected:
# {
#   "totalItems": 1,
#   "firstTitle": "The Martian",
#   "firstISBN": "9780345391803"
# }
```

---

## iOS App Manual Testing

### Test 1: CSV Import Enrichment

**Objective:** Verify EnrichmentService uses /search/advanced endpoint

**Steps:**
1. Open BooksTrack app in Xcode
2. Navigate to Settings → Import CSV Library
3. Import a small CSV file (5-10 books) with title and author columns
4. Monitor backend logs:
   ```bash
   wrangler tail books-api-proxy --search "advanced" --format pretty
   ```
5. Verify enrichment completes successfully
6. Check book details in Library tab for accurate metadata

**Expected Results:**
- ✅ Backend logs show `/search/advanced?title=...&author=...` requests
- ✅ 95%+ enrichment success rate
- ✅ Accurate cover images, ISBNs, publication dates
- ✅ No "Unknown Author" books that have known authors in CSV

**Pass Criteria:**
- All books with title + author in CSV get enriched with correct metadata
- Backend filtering reduces false positives (wrong editions, foreign language editions)

---

### Test 2: General Search (.all Scope)

**Objective:** Verify .all scope uses /search/title endpoint

**Steps:**
1. Open SearchView in app
2. Ensure search scope is "All" (default)
3. Test various query types:
   - Book title: "The Martian"
   - Partial title: "Harry Potter Philosopher"
   - ISBN: "9780345391803"
   - Author name: "Andy Weir" (should still work!)
4. Verify results are relevant and fast

**Expected Results:**
- ✅ All query types return results
- ✅ ISBNs return exact matches
- ✅ Response time <2s for cache miss, <100ms for cache hit
- ✅ No forced scope selection required

**Pass Criteria:**
- Users can search without thinking about scopes
- ISBNs work transparently in .all scope
- Search feels intelligent and predictive

---

### Test 3: ISBN Search (.isbn Scope)

**Objective:** Verify .isbn scope routes to /search/title

**Steps:**
1. Open SearchView
2. Switch scope to "ISBN"
3. Test with various ISBNs:
   - ISBN-13: "9780345391803" (The Martian)
   - ISBN-10: "0345391802" (The Martian)
   - Invalid ISBN: "1234567890123"
4. Test barcode scanner integration:
   - Tap barcode icon
   - Scan a book barcode
   - Verify search results appear

**Expected Results:**
- ✅ Valid ISBNs return exact matches
- ✅ Invalid ISBNs show "No results" gracefully
- ✅ Barcode scanner populates search with ISBN
- ✅ searchByISBN() method works correctly

**Pass Criteria:**
- ISBN search is fast and accurate
- Barcode scanning workflow is seamless
- Results show correct edition metadata

---

### Test 4: Author Search (.author Scope)

**Objective:** Verify .author scope still uses /search/author (no change)

**Steps:**
1. Switch scope to "Author"
2. Search for popular authors:
   - "Stephen King"
   - "J.K. Rowling"
   - "Andy Weir"
3. Verify large bibliographies load correctly
4. Test pagination (Load More button)

**Expected Results:**
- ✅ Author searches return author's bibliography
- ✅ Large result sets paginate correctly
- ✅ Results cached for 24h (fast subsequent searches)
- ✅ No behavior change from previous version

**Pass Criteria:**
- Author search remains unchanged and functional
- 24h cache improves popular author search performance

---

### Test 5: Title Search (.title Scope)

**Objective:** Verify .title scope uses /search/title (no change)

**Steps:**
1. Switch scope to "Title"
2. Search for book titles:
   - Exact: "The Martian"
   - Partial: "Hitchhiker's Guide"
   - Special characters: "The Hitchhiker's Guide to the Galaxy"
3. Verify results are title-focused (not author results)

**Expected Results:**
- ✅ Title search returns books matching query
- ✅ Partial titles work (substring matching)
- ✅ Special characters handled correctly
- ✅ No behavior change from previous version

**Pass Criteria:**
- Title search remains unchanged and functional
- 6h cache improves common title search performance

---

## Performance Testing

### Cache Hit Rate Test

**Objective:** Verify specialized endpoints improve cache performance

**Steps:**
```bash
# Test 1: First search (cache miss)
time curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian" > /dev/null
# Expected: 1-2 seconds

# Test 2: Second search (cache hit)
time curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian" > /dev/null
# Expected: <100ms

# Test 3: Verify cache headers
curl -si "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=The%20Martian" | grep "X-Cache"
# Expected: X-Cache: HIT
```

**Expected Results:**
- ✅ Cache miss: <2s response time
- ✅ Cache hit: <100ms response time
- ✅ Title endpoint: 6h cache TTL
- ✅ Advanced endpoint: 6h cache TTL

---

### Parallel Search Test

**Objective:** Verify .all scope searches don't slow down with title endpoint

**Steps:**
```bash
# Test response times for various query types
for query in "The Martian" "9780345391803" "Andy Weir" "science fiction"; do
  echo "Testing: $query"
  time curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/title?q=$query" > /dev/null
done
```

**Expected Results:**
- ✅ All queries complete in <2s (cache miss)
- ✅ ISBN queries return 1-3 exact results
- ✅ Author names return 10-20 results (title search finds books by author)
- ✅ Genre queries return relevant books

---

## Regression Testing

### Test 6: Advanced Search View

**Objective:** Verify AdvancedSearchView still works with /search/advanced

**Steps:**
1. Open SearchView
2. Tap "Advanced Search" button
3. Fill in multiple fields:
   - Author: "Andy Weir"
   - Title: "Martian"
   - ISBN: (leave empty)
4. Tap "Search"
5. Verify filtered results

**Expected Results:**
- ✅ Results match BOTH author AND title criteria
- ✅ Backend filtering (not client-side)
- ✅ "Andy Weir" + "Martian" = "The Martian" only
- ✅ No unrelated "Martian" books from other authors

**Pass Criteria:**
- AdvancedSearchView behavior unchanged
- Backend filtering ensures clean results

---

### Test 7: Barcode Scanner Integration

**Objective:** Verify barcode scanner uses correct endpoint

**Steps:**
1. Open SearchView
2. Tap barcode scanner icon
3. Scan a book barcode (or use simulator test ISBN)
4. Verify search results populate
5. Check SearchModel.searchByISBN() method

**Expected Results:**
- ✅ Scanner captures ISBN correctly
- ✅ searchByISBN() calls search(query: isbn, scope: .isbn)
- ✅ Results show correct book edition
- ✅ No double-search or UI flicker

**Pass Criteria:**
- Barcode scanning workflow is seamless
- SearchModel.searchByISBN() works with new endpoint routing

---

## Error Handling Tests

### Test 8: No Results Scenarios

**Objective:** Verify graceful handling of empty results

**Steps:**
1. Search for non-existent book: "asdfjkl123impossible"
2. Verify ContentUnavailableView appears
3. Search for invalid ISBN: "1234567890"
4. Verify "No results" message

**Expected Results:**
- ✅ No crashes or errors
- ✅ ContentUnavailableView with search icon
- ✅ Retry button visible
- ✅ Clear error messaging

---

### Test 9: Network Errors

**Objective:** Verify error handling for network failures

**Steps:**
1. Enable Airplane Mode on test device
2. Attempt search
3. Verify error message appears
4. Disable Airplane Mode
5. Tap "Retry" button

**Expected Results:**
- ✅ "Network connection issue" error message
- ✅ Retry button functional
- ✅ Search succeeds after re-enabling network
- ✅ No app crash or hang

---

## Code Review Checklist

- ✅ EnrichmentService.searchAPI() signature changed to (title:author:)
- ✅ EnrichmentService uses URLComponents for query parameter encoding
- ✅ SearchModel.search() routes .all scope to /search/title
- ✅ SearchModel.search() routes .isbn scope to /search/title
- ✅ Swift 6 concurrency compliance maintained (@MainActor, actor isolation)
- ✅ No force unwrapping introduced (guard statements used)
- ✅ Error handling preserved (try/catch blocks intact)
- ✅ Comments explain iOS 26 HIG rationale
- ✅ No breaking changes to public API surface
- ✅ Backward compatible with existing data model

---

## Deployment Checklist

### Pre-Deployment
- [ ] All manual tests pass
- [ ] No compiler warnings or errors
- [ ] Swift 6 strict concurrency enabled and clean
- [ ] Backend endpoints verified functional
- [ ] Cache behavior tested and validated

### Post-Deployment Monitoring
- [ ] Monitor wrangler logs for /search/advanced usage
- [ ] Track EnrichmentStatistics.successRate (target: 95%+)
- [ ] Monitor SearchResponse.responseTime (target: <2s cache miss, <100ms cache hit)
- [ ] Check for user-reported search issues
- [ ] Verify cache hit rate improvement (target: 50%+)

### Rollback Trigger Conditions
- EnrichmentService success rate drops below 85%
- Search response times exceed 5s consistently
- Multiple user reports of incorrect search results
- Backend endpoint errors spike above 5%

### Rollback Procedure
See API_MIGRATION_GUIDE.md Section 6 for rollback code.

---

## Success Criteria Summary

| Metric | Target | How to Verify |
|--------|--------|---------------|
| CSV Enrichment Accuracy | 95%+ | EnrichmentStatistics UI + manual spot checks |
| Search Response Time (cache miss) | <2s | Monitor SearchResponse.responseTime |
| Search Response Time (cache hit) | <100ms | Repeat searches, check X-Cache header |
| Cache Hit Rate | 50%+ | Monitor X-Cache headers in network logs |
| User-Reported Issues | No increase | Support tickets / feedback channels |
| Compiler Warnings | 0 | Xcode build log |
| Test Coverage | 90%+ | Swift Testing framework report |

---

## Contact & Support

**Questions?** Review these docs:
- API_MIGRATION_GUIDE.md (detailed technical rationale)
- cloudflare-workers/books-api-proxy/API_EXAMPLES.md (endpoint specs)
- CLAUDE.md (development standards)

**Issues?** Check:
- Backend logs: `wrangler tail books-api-proxy --format pretty`
- iOS logs: Xcode Console output
- Network traffic: Charles Proxy / Network Inspector

**Rollback?** Follow Section 6 in API_MIGRATION_GUIDE.md

---

**Document Version:** 1.0
**Last Updated:** October 11, 2025
**Testing Status:** Ready for Execution
