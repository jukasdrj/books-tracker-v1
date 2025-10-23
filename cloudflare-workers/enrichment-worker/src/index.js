import {
  StructuredLogger,
  PerformanceTimer
} from '../../structured-logging-infrastructure.js';

/**
 * Enrichment Worker - Handles batch book enrichment with callback-based progress
 */
export class EnrichmentWorker {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    // Initialize structured logging (Phase B)
    this.logger = new StructuredLogger('enrichment-worker', env);
  }

  /**
   * RPC Method: Enrich batch of works with progress callback
   * @param {string} jobId - Job identifier for tracking
   * @param {string[]} workIds - Array of work IDs to enrich
   * @param {Function} progressCallback - Callback for progress updates (optional)
   * @param {Object} options - Optional enrichment configuration
   * @returns {Promise<Object>} Enrichment result
   */
  async enrichBatch(jobId, workIds, progressCallback = null, options = {}) {
    const timer = new PerformanceTimer(this.logger, 'enrichBatch');
    const totalCount = workIds.length;
    let processedCount = 0;
    const enrichedWorks = [];

    try {
      for (const workId of workIds) {
        // Enrich single work using EXTERNAL_APIS_WORKER
        const result = await this.enrichWorkWithAPIs(workId);
        enrichedWorks.push(result);

        processedCount++;
        const progress = processedCount / totalCount;

        // Call progress callback if provided (caller handles WebSocket)
        if (progressCallback) {
          await progressCallback({
            progress: progress,
            processedItems: processedCount,
            totalItems: totalCount,
            currentStatus: `Enriching work ${workId}`,
            currentWorkId: workId
          });
        }

        // Yield to avoid blocking
        await new Promise(resolve => setTimeout(resolve, 0));
      }

      await timer.end({ jobId, totalCount, processedCount });

      return {
        success: true,
        processedCount: processedCount,
        totalCount: totalCount,
        enrichedWorks: enrichedWorks
      };

    } catch (error) {
      this.logger.logError('enrichBatch_error', error, { jobId, processedCount, totalCount });

      // Call error callback if provided
      if (progressCallback) {
        await progressCallback({
          progress: processedCount / totalCount,
          error: error.message,
          currentStatus: 'Enrichment failed'
        });
      }

      throw error;
    }
  }

  /**
   * Internal: Enrich single work using EXTERNAL_APIS_WORKER
   * @param {string} workId - Work identifier (typically ISBN or title+author)
   * @returns {Promise<Object>} Enrichment result with metadata
   */
  async enrichWorkWithAPIs(workId) {
    const timer = new PerformanceTimer(this.logger, 'enrichWorkWithAPIs');

    try {
      // Determine if workId is ISBN or title search
      const isISBN = /^(97[89])?\d{9}[\dX]$/i.test(workId);

      let enrichmentData;
      if (isISBN) {
        // Use ISBN search endpoint
        enrichmentData = await this.env.EXTERNAL_APIS_WORKER.searchByISBN(workId, {
          maxResults: 1,
          includeMetadata: true
        });
      } else {
        // Use general search endpoint
        enrichmentData = await this.env.EXTERNAL_APIS_WORKER.searchBooks(workId, {
          maxResults: 5,
          includeMetadata: true
        });
      }

      await timer.end({ workId, isISBN, found: !!enrichmentData });

      return {
        workId,
        enriched: true,
        data: enrichmentData,
        timestamp: new Date().toISOString()
      };

    } catch (error) {
      this.logger.logError('enrichWorkWithAPIs_error', error, { workId });

      return {
        workId,
        enriched: false,
        error: error.message,
        timestamp: new Date().toISOString()
      };
    }
  }

  /**
   * HTTP fetch handler
   */
  async fetch(request) {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/enrich-batch') {
      const { jobId, workIds, options } = await request.json();

      // Note: HTTP endpoint doesn't support progress callback
      // For real-time progress, use RPC method with callback
      const result = await this.enrichBatch(jobId, workIds, null, options);

      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    return new Response('Enrichment Worker', { status: 200 });
  }
}

export default EnrichmentWorker;
