#!/bin/bash

# Verification script for bookshelf-ai-worker enrichment fix
# Tests that the worker can now properly enrich books from books-api-proxy

echo "=========================================="
echo "Bookshelf AI Worker - Enrichment Fix Test"
echo "=========================================="
echo ""

echo "Test 1: Verify books-api-proxy returns data in 'items' field"
echo "-----------------------------------------------------------"
curl -s "https://books-api-proxy.jukasdrj.workers.dev/search/advanced?title=Attached&author=Amir+Levine" \
  | jq '{
      hasItems: (.items != null),
      itemCount: (.items | length),
      firstBookTitle: .items[0].volumeInfo.title,
      provider: .provider
    }'
echo ""

echo "Test 2: Create mock bookshelf scan with 'Attached' detection"
echo "-----------------------------------------------------------"
echo "Expected: enrichment.status should be 'success' (not 'not_found')"
echo ""
echo "Note: This would require uploading an actual image or using RPC binding."
echo "For now, verify manually at: https://bookshelf-ai-worker.jukasdrj.workers.dev"
echo ""

echo "Test 3: Check deployment status"
echo "-----------------------------------------------------------"
curl -s "https://bookshelf-ai-worker.jukasdrj.workers.dev/health" | jq '.'
echo ""

echo "=========================================="
echo "Manual Verification Steps:"
echo "=========================================="
echo "1. Upload IMG_0014.jpeg to https://bookshelf-ai-worker.jukasdrj.workers.dev"
echo "2. Check that enrichment.status shows 'success' for high-confidence books"
echo "3. Verify that ISBN, coverUrl, and other metadata are populated"
echo "4. Expected success rate: 50%+ (was 0% before fix)"
echo ""
echo "Fix Details:"
echo "- Changed: apiData.results?.[0] → apiData.items?.[0]"
echo "- Added: Proper volumeInfo field mapping for Google Books structure"
echo "- File: cloudflare-workers/bookshelf-ai-worker/src/index.js:396-417"
echo ""
