// cloudflare-workers/api-worker/src/types/websocket-messages.ts

/**
 * Version of the WebSocket message schema.
 */
export const WEBSOCKET_SCHEMA_VERSION = "1.0.0";

/**
 * Enum for all possible message types.
 */
export enum MessageType {
  JobStarted = "job_started",
  JobProgress = "job_progress",
  JobComplete = "job_complete",
  Error = "error",
  Ping = "ping",
  Pong = "pong",
  SyncRequest = "sync_request",
  SyncResponse = "sync_response",
}

/**
 * Enum for all possible pipeline types.
 */
export enum PipelineType {
  BatchEnrichment = "batch_enrichment",
  CsvImport = "csv_import",
  AiScan = "ai_scan",
}

/**
 * Base interface for all WebSocket messages.
 */
export interface WebSocketMessage<T> {
  type: MessageType;
  jobId: string;
  pipeline: PipelineType;
  timestamp: number;
  version: string;
  payload: T;
}

// Payload interfaces for each message type

export interface JobStartedPayload {
  totalCount: number;
  estimatedDuration?: number;
  metadata?: Record<string, any>;
}

export interface JobProgressPayload {
  processedCount: number;
  currentTitle?: string;
  currentItem?: Record<string, any>;
  userMessage?: string;
}

export interface JobCompletePayload {
  successCount: number;
  failureCount: number;
  duration: number;
  results?: any;
  summary?: string;
}

export interface ErrorPayload {
  code: string;
  message: string;
  userMessage?: string;
  retryable?: boolean;
  details?: Record<string, any>;
}

export interface HeartbeatPayload {
  clientTime?: number;
}

export interface SyncResponsePayload {
  state: Record<string, any>;
}


/**
 * Factory class for creating WebSocket messages.
 */
export class WebSocketMessageFactory {
  static create<T>(
    type: MessageType,
    jobId: string,
    pipeline: PipelineType,
    payload: T
  ): WebSocketMessage<T> {
    return {
      type,
      jobId,
      pipeline,
      timestamp: Date.now(),
      version: WEBSOCKET_SCHEMA_VERSION,
      payload,
    };
  }

  static createJobStarted(
    jobId: string,
    pipeline: PipelineType,
    payload: JobStartedPayload
  ) {
    return this.create(MessageType.JobStarted, jobId, pipeline, payload);
  }

  static createJobProgress(
    jobId: string,
    pipeline: PipelineType,
    payload: JobProgressPayload
  ) {
    return this.create(MessageType.JobProgress, jobId, pipeline, payload);
  }

  static createJobComplete(
    jobId: string,
    pipeline: PipelineType,
    payload: JobCompletePayload
  ) {
    return this.create(MessageType.JobComplete, jobId, pipeline, payload);
  }

  static createError(
    jobId: string,
    pipeline: PipelineType,
    payload: ErrorPayload
  ) {
    return this.create(MessageType.Error, jobId, pipeline, payload);
  }

  static createPong(
    jobId: string,
    pipeline: PipelineType,
    payload: HeartbeatPayload
  ) {
    return this.create(MessageType.Pong, jobId, pipeline, payload);
  }
}

/**
 * Validates the structure of a WebSocket message.
 * @param message The message to validate.
 * @returns True if the message is valid, false otherwise.
 */
export function validateMessage(message: any): message is WebSocketMessage<any> {
    return (
        message &&
        typeof message === 'object' &&
        'type' in message &&
        'jobId' in message &&
        'pipeline' in message &&
        'timestamp' in message &&
        'version' in message &&
        'payload' in message
    );
}

/**
 * Type guard to check if a message is of a specific type.
 * @param message The message to check.
 * @param type The message type to check for.
 * @returns True if the message is of the specified type, false otherwise.
 */
export function isWebSocketMessage<T>(message: any, type: MessageType): message is WebSocketMessage<T> {
    return validateMessage(message) && message.type === type;
}
