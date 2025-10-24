import { StructuredLogger, PerformanceTimer } from '../../structured-logging-infrastructure.js';

/**
 * EnrichmentCoordinator - Manages batch enrichment with WebSocket progress
 * Orchestrates enrichment-worker and progress-websocket-durable-object
 */
export class EnrichmentCoordinator {
  constructor(env, logger) {
    this.env = env;
    this.logger = logger || new StructuredLogger('enrichment-coordinator', env);
  }

  /**
   * Start batch enrichment with real-time WebSocket progress
   * @param {string} jobId - Job identifier for WebSocket tracking
   * @param {string[]} workIds - Array of work IDs to enrich
   * @param {Object} options - Enrichment options
   * @returns {Promise<Object>} Enrichment result
   */
  async startEnrichment(jobId, workIds, options = {}) {
    const timer = new PerformanceTimer(this.logger, 'startEnrichment');

    try {
      // Get Durable Object stub for WebSocket communication
      const doId = this.env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
      const doStub = this.env.PROGRESS_WEBSOCKET_DO.get(doId);

      // Define progress callback that pushes to WebSocket
      const progressCallback = async (progressData) => {
        try {
          await doStub.pushProgress(progressData);
        } catch (error) {
          this.logger.logError('pushProgress_error', error, { jobId, progressData });
        }
      };

      // Call enrichment-worker with progress callback
      const result = await this.env.ENRICHMENT_WORKER.enrichBatch(
        jobId,
        workIds,
        progressCallback,
        options
      );

      // Close WebSocket on completion
      await doStub.pushProgress({
        progress: 1.0,
        processedItems: result.processedCount,
        totalItems: result.totalCount,
        currentStatus: 'Enrichment completed',
        completed: true
      });

      await timer.end({ jobId, processedCount: result.processedCount });

      return result;

    } catch (error) {
      this.logger.logError('startEnrichment_error', error, { jobId, workIdsCount: workIds.length });

      // Push error to WebSocket
      try {
        const doId = this.env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
        const doStub = this.env.PROGRESS_WEBSOCKET_DO.get(doId);
        await doStub.pushProgress({
          error: error.message,
          currentStatus: 'Enrichment failed',
          completed: true
        });
      } catch (wsError) {
        this.logger.logError('pushError_failed', wsError, { jobId });
      }

      throw error;
    }
  }
}
