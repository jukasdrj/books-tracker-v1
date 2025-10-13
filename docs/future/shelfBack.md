# Bookshelf AI Scanner: Backend Implementation Plan

**Version:** 1.0
**Date:** October 12, 2025
**Status:** Planning

This document outlines the three-phased plan for building the backend infrastructure for the Bookshelf AI Scanning feature on Cloudflare Workers.

---

### **Phase 1: Foundational AI Service & API**

**Goal:** Establish a robust, standalone AI worker that can accurately process bookshelf images and return structured data. This phase focuses on core functionality and creating a flexible architecture for future model swapping.

#### **1.1. AI Model Abstraction Layer:**
- **Task:** Create a module that abstracts the AI model provider. This will allow for easy swapping between Gemini, Cloudflare's open-source models, or others in the future.
- **Implementation:**
    - Create `src/ai-providers/gemini-provider.js` to encapsulate all Gemini-specific logic (API endpoint, request formatting, response parsing).
    - Create `src/ai-providers/cloudflare-provider.js` as a placeholder for Cloudflare's AI models.
    - Create a factory function `getAIProvider(providerName)` that returns the appropriate provider module. The `providerName` will be set via a `wrangler.toml` environment variable.

#### **1.2. Enhance Gemini Prompt and Schema:**
- **Task:** Implement the enhanced prompt and JSON schema discussed in our review to include confidence scores, ISBN, publisher, and image metadata.
- **Implementation:**
    - Update the `system_prompt` in `bookshelf-ai-worker/src/index.js` to the enhanced version.
    - Update the `schema` object to include `confidence`, `isbn`, `publisher`, `publicationYear`, and the `metadata` object with image quality assessment fields.

#### **1.3. Implement Post-Processing Pipeline:**
- **Task:** Create a series of post-processing steps to clean and validate the AI's output.
- **Implementation:**
    - **Quality Gate:** Reject scans based on the `metadata.imageQuality` field from the AI.
    - **Deduplication:** Implement `deduplicateByBoundingBox` to merge overlapping detections.
    - **Normalization:** Implement `normalizeTitle` and `normalizeAuthor` to clean up common OCR errors.

#### **1.4. Verification & Testing:**
- **Unit Tests:**
    - Test the AI model abstraction layer can switch between providers.
    - Test the post-processing pipeline with mock AI data.
    - Test normalization functions with various OCR error patterns.
- **Integration Tests:**
    - Send 20+ diverse bookshelf images (varying quality, lighting, and angles) to the `/scan` endpoint.
    - **Verification:**
        - Verify responses include the full enhanced schema (confidence scores, etc.).
        - Manually check 5-10 scans to ensure bounding boxes and extracted text are accurate.
        - Verify that poor quality images are rejected with a meaningful error message.

---

### **Phase 2: Hybrid Architecture Integration & Enrichment**

**Goal:** Implement the recommended hybrid architecture where the iOS app communicates directly with the AI worker, and then progressively enriches the results via the `books-api-proxy`.

#### **2.1. Refine API for Hybrid Flow:**
- **Task:** No new endpoints are needed, but ensure the existing `/scan` endpoint on `bookshelf-ai-worker` is robust and documented for direct client access.
- **Implementation:**
    - Add detailed comments to `bookshelf-ai-worker/src/index.js` clarifying its role in the hybrid architecture.
    - Ensure CORS is correctly configured to allow requests from the iOS app.

#### **2.2. Enhance `books-api-proxy` for Enrichment:**
- **Task:** Ensure the `/search/advanced` endpoint is optimized for enriching the high-confidence detections from the AI worker.
- **Implementation:**
    - Review the `handleAdvancedSearch` function in `books-api-proxy/src/search-contexts.js` to ensure it efficiently handles title and author queries.
    - Add logging to track enrichment-specific requests.

#### **2.3. Verification & Testing:**
- **Integration Tests:**
    - Simulate the iOS app's behavior by first calling the `/scan` endpoint on the `bookshelf-ai-worker`.
    - For each high-confidence result, call the `/search/advanced` endpoint on the `books-api-proxy`.
    - **Verification:**
        - Verify that the `/scan` endpoint responds within the 25-40s target.
        - Verify that the `/search/advanced` endpoint returns accurate metadata for the detected books.
        - Test the full flow with at least 10 different book titles and authors from a test scan.

---

### **Phase 3: Optimization, Scalability & Model Evaluation**

**Goal:** Optimize for performance, add scalability features like rate limiting, and evaluate alternative AI models.

#### **3.1. Implement Caching and Rate Limiting:**
- **Task:** Add a caching layer to the `bookshelf-ai-worker` and implement rate limiting to prevent abuse.
- **Implementation:**
    - **Caching:** Use Cloudflare KV to cache AI responses based on the hash of the uploaded image. Set a TTL of 1 hour.
    - **Rate Limiting:** Implement a simple rate limiter using Cloudflare's firewall rules or a KV-based solution to limit requests per user/IP.

#### **3.2. Evaluate Alternative AI Models:**
- **Task:** Test Cloudflare's open-source models as an alternative to Gemini.
- **Implementation:**
    - Implement the `cloudflare-provider.js` module, which will call one of Cloudflare's vision models.
    - Create a test endpoint (e.g., `/scan-cf`) to compare the results directly with the Gemini endpoint.
    - Run the same set of 20+ test images through both providers and compare accuracy, speed, and structure of the results.

#### **3.3. User Feedback Loop:**
- **Task:** Create an endpoint to receive feedback from users on the accuracy of detections.
- **Implementation:**
    - Create a `/feedback` endpoint on the `books-api-proxy` that accepts a `detectionId` and a `correct` flag.
    - Store this feedback in a new R2 bucket for later analysis. This data will be invaluable for fine-tuning prompts or models.

#### **3.4. Verification & Testing:**
- **Performance Tests:**
    - Send the same image twice to the `/scan` endpoint and verify the second request is a cache hit (sub-second response).
    - Send multiple requests in quick succession to verify rate limiting is working.
- **A/B Testing:**
    - Run a batch of 50 images through both the Gemini and Cloudflare model endpoints.
    - **Verification:** Compare the `readableCount` and average `confidence.overall` scores between the two models to determine which performs better for this specific task.
- **Functional Tests:**
    - Send feedback to the `/feedback` endpoint and verify the data is correctly stored in R2.

---

### **Success Metrics**

* **Detection Accuracy:** >90% of visible book spines are correctly identified with a bounding box.
* **OCR Accuracy:** >80% of high-confidence detections have the correct title and author.
* **Processing Time:** Average end-to-end processing time (from image upload to AI response) is under 35 seconds.
* **Model Flexibility:** The backend can be switched from Gemini to a Cloudflare model with a single environment variable change, with no code deployment needed.
* **Scalability:** The system can handle 100 concurrent scan requests without significant performance degradation.