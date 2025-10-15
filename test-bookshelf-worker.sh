#!/bin/bash

# Test bookshelf-ai-worker with enrichment
# Usage: ./test-bookshelf-worker.sh <image_path>

IMAGE_PATH="${1:-docs/testImages/IMG_0014.jpeg}"
WORKER_URL="https://bookshelf-ai-worker.jukasdrj.workers.dev/scan"

echo "🧪 Testing Bookshelf AI Worker with Enrichment"
echo "================================================"
echo "Image: $IMAGE_PATH"
echo "Worker: $WORKER_URL"
echo ""

if [ ! -f "$IMAGE_PATH" ]; then
    echo "❌ Error: Image not found at $IMAGE_PATH"
    exit 1
fi

echo "📤 Uploading image..."
echo ""

# Upload image and capture response
RESPONSE=$(curl -X POST "$WORKER_URL" \
  -H "Content-Type: image/jpeg" \
  --data-binary "@$IMAGE_PATH" \
  -w "\n%{http_code}" \
  --max-time 120 \
  2>/dev/null)

# Extract status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
# Extract JSON response (all but last line)
JSON_RESPONSE=$(echo "$RESPONSE" | head -n -1)

echo "📥 Response Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Success! Parsing response..."
    echo ""

    # Parse and display key metrics
    echo "$JSON_RESPONSE" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)

    print('📊 SCAN RESULTS')
    print('=' * 60)

    metadata = data.get('metadata', {})
    books = data.get('books', [])

    print(f\"Processing Time: {metadata.get('processingTime', 0)}ms\")
    print(f\"Enrichment Time: {metadata.get('enrichmentTime', 0)}ms\")
    print(f\"Total Books: {metadata.get('detectedCount', 0)}\")
    print(f\"Readable: {metadata.get('readableCount', 0)}\")
    print(f\"Enriched: {metadata.get('enrichedCount', 0)}\")
    print(f\"Model: {metadata.get('model', 'unknown')}\")
    print()

    print('📚 DETECTED BOOKS')
    print('=' * 60)

    for i, book in enumerate(books, 1):
        title = book.get('title') or 'Unreadable'
        author = book.get('author') or 'Unknown'
        confidence = book.get('confidence', 0)
        enrichment = book.get('enrichment', {})
        status = enrichment.get('status', 'no_enrichment')

        print(f\"{i}. {title} by {author}\")
        print(f\"   Confidence: {confidence:.2f}\")
        print(f\"   Enrichment: {status}\", end='')

        if status == 'success':
            isbn = enrichment.get('isbn', 'N/A')
            provider = enrichment.get('provider', 'unknown')
            cached = enrichment.get('cachedResult', False)
            print(f\" (ISBN: {isbn}, Provider: {provider}, Cached: {cached})\")
        elif status == 'failed' or status == 'error':
            error = enrichment.get('error', 'Unknown error')
            print(f\" (Error: {error})\")
        elif status == 'skipped':
            reason = enrichment.get('reason', 'unknown')
            print(f\" (Reason: {reason})\")
        else:
            print()
        print()

    print('=' * 60)
    print(f\"✅ Test Complete: {len(books)} books detected, {metadata.get('enrichedCount', 0)} enriched\")

except Exception as e:
    print(f'❌ Error parsing response: {e}')
    print()
    print('Raw response:')
    print(sys.stdin.read())
"
else
    echo "❌ Error: HTTP $HTTP_CODE"
    echo ""
    echo "Response:"
    echo "$JSON_RESPONSE"
fi
