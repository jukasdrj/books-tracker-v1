import { describe, it, expect } from 'vitest';
import { BooksAPIProxyWorker } from '../src/index.js';

describe('Enrichment API', () => {
  it('should start enrichment job and return immediately', async () => {
    let enrichmentCalled = false;
    const capturedArgs = {};

    const env = {
      ENRICHMENT_WORKER: {
        enrichBatch: async (jobId, workIds) => {
          enrichmentCalled = true;
          capturedArgs.jobId = jobId;
          capturedArgs.workIds = workIds;
          return { success: true, processedCount: 0, totalCount: workIds.length };
        }
      }
    };

    const ctx = {
      waitUntil: (promise) => {
        // Store the promise for verification
        ctx.enrichmentPromise = promise;
      }
    };

    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId: 'enrich-job-789',
        workIds: ['work-1', 'work-2', 'work-3']
      })
    });

    const response = await worker.handleEnrichmentStart(request);
    const result = await response.json();

    expect(response.status).toBe(200);
    expect(result.success).toBe(true);
    expect(result.jobId).toBe('enrich-job-789');
    expect(result.totalCount).toBe(3);
    expect(result.status).toBe('started');
    expect(result.message).toContain('/ws/progress?jobId=');

    // Verify enrichment was triggered in background
    expect(ctx.enrichmentPromise).toBeTruthy();
  });

  it('should reject request without jobId', async () => {
    const env = {};
    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workIds: ['work-1', 'work-2']
      })
    });

    const response = await worker.handleEnrichmentStart(request);
    const result = await response.json();

    expect(response.status).toBe(400);
    expect(result.error).toBe('Missing required fields: jobId, workIds');
  });

  it('should reject request without workIds', async () => {
    const env = {};
    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId: 'test-job'
      })
    });

    const response = await worker.handleEnrichmentStart(request);
    const result = await response.json();

    expect(response.status).toBe(400);
    expect(result.error).toBe('Missing required fields: jobId, workIds');
  });

  it('should handle invalid workIds (not array)', async () => {
    const env = {};
    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/api/enrichment/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId: 'test-job',
        workIds: 'not-an-array'
      })
    });

    const response = await worker.handleEnrichmentStart(request);
    const result = await response.json();

    expect(response.status).toBe(400);
    expect(result.error).toBe('Missing required fields: jobId, workIds');
  });
});
