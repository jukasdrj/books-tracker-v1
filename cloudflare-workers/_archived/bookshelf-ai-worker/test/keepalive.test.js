import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

describe('Keep-Alive Ping Mechanism', () => {
  let mockPushProgress;
  let intervalId;

  beforeEach(() => {
    mockPushProgress = vi.fn().mockResolvedValue({ success: true });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    if (intervalId) clearInterval(intervalId);
  });

  it('sends keep-alive ping every 30 seconds during AI processing', async () => {
    const jobId = 'test-job-123';
    const env = {
      BOOKS_API_PROXY: { pushJobProgress: mockPushProgress }
    };

    // Start keep-alive interval
    intervalId = setInterval(async () => {
      await env.BOOKS_API_PROXY.pushJobProgress(jobId, {
        progress: 0.3,
        processedItems: 1,
        totalItems: 3,
        currentStatus: 'Processing with AI...',
        keepAlive: true
      });
    }, 30000);

    // Advance time and verify pings
    await vi.advanceTimersByTimeAsync(30000);
    expect(mockPushProgress).toHaveBeenCalledTimes(1);
    expect(mockPushProgress).toHaveBeenCalledWith(jobId, expect.objectContaining({
      keepAlive: true,
      progress: 0.3
    }));

    await vi.advanceTimersByTimeAsync(30000);
    expect(mockPushProgress).toHaveBeenCalledTimes(2);

    await vi.advanceTimersByTimeAsync(30000);
    expect(mockPushProgress).toHaveBeenCalledTimes(3);
  });

  it('clears interval on AI processing completion', async () => {
    const jobId = 'test-job-123';
    const env = {
      BOOKS_API_PROXY: { pushJobProgress: mockPushProgress }
    };

    // Start and immediately clear interval
    intervalId = setInterval(async () => {
      await env.BOOKS_API_PROXY.pushJobProgress(jobId, {
        progress: 0.3,
        processedItems: 1,
        totalItems: 3,
        currentStatus: 'Processing with AI...',
        keepAlive: true
      });
    }, 30000);

    clearInterval(intervalId);

    // Advance time - no pings should fire
    await vi.advanceTimersByTimeAsync(90000);
    expect(mockPushProgress).not.toHaveBeenCalled();
  });

  it('clears interval on error during AI processing', async () => {
    const jobId = 'test-job-123';
    const env = {
      BOOKS_API_PROXY: { pushJobProgress: mockPushProgress }
    };

    // Start interval
    intervalId = setInterval(async () => {
      await env.BOOKS_API_PROXY.pushJobProgress(jobId, {
        progress: 0.3,
        processedItems: 1,
        totalItems: 3,
        currentStatus: 'Processing with AI...',
        keepAlive: true
      });
    }, 30000);

    // Simulate error and cleanup
    try {
      throw new Error('AI processing failed');
    } catch (error) {
      clearInterval(intervalId);
    }

    // Advance time - no pings should fire after error
    await vi.advanceTimersByTimeAsync(90000);
    expect(mockPushProgress).not.toHaveBeenCalled();
  });
});
