import { describe, it, expect, vi } from 'vitest';
import { BooksAPIProxyWorker } from '../src/index.js';

describe('WebSocket Progress Endpoint', () => {
  it('should reject WebSocket connection without jobId', async () => {
    const env = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: (name) => ({ toString: () => name }),
        get: (id) => ({
          fetch: async (request) => {
            return new Response(null, { status: 101 });
          }
        })
      }
    };

    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/ws/progress', {
      headers: { 'Upgrade': 'websocket' }
    });

    const response = await worker.handleWebSocketUpgrade(request);

    expect(response.status).toBe(400);
    const text = await response.text();
    expect(text).toBe('Missing jobId parameter');
  });

  it('should forward WebSocket upgrade to Durable Object with valid jobId', async () => {
    let capturedRequest = null;

    const env = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: (name) => {
          expect(name).toBe('test-job-123');
          return { toString: () => name };
        },
        get: (id) => ({
          fetch: async (request) => {
            capturedRequest = request;
            return new Response('WebSocket upgrade successful', { status: 200 });
          }
        })
      }
    };

    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const request = new Request('https://api.example.com/ws/progress?jobId=test-job-123', {
      headers: { 'Upgrade': 'websocket' }
    });

    const response = await worker.handleWebSocketUpgrade(request);

    expect(response.status).toBe(200);
    expect(capturedRequest).toBeTruthy();
  });

  it('should push progress via RPC to Durable Object', async () => {
    let capturedProgress = null;

    const env = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: (name) => {
          expect(name).toBe('test-job-456');
          return { toString: () => name };
        },
        get: (id) => ({
          pushProgress: async (progressData) => {
            capturedProgress = progressData;
            return { success: true };
          }
        })
      }
    };

    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const progressData = {
      progress: 0.5,
      processedItems: 50,
      totalItems: 100,
      currentStatus: 'Processing...'
    };

    const result = await worker.pushJobProgress('test-job-456', progressData);

    expect(result.success).toBe(true);
    expect(capturedProgress).toEqual(progressData);
  });

  it('should close connection via RPC to Durable Object', async () => {
    let capturedReason = null;

    const env = {
      PROGRESS_WEBSOCKET_DO: {
        idFromName: (name) => ({ toString: () => name }),
        get: (id) => ({
          closeConnection: async (reason) => {
            capturedReason = reason;
            return { success: true };
          }
        })
      }
    };

    const ctx = {};
    const worker = new BooksAPIProxyWorker(ctx, env);

    const result = await worker.closeJobConnection('test-job-789', 'Job completed');

    expect(result.success).toBe(true);
    expect(capturedReason).toBe('Job completed');
  });
});
