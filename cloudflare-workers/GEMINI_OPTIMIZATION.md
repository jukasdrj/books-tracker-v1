# Gemini-Only Optimization (October 24, 2025)

## Summary

Simplified BooksTrack bookshelf AI scanner to use **Gemini 2.0 Flash exclusively** after discovering Cloudflare Workers AI models couldn't handle typical bookshelf images due to small context windows.

## Problem

Cloudflare Workers AI vision models have limited context windows compared to Gemini:
- **Gemini 2.0 Flash:** 2M tokens ✅ Works with 4-5MB images
- **Llama 3.2 11B Vision:** 128K tokens ❌ Fails
- **LLaVA 1.5:** 4K tokens ❌ Fails  
- **UForm Gen2 Qwen:** 8K tokens ❌ Fails

Typical bookshelf images from iOS (~4-5MB, 1920px @ 90% quality) exceeded these limits:
```
Error: 5021: The estimated number of input and maximum output tokens (1457775) 
exceeded this model context window limit (128000).
```

## Solution: Gemini-Only

Removed all Cloudflare AI provider code and infrastructure, keeping only proven-working Gemini integration.

### Changes Made

**Backend (cloudflare-workers/api-worker):**
- ✅ Removed `src/providers/cloudflare-provider.js`
- ✅ Removed `src/utils/image-resizer.js` (WASM attempts)
- ✅ Removed `src/config/model-limits.js`
- ✅ Simplified `src/services/ai-scanner.js` to Gemini-only
- ✅ Removed provider parameter routing logic

**iOS (BooksTrackerPackage):**
- ✅ Simplified `Common/AIProvider.swift` enum to single case: `.geminiFlash`
- ✅ Removed `Common/AIProviderSettings.swift` entirely
- ✅ Removed provider picker UI from SettingsView
- ✅ Removed provider query parameter from BookshelfAIService

**Result:**
- Bundle size reduced **64%** (233KB → 83KB)
- Simpler codebase, less to maintain
- Single proven AI provider
- No context window issues

## Performance

**Gemini 2.0 Flash:**
- Processing time: 25-40s (includes AI inference + enrichment)
- Image size: Handles 4-5MB images natively (no resizing needed)
- Accuracy: High (0.7-0.95 confidence scores)
- Context window: 2M tokens (no limits)

## Future Work

For experimenting with other AI providers, see **[GitHub Issue #134](https://github.com/jukasdrj/books-tracker-v1/issues/134)** which documents three approaches for implementing image resizing:

1. **Manual WASM (@jsquash)** - High quality, complex setup, 330-550ms latency
2. **R2 + Cloudflare Image Resizing** - Simple, external dependency, 610-1210ms latency  
3. **wasm-image-optimization** - Fast, lower quality, 200-400ms latency

All research preserved for future reference, but not worth complexity for current use case.

## Deployment

Deployed: October 24, 2025 @ 7:23 PM  
Worker Version: `aee02634-7d4b-4de4-ba07-92d9dfad2c57`  
Bundle: 82.95 KiB (17.67 KiB gzipped)  

**Ready to test from iOS!** 🎉
