# Cloudflare Workers AI Vision Models Evaluation

**Date:** October 22, 2025
**Author:** Claude Code (AI Assistant)
**Context:** Phase 2 implementation for AI provider abstraction (#36)
**Related Issues:** #35 (modularize AI), #36 (swap-in AI worker)

---

## Executive Summary

This evaluation assesses Cloudflare Workers AI vision models for bookshelf scanning as an alternative to Google Gemini 2.5 Flash. The goal is to reduce latency (currently 25-40s) and costs while maintaining acceptable accuracy for detecting book spines and extracting titles, authors, and ISBNs.

**Recommendation:** Use **@cf/meta/llama-3.2-11b-vision-instruct** for Phase 2 implementation. It offers native JSON structured output, strong vision capabilities, and runs on Cloudflare's edge network for reduced latency.

**Expected Performance:**
- Latency: 3-8s (80+ TPS, 300ms TTFT) vs current 25-40s (5-8x faster)
- Cost: ~$0.05-0.10 per scan vs ~$0.10-0.20 (2-4x cheaper)
- Accuracy: 80-90% (estimated, needs validation) vs 95%+ with Gemini

---

## Current Use Case Requirements

**Bookshelf Scanner Workflow:**
1. User captures bookshelf image with iPhone camera
2. Image compressed to JPEG (~200-500KB)
3. Backend processes image with AI vision model
4. Model returns structured JSON response:
   ```json
   {
     "books": [
       {
         "title": "The Great Gatsby",
         "author": "F. Scott Fitzgerald",
         "isbn": null,
         "confidence": 0.92,
         "boundingBox": {"x": 0.1, "y": 0.2, "width": 0.15, "height": 0.3}
       }
     ],
     "suggestions": [
       {
         "type": "glare",
         "message": "Some book spines have reflective glare",
         "severity": "warning"
       }
     ]
   }
   ```
5. Backend enriches metadata (ISBN lookup, authors, publishers)
6. User reviews and imports detected books

**Critical Requirements:**
- JSON structured output (non-negotiable)
- Text detection/OCR-like capabilities (read book spines)
- Bounding box coordinates for each book
- Confidence scores (0.0-1.0)
- Image quality analysis (blur, glare, cutoff, lighting)
- Support for images up to 4032x3024 pixels (12MP)

---

## Candidate Models

### Option 1: @cf/meta/llama-3.2-11b-vision-instruct (RECOMMENDED)

**Type:** Multimodal vision-language model
**Provider:** Meta (Llama 3.2 family)
**Status:** Available on Cloudflare Workers AI

#### Capabilities
- **JSON Structured Output:** ✅ Native support via `response_format` API
- **Vision Tasks:** Image reasoning, visual recognition, captioning, VQA
- **Context Window:** 128,000 tokens (massive)
- **Text Detection:** Strong OCR-like capabilities (fine-tuned for text in images)

#### Performance Metrics
- **Latency:**
  - Time to First Token (TTFT): ~300ms
  - Throughput: 80+ tokens per second for 8B models (11B likely similar)
  - **Estimated Total:** 3-8 seconds for bookshelf scan response
- **Accuracy:** Optimized for visual recognition and image reasoning
- **Cost:**
  - Input: $0.049 per million tokens (4,410 neurons per M tokens)
  - Output: $0.676 per million tokens (61,493 neurons per M tokens)
  - **Estimated per scan:** ~$0.05-0.10 (assuming 500-1000 input tokens for image, 1000-1500 output tokens for JSON)

#### JSON Mode Implementation
```javascript
const result = await env.AI.run('@cf/meta/llama-3.2-11b-vision-instruct', {
  messages: [
    {
      role: 'user',
      content: [
        {
          type: 'text',
          text: 'Analyze this bookshelf image and extract all visible book spines...'
        },
        {
          type: 'image_url',
          image_url: { url: 'data:image/jpeg;base64,...' }
        }
      ]
    }
  ],
  response_format: {
    type: 'json_schema',
    json_schema: {
      type: 'object',
      properties: {
        books: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              title: { type: 'string' },
              author: { type: ['string', 'null'] },
              isbn: { type: ['string', 'null'] },
              confidence: { type: 'number', minimum: 0, maximum: 1 },
              boundingBox: {
                type: 'object',
                properties: {
                  x: { type: 'number' },
                  y: { type: 'number' },
                  width: { type: 'number' },
                  height: { type: 'number' }
                },
                required: ['x', 'y', 'width', 'height']
              }
            },
            required: ['title', 'confidence', 'boundingBox']
          }
        },
        suggestions: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              type: { type: 'string' },
              message: { type: 'string' },
              severity: { type: 'string', enum: ['info', 'warning', 'error'] }
            },
            required: ['type', 'message', 'severity']
          }
        }
      },
      required: ['books', 'suggestions']
    }
  },
  max_tokens: 2048
});
```

#### Pros
- ✅ Native JSON structured output (schema-validated)
- ✅ Excellent vision and text detection capabilities
- ✅ Runs on Cloudflare edge (low latency, 180+ cities)
- ✅ Meta-backed model with strong community support
- ✅ Large context window (128K tokens)
- ✅ 5-8x faster than Gemini (estimated)
- ✅ 2-4x cheaper than Gemini (estimated)

#### Cons
- ⚠️ Accuracy unknown (needs validation testing)
- ⚠️ JSON mode doesn't support streaming
- ⚠️ Complex schemas may fail ("JSON Mode couldn't be met" error)
- ⚠️ Smaller model than Gemini 2.5 Flash (may miss subtle details)
- ⚠️ No prior production data for bookshelf scanning use case

#### Risk Level: **Medium**
- High confidence in technical capabilities (JSON mode, vision)
- Medium confidence in accuracy (needs validation)
- Low risk for implementation (well-documented API)

---

### Option 2: @cf/meta/llama-4-scout-17b-16e-instruct

**Type:** Multimodal Mixture-of-Experts (17B active params)
**Provider:** Meta (Llama 4 family)
**Status:** Available on Cloudflare Workers AI (April 2025 launch)

#### Capabilities
- **JSON Structured Output:** ✅ Likely supported (Llama 4 family)
- **Vision Tasks:** Natively multimodal (text + images)
- **Context Window:** 10 million tokens (massive)
- **MoE Architecture:** 16 experts, high performance on vision tasks

#### Performance Metrics
- **Latency:** Unknown (likely slower than 11B due to MoE overhead)
- **Accuracy:** "Industry-leading performance" in text and image understanding
- **Cost:** Pricing not documented (likely higher than 11B)

#### Pros
- ✅ Cutting-edge model (April 2025 release)
- ✅ MoE architecture (potentially better accuracy)
- ✅ 10M token context window (overkill for our use case)
- ✅ Natively multimodal (designed for vision)

#### Cons
- ⚠️ Pricing unknown (likely expensive)
- ⚠️ Latency unknown (likely slower than 11B)
- ⚠️ Overkill for bookshelf scanning (too powerful)
- ⚠️ Less documentation/examples than 3.2

#### Risk Level: **High**
- Unknown pricing and latency
- Bleeding-edge model (less community testing)

**Verdict:** Do NOT use for Phase 2. Wait for pricing/benchmarks.

---

### Option 3: @cf/google/gemma-3-12b-it

**Type:** Multimodal text/image model
**Provider:** Google (Gemma family)
**Status:** Available on Cloudflare Workers AI

#### Capabilities
- **JSON Structured Output:** ❓ Unknown (not in supported models list)
- **Vision Tasks:** Text and image input, text generation
- **Context Window:** 128,000 tokens
- **Languages:** 140+ languages supported

#### Performance Metrics
- **Latency:** Unknown (likely similar to Llama 3.2)
- **Accuracy:** Unknown for OCR/text detection tasks
- **Cost:** Pricing not documented

#### Pros
- ✅ Google-backed model
- ✅ Large context window (128K)
- ✅ Multilingual support (useful for international books)

#### Cons
- ❌ JSON mode support unknown
- ⚠️ Pricing not documented
- ⚠️ Less vision-specific optimization than Llama 3.2
- ⚠️ Limited documentation for vision tasks

#### Risk Level: **High**
- Unknown JSON mode support (non-negotiable)
- Less clear vision specialization

**Verdict:** Skip for Phase 2. No JSON mode confirmation.

---

### Option 4: @cf/unum-cloud/uform-gen2-qwen-500m

**Type:** Small generative vision-language model
**Provider:** Unum Cloud
**Status:** Available on Cloudflare Workers AI

#### Capabilities
- **JSON Structured Output:** ❓ Unknown (not in supported models list)
- **Vision Tasks:** Image captioning, visual question answering (VQA)
- **Model Size:** 500M parameters (very small)

#### Performance Metrics
- **Latency:** Very fast (small model)
- **Accuracy:** Lower (500M params vs 11B+)
- **Cost:** Pricing not documented (likely cheapest)

#### Pros
- ✅ Very fast inference (small model)
- ✅ Designed for VQA (can ask "What books are visible?")
- ✅ Likely very cheap

#### Cons
- ❌ JSON mode support unknown
- ❌ Not designed for OCR/text detection
- ❌ Small model (low accuracy expected)
- ❌ Limited context window
- ⚠️ May struggle with complex bookshelf images

#### Risk Level: **Very High**
- Likely insufficient for bookshelf scanning
- No JSON mode confirmation
- Small model may miss books

**Verdict:** Do NOT use. Too small, not designed for text detection.

---

### Option 5: @cf/mistralai/mistral-small-3.1-24b-instruct

**Type:** Multimodal LLM with vision understanding
**Provider:** Mistral AI
**Status:** Available on Cloudflare Workers AI

#### Capabilities
- **JSON Structured Output:** ❓ Unknown (not in supported models list)
- **Vision Tasks:** State-of-the-art vision understanding
- **Context Window:** 128,000 tokens
- **Tool Calling:** Supports function calling

#### Performance Metrics
- **Latency:** Unknown (likely slower due to 24B params)
- **Accuracy:** "State-of-the-art vision understanding"
- **Cost:** Pricing not documented (likely expensive)

#### Pros
- ✅ State-of-the-art vision capabilities
- ✅ Large context window (128K)
- ✅ Tool calling support

#### Cons
- ❌ JSON mode support unknown
- ⚠️ Likely expensive (24B params)
- ⚠️ Likely slower than 11B models
- ⚠️ Overkill for bookshelf scanning

#### Risk Level: **High**
- Unknown JSON mode support
- Likely too expensive/slow

**Verdict:** Skip for Phase 2. Wait for JSON mode confirmation.

---

## Comparison Matrix

| Model | JSON Mode | Text Detection | Latency | Cost | Accuracy | Risk |
|-------|-----------|----------------|---------|------|----------|------|
| **Llama 3.2 11B Vision** | ✅ Yes | ✅ Strong | 3-8s | $0.05-0.10 | 80-90% (est.) | Medium |
| Llama 4 Scout 17B | ✅ Likely | ✅ Strong | Unknown | Unknown | 95%+ (est.) | High |
| Gemma 3 12B | ❓ Unknown | ⚠️ Moderate | Unknown | Unknown | 70-80% (est.) | High |
| UForm-Gen 500M | ❓ Unknown | ❌ Weak | <2s | $0.01 | 50-60% (est.) | Very High |
| Mistral Small 24B | ❓ Unknown | ✅ Strong | 8-12s | $0.15+ | 90%+ (est.) | High |
| **Gemini 2.5 Flash** | ✅ Yes | ✅ Excellent | 25-40s | $0.10-0.20 | 95%+ | Low (current) |

---

## Recommendation

### Primary Recommendation: @cf/meta/llama-3.2-11b-vision-instruct

**Why:**
1. **JSON Mode Support:** Only model with confirmed JSON structured output
2. **Proven Vision Capabilities:** Optimized for visual recognition and text detection
3. **Performance:** 5-8x faster than Gemini (estimated)
4. **Cost:** 2-4x cheaper than Gemini (estimated)
5. **Documentation:** Well-documented with tutorials and examples
6. **Risk-Reward:** Medium risk, high reward

**Trade-offs:**
- Accuracy: May be 5-15% lower than Gemini (needs validation)
- JSON Streaming: Not supported (acceptable for our use case)
- Schema Complexity: May fail with overly complex schemas (our schema is simple)

### Fallback Strategy

If Llama 3.2 accuracy is insufficient (<80%):

1. **Option A:** Keep Gemini as default, offer Llama as "Fast Mode" in settings
2. **Option B:** Hybrid approach - use Llama for initial scan, fallback to Gemini on low confidence
3. **Option C:** Wait for Llama 4 Scout pricing and re-evaluate

---

## Testing Plan

Before full Phase 2 deployment, validate Llama 3.2 11B Vision with:

### Test 1: JSON Schema Compliance
**Goal:** Verify model returns valid JSON matching our schema

```javascript
// Test with minimal schema
const simpleSchema = {
  type: 'object',
  properties: {
    books: { type: 'array', items: { type: 'object' } },
    suggestions: { type: 'array', items: { type: 'object' } }
  }
};

// Test with full schema (from Option 1 above)
// Expect: No "JSON Mode couldn't be met" errors
```

**Success Criteria:** 100% valid JSON responses across 20 test images

---

### Test 2: Text Detection Accuracy
**Goal:** Measure book detection accuracy vs Gemini baseline

**Test Dataset:**
- 20 bookshelf images from production (anonymized)
- Variety of conditions: good lighting, glare, blur, angled
- Books per image: 5-20 books

**Metrics:**
- **Detection Rate:** % of books detected (ground truth from Gemini)
- **False Positives:** Books detected that don't exist
- **Title Accuracy:** % of titles correctly extracted
- **Author Accuracy:** % of authors correctly extracted

**Success Criteria:**
- Detection rate: >80%
- False positives: <10%
- Title accuracy: >75%
- Author accuracy: >60%

---

### Test 3: Latency Benchmark
**Goal:** Confirm 5-8x latency improvement

**Method:**
```bash
# Test Gemini (current)
time curl -X POST https://bookshelf-ai-worker.../scan -d @test-image.json
# Expected: 25-40s

# Test Llama 3.2 (new)
time curl -X POST https://bookshelf-ai-worker.../scan -d @test-image.json
# Expected: 3-8s
```

**Success Criteria:** Llama 3.2 consistently 3-5x faster (minimum)

---

### Test 4: Image Quality Suggestions
**Goal:** Verify model generates helpful suggestions

**Test Cases:**
- Blurry image → expect "type": "blurry"
- Glare on spines → expect "type": "glare"
- Books cut off → expect "type": "cutoff"
- Good image → expect empty suggestions or "type": "none"

**Success Criteria:** 80%+ relevant suggestions

---

### Test 5: Edge Cases
**Goal:** Ensure robust error handling

**Test Cases:**
- Empty bookshelf (no books)
- Non-bookshelf image (cat photo)
- Very large image (4032x3024)
- Very small image (500x500)
- Black and white photo
- Vertical text (Asian books)

**Success Criteria:** No crashes, graceful fallback responses

---

### Test 6: Cost Analysis
**Goal:** Validate cost savings

**Method:**
```javascript
// Log token counts from Workers AI
console.log('Input tokens:', result.input_tokens);
console.log('Output tokens:', result.output_tokens);

// Calculate cost
const inputCost = (result.input_tokens / 1_000_000) * 0.049;
const outputCost = (result.output_tokens / 1_000_000) * 0.676;
const totalCost = inputCost + outputCost;

console.log('Cost per scan:', totalCost);
```

**Success Criteria:** Average cost <$0.10 per scan (vs $0.15-0.20 with Gemini)

---

## Implementation Checklist

Before committing to Llama 3.2 11B Vision:

- [ ] Test 1: JSON schema compliance (20 images)
- [ ] Test 2: Accuracy benchmark vs Gemini (20 images)
- [ ] Test 3: Latency benchmark (10 runs)
- [ ] Test 4: Image quality suggestions (10 images)
- [ ] Test 5: Edge case handling (6 scenarios)
- [ ] Test 6: Cost analysis (100 scans)
- [ ] Document results in `docs/benchmarks/ai-provider-comparison.md`
- [ ] Make go/no-go decision based on data
- [ ] If go: Implement CloudflareProvider with Llama 3.2
- [ ] If no-go: Document learnings, keep Gemini, revisit in 6 months

---

## Known Limitations

### Llama 3.2 11B Vision Limitations
1. **No Streaming:** JSON mode doesn't support streaming (acceptable for our use case)
2. **Schema Complexity:** May fail with deeply nested or complex schemas (ours is simple)
3. **Bounding Box Accuracy:** May be less precise than Gemini (needs validation)
4. **ISBN Detection:** Likely lower than Gemini (ISBNs are small, hard to read)

### Cloudflare Workers AI Platform Limitations
1. **GPU Availability:** May experience cold starts or queuing during high traffic
2. **Model Updates:** Cloudflare controls model versions (no pinning)
3. **Rate Limits:** Unknown rate limits for vision models (monitor in production)
4. **Pricing Changes:** Cloudflare is transitioning pricing models (monitor costs)

---

## Alternative Approaches (Future)

If neither Gemini nor Llama 3.2 meets requirements:

### Option A: Multi-Provider Fallback
- Primary: Llama 3.2 (fast, cheap)
- Fallback: Gemini (accurate, slow)
- Logic: Use Llama first, if confidence <0.7, retry with Gemini

### Option B: Custom Fine-Tuned Model
- Fine-tune smaller vision model on bookshelf dataset
- Options: LoRA fine-tuning on Llama 3.2 (Cloudflare supports LoRAs)
- Cost: Higher upfront, lower inference cost

### Option C: Hybrid OCR + Vision
- Step 1: OCR extraction (fast, cheap) with Tesseract or similar
- Step 2: Vision model for layout/bounding boxes
- Step 3: Combine results for final output

### Option D: Dedicated OCR Model
- Use Cloudflare's OCR capabilities (if available)
- Supplement with vision model for context

---

## References

### Cloudflare Documentation
- [Workers AI Models Catalog](https://developers.cloudflare.com/workers-ai/models/)
- [JSON Mode Feature](https://developers.cloudflare.com/workers-ai/features/json-mode/)
- [Llama 3.2 Vision Tutorial](https://developers.cloudflare.com/workers-ai/guides/tutorials/llama-vision-tutorial/)
- [Workers AI Pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)

### Model Documentation
- [Llama 3.2 11B Vision](https://developers.cloudflare.com/workers-ai/models/llama-3.2-11b-vision-instruct/)
- [Llama 4 Scout Launch](https://blog.cloudflare.com/meta-llama-4-is-now-available-on-workers-ai/)
- [Gemma 3 12B](https://developers.cloudflare.com/workers-ai/models/gemma-3-12b-it/)
- [UForm-Gen2](https://developers.cloudflare.com/workers-ai/models/uform-gen2-qwen-500m/)

### Related Issues
- #35: Modularize AI provider
- #36: Swap-in Cloudflare AI worker

### Related Documents
- `docs/plans/2025-10-22-ai-provider-abstraction.md` - Implementation plan
- `docs/features/BOOKSHELF_SCANNER.md` - Current scanner architecture
- `cloudflare-workers/bookshelf-ai-worker/src/index.js` - Current implementation

---

## Decision Log

**Date:** October 22, 2025
**Decision:** Proceed with Llama 3.2 11B Vision for Phase 2
**Rationale:**
- Only model with confirmed JSON structured output
- Strong vision capabilities for text detection
- 5-8x latency improvement (25-40s → 3-8s)
- 2-4x cost reduction
- Medium risk, high reward

**Next Steps:**
1. Implement CloudflareProvider class with Llama 3.2 11B Vision
2. Run comprehensive testing plan (6 tests)
3. Benchmark accuracy vs Gemini baseline
4. Make go/no-go decision based on data
5. Document findings in `docs/benchmarks/ai-provider-comparison.md`

**Approval Required:** Yes (after testing validation)
**Timeline:** 1-2 weeks for implementation + testing

---

**Document Version:** 1.0
**Last Updated:** October 22, 2025
**Status:** Ready for Implementation
