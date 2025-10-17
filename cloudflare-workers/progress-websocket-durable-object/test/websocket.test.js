import { describe, it, expect } from 'vitest';
import { ProgressWebSocketDO } from '../src/index.js';

describe('ProgressWebSocketDO', () => {
  it('should reject non-WebSocket requests', async () => {
    const state = {
      id: { toString: () => 'test-id' },
      storage: new Map()
    };
    const env = {};
    const durableObject = new ProgressWebSocketDO(state, env);

    const request = new Request('https://test.com/ws/progress?jobId=test-job-123');
    const response = await durableObject.fetch(request);

    expect(response.status).toBe(426);
    const text = await response.text();
    expect(text).toBe('Expected Upgrade: websocket');
  });

  it('should reject requests without jobId', async () => {
    const state = {
      id: { toString: () => 'test-id' },
      storage: new Map()
    };
    const env = {};
    const durableObject = new ProgressWebSocketDO(state, env);

    const request = new Request('https://test.com/ws/progress', {
      headers: { 'Upgrade': 'websocket' }
    });
    const response = await durableObject.fetch(request);

    expect(response.status).toBe(400);
    const text = await response.text();
    expect(text).toBe('Missing jobId parameter');
  });

  it('should throw error when pushing progress without connection', async () => {
    const state = {
      id: { toString: () => 'test-id' },
      storage: new Map()
    };
    const env = {};
    const durableObject = new ProgressWebSocketDO(state, env);

    await expect(async () => {
      await durableObject.pushProgress({ progress: 0.5 });
    }).rejects.toThrow('No WebSocket connection available');
  });
});
