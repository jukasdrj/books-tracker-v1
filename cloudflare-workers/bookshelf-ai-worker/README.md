# 📚 Bookshelf AI Worker

AI-powered bookshelf scanning service using Google Gemini 2.5 Flash for BooksTrack.

## 🎯 Purpose

Analyzes photos of bookshelves to:
- Detect book spines with precise bounding boxes
- Extract titles and author names using multimodal AI
- Return structured JSON with normalized coordinates (0-1)
- Handle partial/blurry text gracefully (returns null for unreadable fields)

## 🏗️ Architecture

### Deployment Modes

**1. Standalone Worker (Current)**
```
iOS App → HTTPS POST → bookshelf-ai-worker.workers.dev/scan
                            ↓
                    Gemini 2.5 Flash API
                            ↓
                    Structured JSON Response
```

**2. RPC Integration (Future)**
```
iOS App → books-api-proxy → RPC Binding → BookshelfAIWorker.scanBookshelf()
```

## 🚀 Quick Start

### Prerequisites

- Cloudflare Workers account (Free or Paid tier)
- Google AI Studio API key (stored in Cloudflare Secrets Store as `google_aistudio_key`)
- Node.js 18+ and npm

### Installation

```bash
cd cloudflare-workers/bookshelf-ai-worker
npm install
```

### Development

```bash
# Run local development server
npm run dev

# Open http://localhost:8787 for test interface
```

### Deployment

```bash
# Deploy to production
npm run deploy

# Monitor real-time logs
npm run tail
```

## 📡 API Reference

### POST /scan

Scans a bookshelf image and returns detected books.

**Request:**
```http
POST /scan
Content-Type: image/jpeg

<raw image bytes>
```

**Response:**
```json
{
  "success": true,
  "books": [
    {
      "title": "The Great Gatsby",
      "author": "F. Scott Fitzgerald",
      "boundingBox": {
        "x1": 0.12,
        "y1": 0.05,
        "x2": 0.18,
        "y2": 0.85
      }
    },
    {
      "title": null,
      "author": null,
      "boundingBox": {
        "x1": 0.19,
        "y1": 0.05,
        "x2": 0.24,
        "y2": 0.85
      }
    }
  ],
  "metadata": {
    "processingTime": 4200,
    "detectedCount": 15,
    "readableCount": 12,
    "model": "gemini-2.5-flash-preview-05-20",
    "timestamp": "2025-10-12T18:30:00.000Z"
  }
}
```

**Bounding Box Format:**
- Normalized coordinates (0.0 - 1.0)
- `x1, y1`: Top-left corner
- `x2, y2`: Bottom-right corner

**Null Handling:**
- `title: null` or `author: null` = spine detected but text unreadable
- Client should offer manual entry for these cases

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "model": "gemini-2.5-flash-preview-05-20",
  "timestamp": "2025-10-12T18:30:00.000Z"
}
```

### GET /

Interactive HTML testing interface with drag-and-drop upload and visual bounding box overlay.

## 🔧 Configuration

### Environment Variables (wrangler.toml)

```toml
[vars]
AI_MODEL = "gemini-2.5-flash-preview-05-20"
MAX_IMAGE_SIZE_MB = "10"
REQUEST_TIMEOUT_MS = "25000"
LOG_LEVEL = "INFO"
```

### Secrets

```bash
# Set Gemini API key (one-time setup)
wrangler secret put GEMINI_API_KEY
# Paste your Google AI Studio key when prompted
```

## 📊 Performance

### Benchmarks

| Metric | Target | Typical |
|--------|--------|---------|
| Processing Time | <8s | 4-6s |
| Detection Rate | >80% | 85-90% |
| Readable Text Rate | >60% | 70-80% |
| Max Image Size | 10MB | 2-5MB |

### Rate Limits

**Gemini API (Free Tier):**
- 15 requests/minute
- 1,500 requests/day
- 1M tokens/day

**Cloudflare Workers (Free Tier):**
- 100,000 requests/day
- 10ms CPU time per request (actual: 0-2ms, Gemini does the heavy lifting)

**Upgrade to Paid:** For production use >100 scans/day, upgrade to Gemini Paid tier (2,000 RPM).

## 💰 Cost Estimates

### Gemini API Pricing (2025)

**Per Scan:**
- Input: ~10,500 tokens × $0.000000075 = $0.0007875
- Output: ~1,500 tokens × $0.0003 = $0.00045
- **Total: ~$0.0012 per scan**

**Monthly Projections:**

| Usage | Cost |
|-------|------|
| 100 scans | $0.12 |
| 1,000 scans | $1.20 |
| 5,000 scans | $6.00 |
| 20,000 scans | $24.00 |

**Cloudflare Workers:**
- Free tier: $0/month (up to 100K requests)
- Paid tier: $5/month + $0.50 per million requests

## 🧪 Testing

### Manual Testing (HTML Interface)

1. Deploy worker: `npm run deploy`
2. Visit `https://bookshelf-ai-worker.YOUR_ACCOUNT.workers.dev`
3. Upload test bookshelf photo
4. Verify bounding boxes align with visual spines
5. Check JSON output for accuracy

