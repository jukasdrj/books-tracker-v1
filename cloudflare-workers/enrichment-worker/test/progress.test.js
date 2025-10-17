import { describe, it, expect } from 'vitest';
import { EnrichmentWorker } from '../src/index.js';

describe('Enrichment Progress WebSocket', () => {
  it('should push progress updates during batch enrichment', async () => {
    const mockProgressUpdates = [];

    const env = {
      BOOKS_API_PROXY: {
        pushJobProgress: async (jobId, data) => {
          mockProgressUpdates.push({ jobId, data });
          return { success: true };
        },
        closeJobConnection: async (jobId, reason) => {
          return { success: true };
        }
      }
    };

    const ctx = {};
    const worker = new EnrichmentWorker(ctx, env);

    const result = await worker.enrichBatch('enrich-job-123', ['work-1', 'work-2', 'work-3']);

    // Verify progress updates were sent
    expect(mockProgressUpdates.length).toBeGreaterThan(0);
    expect(mockProgressUpdates[0].jobId).toBe('enrich-job-123');
    expect(mockProgressUpdates[0].data).toHaveProperty('progress');
    expect(mockProgressUpdates[0].data).toHaveProperty('processedItems');
    expect(mockProgressUpdates[0].data).toHaveProperty('totalItems');

    // Verify final result
    expect(result.success).toBe(true);
    expect(result.processedCount).toBe(3);
    expect(result.totalCount).toBe(3);
  });

  it('should handle enrichment errors and push error status', async () => {
    let errorStatusSent = false;

    const env = {
      BOOKS_API_PROXY: {
        pushJobProgress: async (jobId, data) => {
          if (data.error) {
            errorStatusSent = true;
          }
          return { success: true };
        },
        closeJobConnection: async () => ({ success: true })
      }
    };

    const ctx = {};
    const worker = new EnrichmentWorker(ctx, env);

    // Override enrichWork to throw error
    worker.enrichWork = async () => {
      throw new Error('Enrichment failed');
    };

    try {
      await worker.enrichBatch('error-job', ['work-1']);
    } catch (error) {
      expect(error.message).toBe('Enrichment failed');
      expect(errorStatusSent).toBe(true);
    }
  });
});
