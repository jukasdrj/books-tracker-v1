# AI Provider Abstraction Implementation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Modularize the bookshelf-ai-worker to support multiple AI vision providers (Gemini, Cloudflare Workers AI) through a clean abstraction layer.

**Architecture:** Provider pattern with factory-based initialization. Each provider implements a standard interface for image scanning. Configuration-driven provider selection via environment variables.

**Tech Stack:** Cloudflare Workers, Gemini API, Cloudflare Workers AI, JavaScript ES modules

**Related Issues:**
- #35 "shelf - modularize the ai"
- #36 "cf - swap-in ai worker"

**Reference:** `MODULARIZATION_PLAN.md` in project root

---

## Phase 1: Provider Abstraction (No Behavior Change)

### Task 1: Define AIProvider Interface

**Files:**
- Create: `cloudflare-workers/bookshelf-ai-worker/src/providers/AIProvider.interface.js`

**Step 1: Write the interface documentation**

Create the provider contract:

```javascript
/**
 * Standard interface for AI vision providers
 * All providers must implement this interface to scan bookshelf images
 */

/**
 * @typedef {Object} ScanResult
 * @property {Array<DetectedBook>} books - Array of detected books
 * @property {Array<Suggestion>} suggestions - Image quality suggestions
 * @property {Object} metadata - Provider-specific metadata
 */

/**
 * @typedef {Object} DetectedBook
 * @property {string} title - Book title
 * @property {string|null} author - Author name (if detected)
 * @property {string|null} isbn - ISBN (if detected)
 * @property {number} confidence - Detection confidence (0.0-1.0)
 * @property {Object} boundingBox - Bounding box coordinates (normalized 0-1)
 * @property {number} boundingBox.x - X coordinate
 * @property {number} boundingBox.y - Y coordinate
 * @property {number} boundingBox.width - Width
 * @property {number} boundingBox.height - Height
 */

/**
 * @typedef {Object} Suggestion
 * @property {string} type - Suggestion type (blurry, glare, cutoff, etc.)
 * @property {string} message - Human-readable message
 * @property {string} severity - Severity level (warning, error, info)
 */

export class AIProvider {
    /**
     * Scan a bookshelf image and extract book information
     * @param {ArrayBuffer} imageData - Raw image data
     * @param {Object} env - Cloudflare Worker environment bindings
     * @returns {Promise<ScanResult>} Scan results with books, suggestions, metadata
     * @throws {Error} If scanning fails
     */
    async scanImage(imageData, env) {
        throw new Error('AIProvider.scanImage() must be implemented by subclass');
    }

    /**
     * Get provider name for logging/debugging
     * @returns {string} Provider name
     */
    getProviderName() {
        throw new Error('AIProvider.getProviderName() must be implemented by subclass');
    }
}
```

**Step 2: Commit interface definition**

```bash
cd cloudflare-workers/bookshelf-ai-worker
git add src/providers/AIProvider.interface.js
git commit -m "feat(ai): add AIProvider interface definition

- Defines standard contract for all AI vision providers
- Includes JSDoc types for ScanResult, DetectedBook, Suggestion
- Establishes scanImage() and getProviderName() methods
- Related to #35 (modularize AI) and #36 (swap-in AI worker)"
```

---

### Task 2: Extract GeminiProvider

**Files:**
- Create: `cloudflare-workers/bookshelf-ai-worker/src/providers/geminiProvider.js`
- Read: `cloudflare-workers/bookshelf-ai-worker/src/index.js` (lines with `processImageWithAI`)

**Step 1: Create GeminiProvider skeleton**

```javascript
import { AIProvider } from './AIProvider.interface.js';

/**
 * Gemini AI vision provider implementation
 * Uses Google Gemini 2.5 Flash for bookshelf scanning
 */
export class GeminiProvider extends AIProvider {
    constructor(apiKey) {
        super();
        if (!apiKey) {
            throw new Error('GeminiProvider requires GEMINI_API_KEY');
        }
        this.apiKey = apiKey;
        this.modelName = 'gemini-2.5-flash-latest';
        this.apiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/${this.modelName}:generateContent`;
    }

    getProviderName() {
        return 'gemini';
    }

    async scanImage(imageData, env) {
        // Implementation will be moved from index.js
        throw new Error('Not yet implemented');
    }
}
```

**Step 2: Run basic instantiation test**

Create temporary test file to verify class loads:

```javascript
// Test file (delete after verification)
import { GeminiProvider } from './src/providers/geminiProvider.js';

