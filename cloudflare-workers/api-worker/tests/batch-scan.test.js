/**
 * Batch Scan Endpoint Tests
 *
 * Tests the batch bookshelf scanning endpoint that accepts multiple photos
 * and processes them sequentially with WebSocket progress updates.
 *
 * Run with: npm test -- batch-scan.test.js
 *
 * Note: These tests require the worker to be running locally:
 * npm run dev (in another terminal)
 */

import { describe, it, expect, beforeAll } from 'vitest';

describe('Batch Scan Endpoint', () => {
  const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:8787';

  // Test connection to local dev server
  beforeAll(async () => {
    try {
      const response = await fetch(`${BASE_URL}/health`);
      if (!response.ok) {
        throw new Error('Worker not running. Start with: npm run dev');
      }
    } catch (error) {
      console.error('Failed to connect to worker:', error.message);
      throw new Error('Worker must be running on http://localhost:8787. Start with: npm run dev');
    }
  });

  it('accepts batch scan request with multiple images', async () => {
    const jobId = crypto.randomUUID();
    const request = {
      jobId,
      images: [
        { index: 0, data: 'base64image1...' },
        { index: 1, data: 'base64image2...' }
      ]
    };

    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request)
    });

    expect(response.status).toBe(202); // Accepted
    const body = await response.json();
    expect(body.jobId).toBe(jobId);
    expect(body.totalPhotos).toBe(2);
    expect(body.status).toBe('processing');
  });

  it('rejects batches exceeding 5 photos', async () => {
    const jobId = crypto.randomUUID();
    const images = Array.from({ length: 6 }, (_, i) => ({
      index: i,
      data: 'base64image...'
    }));

    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId, images })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('maximum 5 photos');
  });

  it('rejects request without jobId', async () => {
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        images: [{ index: 0, data: 'base64image...' }]
      })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('jobId');
  });

  it('rejects request without images array', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('images array required');
  });

  it('rejects empty images array', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ jobId, images: [] })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('At least one image required');
  });

  it('validates image structure (index and data fields)', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        images: [{ index: 0 }] // Missing data field
      })
    });

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toContain('index and data fields');
  });

  it('includes CORS headers', async () => {
    const jobId = crypto.randomUUID();
    const response = await fetch(`${BASE_URL}/api/scan-bookshelf/batch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jobId,
        images: [{ index: 0, data: 'base64image...' }]
      })
    });

    expect(response.headers.get('access-control-allow-origin')).toBe('*');
  });
});