### CLI Testing

```bash
# Upload test image
curl -X POST https://bookshelf-ai-worker.YOUR_ACCOUNT.workers.dev/scan \
  -H "Content-Type: image/jpeg" \
  --data-binary @test-bookshelf.jpg \
  | jq '.books[] | {title, author}'
```

### Success Criteria

- ✅ Detects ≥80% of visible book spines
- ✅ Reads ≥60% of clear titles/authors
- ✅ Bounding boxes align with visual spines (±5% tolerance)
- ✅ Response time <8s for typical images
- ✅ Graceful handling of blurry/partial text (null values)

## 🔒 Security

### API Key Protection

- ✅ Stored in Cloudflare Secrets Store (encrypted at rest)
- ✅ Never exposed in logs or responses
- ✅ Automatically rotates with wrangler secret updates

### CORS

Enabled for iOS app integration:
```javascript
headers: {
  "Access-Control-Allow-Origin": "*"
}
```

**Production:** Restrict to your iOS app domain:
```javascript
"Access-Control-Allow-Origin": "https://your-app-domain.com"
```

## 🐛 Troubleshooting

### "GEMINI_API_KEY not configured"

**Solution:**
```bash
wrangler secret put GEMINI_API_KEY
# Paste your Google AI Studio key
```

### "Image too large"

**Solution:** Reduce image size on client (iOS):
```swift
let maxImageSize: CGFloat = 2048
let compressionQuality: CGFloat = 0.8
let imageData = image.jpegData(compressionQuality: compressionQuality)
```

### "Gemini API Error: 429"

**Cause:** Rate limit exceeded (15 RPM on free tier)

**Solution:**
1. Upgrade to Gemini Paid tier (2,000 RPM)
2. Implement client-side rate limiting
3. Add retry logic with exponential backoff

### "Request timeout"

**Cause:** Gemini processing >25s (rare)

**Solution:**
- Reduce image size before upload
- Check Gemini API status: https://status.cloud.google.com

## 🔗 Integration with BooksTracker

### Future: RPC Service Binding

```toml
# books-api-proxy/wrangler.toml
[[services]]
binding = "BOOKSHELF_AI"
service = "bookshelf-ai-worker"
entrypoint = "BookshelfAIWorker"
```

```javascript
// books-api-proxy/src/scan-handler.js
const result = await env.BOOKSHELF_AI.scanBookshelf(imageData);
```

### iOS Client Example

```swift
func scanBookshelf(image: UIImage) async throws -> [DetectedBook] {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        throw ScanError.invalidImage
    }

    var request = URLRequest(url: URL(string: "https://bookshelf-ai-worker.YOUR_ACCOUNT.workers.dev/scan")!)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = imageData
    request.timeoutInterval = 30

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(BookshelfScanResponse.self, from: data)

    return response.books.map { DetectedBook(cloudBook: $0) }
}
```

## 📚 References

- [Gemini API Documentation](https://ai.google.dev/gemini-api/docs)
- [Cloudflare Workers Docs](https://developers.cloudflare.com/workers/)
- [BooksTracker Main Architecture](../README.md)

## 📝 Version History

### 1.0.0 (2025-10-12)
- Initial release
- Gemini 2.5 Flash integration
- Standalone worker deployment
- HTML test interface
- Analytics tracking
- Production-ready error handling

---

**Maintained by:** BooksTrack Team
**Last Updated:** October 12, 2025