try {
    const provider = new GeminiProvider('test-key');
    console.log('✅ Provider name:', provider.getProviderName());
    console.log('✅ GeminiProvider class loads successfully');
} catch (error) {
    console.error('❌ Failed to load GeminiProvider:', error);
}
```

Run: `node --input-type=module --eval "$(cat test-gemini.js)"`
Expected: `✅ Provider name: gemini`

**Step 3: Extract Gemini-specific logic from index.js**

Copy the `processImageWithAI` function logic into `scanImage` method:

```javascript
async scanImage(imageData, env) {
    try {
        // Convert ArrayBuffer to base64
        const base64Image = btoa(
            String.fromCharCode(...new Uint8Array(imageData))
        );

        // Build Gemini-specific payload
        const payload = {
            contents: [{
                parts: [
                    {
                        text: `Analyze this bookshelf image and extract all visible book spines.
Return JSON with this exact structure:
{
  "books": [{"title": "string", "author": "string|null", "isbn": "string|null", "confidence": 0.0-1.0, "boundingBox": {"x": 0.0-1.0, "y": 0.0-1.0, "width": 0.0-1.0, "height": 0.0-1.0}}],
  "suggestions": [{"type": "string", "message": "string", "severity": "warning|error|info"}]
}

Suggestions types: blurry, glare, cutoff, too_far, angle, lighting, obstruction, partial, small_text`
                    },
                    {
                        inline_data: {
                            mime_type: 'image/jpeg',
                            data: base64Image
                        }
                    }
                ]
            }],
            generationConfig: {
                temperature: 0.2,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 2048,
                responseMimeType: 'application/json'
            }
        };

        // Call Gemini API
        const response = await fetch(
            `${this.apiEndpoint}?key=${this.apiKey}`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(payload)
            }
        );

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Gemini API error (${response.status}): ${errorText}`);
        }

        const result = await response.json();

        // Extract JSON from Gemini response
        const content = result.candidates?.[0]?.content?.parts?.[0]?.text;
        if (!content) {
            throw new Error('No content in Gemini response');
        }

        const scanResult = JSON.parse(content);

        // Add provider metadata
        return {
            books: scanResult.books || [],
            suggestions: scanResult.suggestions || [],
            metadata: {
                provider: 'gemini',
                model: this.modelName,
                timestamp: new Date().toISOString(),
                processingTimeMs: Date.now() - startTime
            }
        };

    } catch (error) {
        console.error('[GeminiProvider] Scan failed:', error);
        throw error;
    }
}
```

**Step 4: Add timing tracking**

Add `startTime` at the top of `scanImage`:

```javascript
async scanImage(imageData, env) {
    const startTime = Date.now();
    try {
        // ... existing code ...
```

**Step 5: Commit GeminiProvider implementation**

```bash
git add src/providers/geminiProvider.js
git commit -m "feat(ai): implement GeminiProvider class

- Extracts Gemini-specific logic from index.js
- Implements AIProvider interface
- Handles base64 encoding, API calls, response parsing
- Adds provider metadata to results
- Related to #35"
```

---

### Task 3: Create AIProviderFactory

**Files:**
- Create: `cloudflare-workers/bookshelf-ai-worker/src/providers/AIProviderFactory.js`

**Step 1: Implement factory function**

```javascript
import { GeminiProvider } from './geminiProvider.js';

/**
 * Factory for creating AI provider instances based on configuration
 */
export class AIProviderFactory {
    /**
     * Create provider instance from environment configuration
     * @param {Object} env - Cloudflare Worker environment bindings
     * @returns {AIProvider} Configured provider instance
     * @throws {Error} If provider configuration is invalid
     */
    static createProvider(env) {
        const providerType = env.AI_PROVIDER || 'gemini';

        switch (providerType.toLowerCase()) {
            case 'gemini':
                if (!env.GEMINI_API_KEY) {
                    throw new Error('GEMINI_API_KEY required for gemini provider');
                }
                console.log('[AIProviderFactory] Creating Gemini provider');
                return new GeminiProvider(env.GEMINI_API_KEY);

            // Future providers will be added here
            // case 'cloudflare':
            //     return new CloudflareProvider(env.AI);

            default:
                throw new Error(`Unknown AI provider: ${providerType}`);
        }
    }

    /**
     * Get list of supported provider types
     * @returns {Array<string>} Supported provider names
     */
    static getSupportedProviders() {
        return ['gemini']; // Will expand to ['gemini', 'cloudflare']
    }
}
```

**Step 2: Write factory test**

Create `test-factory.js`:

```javascript
import { AIProviderFactory } from './src/providers/AIProviderFactory.js';

const testEnv = {
    AI_PROVIDER: 'gemini',
    GEMINI_API_KEY: 'test-key-123'
};

try {
    const provider = AIProviderFactory.createProvider(testEnv);
    console.log('✅ Factory created provider:', provider.getProviderName());
    console.log('✅ Supported providers:', AIProviderFactory.getSupportedProviders());
} catch (error) {
    console.error('❌ Factory test failed:', error);
}
```

Run: `node --input-type=module test-factory.js`
Expected: `✅ Factory created provider: gemini`

**Step 3: Test error handling**

Test missing API key:

```javascript
const badEnv = { AI_PROVIDER: 'gemini' }; // Missing GEMINI_API_KEY

try {
    AIProviderFactory.createProvider(badEnv);
    console.error('❌ Should have thrown error for missing API key');
} catch (error) {
    console.log('✅ Correctly throws error:', error.message);
}
```

Expected: `✅ Correctly throws error: GEMINI_API_KEY required for gemini provider`

**Step 4: Commit factory**

```bash
git add src/providers/AIProviderFactory.js
git commit -m "feat(ai): add AIProviderFactory for provider selection

- Factory reads AI_PROVIDER env var to select provider
- Validates required environment bindings
- Returns configured provider instance
- Supports listing available providers
- Related to #35"
```

---

### Task 4: Refactor index.js to Use Factory

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/src/index.js`

**Step 1: Add factory import**

At the top of `index.js`:

```javascript
import { AIProviderFactory } from './providers/AIProviderFactory.js';
```

**Step 2: Replace processImageWithAI function**

Find the `processImageWithAI` function and replace it with:

```javascript
/**
 * Process bookshelf image using configured AI provider
 * @param {ArrayBuffer} imageData - Raw image data
 * @param {Object} env - Worker environment bindings
 * @returns {Promise<Object>} Scan results
 */
async function processImageWithAI(imageData, env) {
    const provider = AIProviderFactory.createProvider(env);
    console.log(`[Worker] Using AI provider: ${provider.getProviderName()}`);
    return await provider.scanImage(imageData, env);
}
```

**Step 3: Verify no direct Gemini references remain**

Search for Gemini-specific code:

```bash
grep -n "generativelanguage.googleapis.com" src/index.js
grep -n "gemini-2.5-flash" src/index.js
grep -n "GEMINI_API_KEY" src/index.js
```

Expected: No matches (all moved to GeminiProvider)

**Step 4: Test with existing tests**

Run: `npm test`
Expected: All existing tests pass (behavior unchanged)

**Step 5: Commit refactored index.js**

```bash
git add src/index.js
git commit -m "refactor(ai): use AIProviderFactory in main worker

- Removes direct Gemini API code from index.js
- Uses factory to get configured provider
- Maintains existing worker behavior (no API changes)
- Completes Phase 1 of modularization
- Related to #35

BREAKING: None (internal refactor only)
TESTED: Existing test suite passes"
```

---

### Task 5: Update wrangler.toml Configuration

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/wrangler.toml`

**Step 1: Add AI_PROVIDER environment variable**

Add to `[vars]` section:

```toml
[vars]
AI_PROVIDER = "gemini"  # Options: gemini, cloudflare (future)
```

**Step 2: Document configuration**

Add comment block:

```toml
# AI Provider Configuration
# AI_PROVIDER: Which AI vision provider to use
#   - "gemini": Google Gemini 2.5 Flash (requires GEMINI_API_KEY secret)
#   - "cloudflare": Cloudflare Workers AI (requires AI binding, Phase 2)
[vars]
AI_PROVIDER = "gemini"
```

**Step 3: Verify secrets are configured**

Check that GEMINI_API_KEY is set:

```bash
wrangler secret list
```

Expected: `GEMINI_API_KEY` appears in list

**Step 4: Test deployment**

Deploy with new configuration:

```bash
npm run deploy
```

Expected: Deployment succeeds, worker responds to requests

**Step 5: Commit configuration**

```bash
git add wrangler.toml
git commit -m "feat(ai): add AI_PROVIDER configuration variable

- Adds AI_PROVIDER to wrangler.toml
- Documents provider options and requirements
- Defaults to 'gemini' (existing behavior)
- Related to #35"
```

---

### Task 6: Add Provider Health Check Endpoint

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/src/index.js`

**Step 1: Add /health/provider endpoint**

Add new route handler in `fetch()` function:

```javascript
// Add after existing /health endpoint
if (url.pathname === '/health/provider') {
    try {
        const provider = AIProviderFactory.createProvider(env);
        return new Response(JSON.stringify({
            status: 'ok',
            provider: provider.getProviderName(),
            supportedProviders: AIProviderFactory.getSupportedProviders(),
            timestamp: new Date().toISOString()
        }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });
    } catch (error) {
        return new Response(JSON.stringify({
            status: 'error',
            error: error.message
        }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}
```

**Step 2: Test health endpoint locally**

Start dev server:

```bash
npm run dev
```

Test in another terminal:

```bash
curl http://localhost:8787/health/provider
```

Expected output:
```json
{
  "status": "ok",
  "provider": "gemini",
  "supportedProviders": ["gemini"],
  "timestamp": "2025-10-22T..."
}
```

**Step 3: Deploy and test in production**

```bash
npm run deploy
curl https://bookshelf-ai-worker.jukasdrj.workers.dev/health/provider
```

Expected: Same JSON with current provider info

**Step 4: Commit health endpoint**

```bash
git add src/index.js
git commit -m "feat(ai): add /health/provider endpoint

- Returns current provider name
- Lists supported providers
- Helps verify configuration
- Related to #35"
```

---

## Phase 1 Completion Checklist

**Verify Phase 1 before proceeding to Phase 2:**

- [ ] `AIProvider.interface.js` exists with complete JSDoc
- [ ] `GeminiProvider` implements `scanImage()` and `getProviderName()`
- [ ] `AIProviderFactory` creates Gemini provider from env config
- [ ] `index.js` uses factory instead of direct Gemini code
- [ ] `wrangler.toml` has `AI_PROVIDER = "gemini"`
- [ ] `/health/provider` endpoint returns provider info
- [ ] All existing tests pass (no behavior change)
- [ ] Deployed worker processes images successfully
- [ ] Zero direct Gemini references in `index.js`

**Test the complete flow:**

```bash
# 1. Deploy updated worker
npm run deploy

# 2. Test health endpoint
curl https://bookshelf-ai-worker.jukasdrj.workers.dev/health/provider

# 3. Test actual image scan (use iOS app or curl with base64 image)
# Should work exactly as before, but using new provider system

# 4. Check logs
wrangler tail bookshelf-ai-worker --format pretty
# Should see: "[Worker] Using AI provider: gemini"
```

---

## Phase 2: Cloudflare Workers AI Integration

**Prerequisites before starting Phase 2:**
- [ ] Phase 1 complete and tested
- [ ] Research Cloudflare Workers AI vision models
- [ ] Decision made on which model to use (e.g., `@cf/llava-hf/llava-1.5-7b-hf`)
- [ ] Understanding of Workers AI binding syntax

### Task 7: Research Cloudflare Workers AI Models

**Files:**
- Create: `docs/research/cloudflare-ai-models-evaluation.md`

**Step 1: Query Cloudflare AI catalog**

Use Cloudflare dashboard or API to list vision models:

```bash
curl https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/ai/models \
  -H "Authorization: Bearer $CF_API_TOKEN" | jq '.result[] | select(.task.name == "Image-to-Text")'
```

**Step 2: Document candidate models**

Create evaluation document:

```markdown
# Cloudflare Workers AI Vision Models Evaluation

## Date: 2025-10-22

## Candidate Models

### Option 1: @cf/llava-hf/llava-1.5-7b-hf
- **Type:** Image-to-text
- **Pros:** Open source, good for general vision tasks
- **Cons:** May need prompt engineering for JSON output
- **Latency:** ~500ms (estimated)

### Option 2: [Other model if available]
...

## Recommendation
[TBD after testing]

## Testing Plan
1. Test JSON output reliability
2. Benchmark latency vs Gemini
3. Evaluate accuracy on bookshelf images
4. Assess cost per request
```

**Step 3: Test model with sample image**

Create test script:

```javascript
// test-cf-ai.js
export default {
    async fetch(request, env) {
        const imageUrl = 'https://example.com/bookshelf-test.jpg';
        const imageResponse = await fetch(imageUrl);
        const imageBlob = await imageResponse.arrayBuffer();

        const result = await env.AI.run('@cf/llava-hf/llava-1.5-7b-hf', {
            image: [...new Uint8Array(imageBlob)],
            prompt: "List all book titles visible on this shelf. Return JSON.",
            max_tokens: 512
        });

        return new Response(JSON.stringify(result, null, 2));
    }
};
```

Deploy test worker and evaluate results.

**Step 4: Document findings**

Update `cloudflare-ai-models-evaluation.md` with:
- Actual test results
- JSON reliability assessment
- Performance metrics
- Recommendation for production

**Step 5: Commit research**

```bash
git add docs/research/cloudflare-ai-models-evaluation.md
git commit -m "docs(ai): evaluate Cloudflare Workers AI vision models

- Tests image-to-text models for bookshelf scanning
- Documents latency, accuracy, cost trade-offs
- Provides recommendation for Phase 2
- Related to #36"
```

---

### Task 8: Implement CloudflareProvider

**Files:**
- Create: `cloudflare-workers/bookshelf-ai-worker/src/providers/cloudflareProvider.js`

**Step 1: Write the failing test**

Create `tests/cloudflare-provider.test.js`:

```javascript
import { CloudflareProvider } from '../src/providers/cloudflareProvider.js';

describe('CloudflareProvider', () => {
    it('should implement AIProvider interface', () => {
        const mockAI = { run: async () => ({}) };
        const provider = new CloudflareProvider(mockAI);

        expect(provider.getProviderName()).toBe('cloudflare');
        expect(typeof provider.scanImage).toBe('function');
    });
});
```

**Step 2: Run test to verify it fails**

```bash
npm test
```

Expected: `FAIL: CloudflareProvider is not defined`

**Step 3: Create CloudflareProvider class**

```javascript
import { AIProvider } from './AIProvider.interface.js';

/**
 * Cloudflare Workers AI vision provider implementation
 * Uses Cloudflare's native AI binding for low-latency vision tasks
 */
export class CloudflareProvider extends AIProvider {
    constructor(aiBinding) {
        super();
        if (!aiBinding) {
            throw new Error('CloudflareProvider requires AI binding');
        }
        this.ai = aiBinding;
        this.modelName = '@cf/llava-hf/llava-1.5-7b-hf'; // Or chosen model
    }

    getProviderName() {
        return 'cloudflare';
    }

    async scanImage(imageData, env) {
        const startTime = Date.now();

        try {
            // Convert ArrayBuffer to array for Workers AI
            const imageArray = [...new Uint8Array(imageData)];

            // Call Workers AI
            const result = await this.ai.run(this.modelName, {
                image: imageArray,
                prompt: `Analyze this bookshelf image and extract all visible book spines.
Return ONLY valid JSON with this exact structure:
{
  "books": [{"title": "string", "author": "string|null", "isbn": "string|null", "confidence": 0.9, "boundingBox": {"x": 0.1, "y": 0.2, "width": 0.15, "height": 0.3}}],
  "suggestions": [{"type": "blurry", "message": "string", "severity": "warning"}]
}

No additional text, only JSON.`,
                max_tokens: 2048
            });

            // Parse response (may need adjustment based on model output format)
            const scanResult = typeof result === 'string'
                ? JSON.parse(result)
                : result;

            return {
                books: scanResult.books || [],
                suggestions: scanResult.suggestions || [],
                metadata: {
                    provider: 'cloudflare',
                    model: this.modelName,
                    timestamp: new Date().toISOString(),
                    processingTimeMs: Date.now() - startTime
                }
            };

        } catch (error) {
            console.error('[CloudflareProvider] Scan failed:', error);
            throw error;
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
npm test
```

Expected: `PASS: CloudflareProvider tests`

**Step 5: Commit CloudflareProvider**

```bash
git add src/providers/cloudflareProvider.js tests/cloudflare-provider.test.js
git commit -m "feat(ai): implement CloudflareProvider for Workers AI

- Implements AIProvider interface with Workers AI binding
- Uses Cloudflare's native vision model for low latency
- Adds provider metadata to results
- Includes unit tests
- Related to #36"
```

---

### Task 9: Update Factory to Support Cloudflare Provider

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/src/providers/AIProviderFactory.js`

**Step 1: Import CloudflareProvider**

Add import at top:

```javascript
import { CloudflareProvider } from './cloudflareProvider.js';
```

**Step 2: Add cloudflare case to factory**

Update `createProvider()` switch:

```javascript
case 'cloudflare':
    if (!env.AI) {
        throw new Error('AI binding required for cloudflare provider');
    }
    console.log('[AIProviderFactory] Creating Cloudflare Workers AI provider');
    return new CloudflareProvider(env.AI);
```

**Step 3: Update supported providers list**

```javascript
static getSupportedProviders() {
    return ['gemini', 'cloudflare'];
}
```

**Step 4: Test factory with cloudflare option**

```javascript
// Test with mock AI binding
const cfEnv = {
    AI_PROVIDER: 'cloudflare',
    AI: { run: async () => ({}) } // Mock binding
};

const provider = AIProviderFactory.createProvider(cfEnv);
console.log('✅ Created provider:', provider.getProviderName()); // Should be 'cloudflare'
```

**Step 5: Commit factory update**

```bash
git add src/providers/AIProviderFactory.js
git commit -m "feat(ai): add Cloudflare provider support to factory

- Factory now creates CloudflareProvider when AI_PROVIDER=cloudflare
- Validates AI binding is present
- Updates supported providers list
- Related to #36"
```

---

### Task 10: Configure Workers AI Binding

**Files:**
- Modify: `cloudflare-workers/bookshelf-ai-worker/wrangler.toml`

**Step 1: Add AI binding**

Add binding configuration:

```toml
# Workers AI Binding (required for AI_PROVIDER="cloudflare")
[ai]
binding = "AI"
```

**Step 2: Update configuration comment**

Update the AI provider comment:

```toml
# AI Provider Configuration
# AI_PROVIDER: Which AI vision provider to use
#   - "gemini": Google Gemini 2.5 Flash (requires GEMINI_API_KEY secret)
#   - "cloudflare": Cloudflare Workers AI (requires [ai] binding below)
[vars]
AI_PROVIDER = "gemini"  # Change to "cloudflare" to use Workers AI

# Workers AI Binding (required for AI_PROVIDER="cloudflare")
[ai]
binding = "AI"
```

**Step 3: Deploy with binding**

```bash
npm run deploy
```

Expected: Deployment succeeds with AI binding enabled

**Step 4: Test health endpoint**

```bash
curl https://bookshelf-ai-worker.jukasdrj.workers.dev/health/provider
```

Expected: Still shows `"provider": "gemini"` (we haven't switched yet)

**Step 5: Commit binding configuration**

```bash
git add wrangler.toml
git commit -m "feat(ai): add Workers AI binding configuration

- Adds [ai] binding for Cloudflare provider
- Updates configuration documentation
- Keeps gemini as default for now
- Related to #36"
```

---

### Task 11: Performance Benchmark & Switch to Cloudflare

**Files:**
- Create: `docs/benchmarks/ai-provider-comparison.md`
- Modify: `cloudflare-workers/bookshelf-ai-worker/wrangler.toml`

**Step 1: Create benchmark script**

Create `scripts/benchmark-providers.sh`:

```bash
#!/bin/bash

echo "=== AI Provider Performance Benchmark ==="
echo ""

# Test image (base64 encoded)
TEST_IMAGE="base64-encoded-bookshelf-image-here"

echo "Testing Gemini provider..."
START=$(date +%s%3N)
curl -X POST https://bookshelf-ai-worker.jukasdrj.workers.dev/scan \
  -H "Content-Type: application/json" \
  -d "{\"image\": \"$TEST_IMAGE\"}" \
  -o /tmp/gemini-result.json
END=$(date +%s%3N)
GEMINI_TIME=$((END - START))
echo "Gemini latency: ${GEMINI_TIME}ms"

# Switch to Cloudflare (manually change AI_PROVIDER and deploy)
# Then repeat test
# Document results in comparison.md
```

**Step 2: Run benchmarks**

Test both providers with identical images:

1. Deploy with `AI_PROVIDER = "gemini"`
2. Run benchmark
3. Deploy with `AI_PROVIDER = "cloudflare"`
4. Run benchmark
5. Compare results

**Step 3: Document results**

Create `docs/benchmarks/ai-provider-comparison.md`:

```markdown
# AI Provider Performance Comparison

## Test Setup
- Date: 2025-10-22
- Image: 3024x4032 bookshelf photo (12 books)
- Region: US-East

## Results

| Metric | Gemini 2.5 Flash | Cloudflare Workers AI | Improvement |
|--------|------------------|----------------------|-------------|
| Latency | 25-40s | 5-8s | 5x faster |
| Accuracy | 95% | 85% | -10% |
| Cost/request | $0.001 | $0.0001 | 10x cheaper |
| Book detection | 12/12 | 10/12 | -2 books |

## Recommendation
[Decision based on data]

## Trade-offs
- Cloudflare: Faster but less accurate
- Gemini: Slower but more reliable
```

**Step 4: Make provider decision**

Based on benchmarks, decide which provider to use as default:

**Option A: Keep Gemini (prioritize accuracy)**
```toml
AI_PROVIDER = "gemini"
```

**Option B: Switch to Cloudflare (prioritize speed)**
```toml
AI_PROVIDER = "cloudflare"
```

**Option C: User-configurable (future enhancement)**
- Add UI toggle in iOS app
- Pass provider preference in request headers

**Step 5: Commit benchmark results**

```bash
git add docs/benchmarks/ai-provider-comparison.md scripts/benchmark-providers.sh
git commit -m "docs(ai): add provider performance benchmarks

- Compares Gemini vs Cloudflare Workers AI
- Documents latency, accuracy, cost trade-offs
- Informs default provider decision
- Related to #36"
```

**Step 6: Update wrangler.toml with decision**

If switching to Cloudflare:

```bash
# Change AI_PROVIDER to cloudflare
git add wrangler.toml
git commit -m "feat(ai): switch default provider to Cloudflare Workers AI

- Changes AI_PROVIDER from gemini to cloudflare
- Reduces latency from 25-40s to 5-8s (5x improvement)
- See docs/benchmarks/ai-provider-comparison.md for analysis
- Related to #36

BREAKING: May have different accuracy characteristics
TESTED: Benchmark shows acceptable trade-offs"
```

---

## Phase 2 Completion Checklist

**Verify Phase 2 before closing issues:**

- [ ] `CloudflareProvider` class implements AIProvider interface
- [ ] Factory creates CloudflareProvider when `AI_PROVIDER = "cloudflare"`
- [ ] `wrangler.toml` has `[ai]` binding configured
- [ ] Performance benchmarks completed and documented
- [ ] Provider decision made and deployed
- [ ] `/health/provider` endpoint reflects active provider
- [ ] iOS app successfully scans images with new provider
- [ ] Logs show correct provider being used
- [ ] All tests pass with both providers

**Final Integration Test:**

```bash
# 1. Test Gemini provider
wrangler.toml: AI_PROVIDER = "gemini"
npm run deploy
[Test with iOS app - verify scan works]

# 2. Test Cloudflare provider
wrangler.toml: AI_PROVIDER = "cloudflare"
npm run deploy
[Test with iOS app - verify scan works]

# 3. Test provider switching without code changes
[Change wrangler.toml AI_PROVIDER value]
npm run deploy
[Verify worker uses new provider immediately]
```

---

## Post-Implementation Tasks

### Documentation Updates

**Files to update:**
- [ ] `cloudflare-workers/README.md` - Add provider architecture section
- [ ] `CLAUDE.md` - Update backend architecture section
- [ ] `docs/features/BOOKSHELF_SCANNER.md` - Add provider switching guide

### iOS App Integration (Optional Future Enhancement)

**If adding user-configurable provider:**

```swift
// Allow users to choose provider in Settings
enum AIProvider: String, CaseIterable {
    case gemini = "gemini"
    case cloudflare = "cloudflare"

    var displayName: String {
        switch self {
        case .gemini: return "Gemini 2.5 Flash (Accurate)"
        case .cloudflare: return "Cloudflare AI (Fast)"
        }
    }
}

// Pass in API request header
headers["X-AI-Provider"] = selectedProvider.rawValue
```

**Worker modification to read header:**
```javascript
const requestedProvider = request.headers.get('X-AI-Provider') || env.AI_PROVIDER;
env.AI_PROVIDER = requestedProvider; // Override for this request
```

### Monitoring & Observability

**Add provider metrics:**
```javascript
// In each provider's scanImage()
console.log(JSON.stringify({
    event: 'ai_scan_complete',
    provider: this.getProviderName(),
    latencyMs: Date.now() - startTime,
    bookCount: result.books.length,
    suggestionCount: result.suggestions.length
}));
```

**Query in Cloudflare Analytics:**
- Track requests by provider
- Monitor latency percentiles (p50, p95, p99)
- Alert on error rate increases

### Cost Analysis

**Create monthly report script:**
```bash
# scripts/monthly-ai-costs.sh
# Query Cloudflare analytics for:
# - Gemini API requests × $0.001
# - Workers AI requests × $0.0001
# - Total scans per day/month
# - Cost per user
```

---

## Success Criteria

**This implementation is successful when:**

1. ✅ **Modularity**: Adding a new AI provider requires:
   - Create 1 new file (e.g., `openaiProvider.js`)
   - Add 1 case to factory
   - Change 1 line in `wrangler.toml`
   - Zero changes to `index.js`

2. ✅ **Performance**: Cloudflare provider is 3-5x faster than Gemini

3. ✅ **Reliability**: Both providers have >95% scan success rate

4. ✅ **Maintainability**: Code review shows clear separation of concerns

5. ✅ **Testability**: Each provider can be tested in isolation

6. ✅ **Zero Downtime**: Provider switching requires only config change + deploy

---

## Rollback Plan

**If Phase 2 fails or Cloudflare provider underperforms:**

```bash
# Instant rollback to Gemini
wrangler.toml: AI_PROVIDER = "gemini"
npm run deploy
# Takes 30 seconds, zero code changes
```

**Phase 1 gives us this safety net** - the abstraction ensures we can switch providers instantly without touching application code.

---

## Future Enhancements (Post-Phase 2)

**Potential Phase 3 ideas:**
- Multi-provider fallback (try Cloudflare, fallback to Gemini on error)
- A/B testing framework (50% Cloudflare, 50% Gemini, compare results)
- Provider-specific optimization (different prompts per model)
- Cost-based routing (use cheap provider first, fallback to accurate one)
- User-selected provider (Settings toggle in iOS app)

**Documented in:** Issue #36 (comment on future enhancements)

---

## References

- **Original Plan:** `MODULARIZATION_PLAN.md`
- **Related Issues:** #35 (modularize AI), #36 (swap-in AI worker)
- **Cloudflare Docs:** https://developers.cloudflare.com/workers-ai/
- **Gemini API Docs:** https://ai.google.dev/gemini-api/docs/vision

---

**Plan created:** 2025-10-22
**Estimated time:** Phase 1 (4-6 hours), Phase 2 (6-8 hours)
**Total tasks:** 11 tasks, 50+ steps
