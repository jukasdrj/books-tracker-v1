import { DurableObject } from 'cloudflare:workers';

/**
 * Durable Object for managing WebSocket connections per job
 * One instance per jobId - stores WebSocket connection and forwards progress messages
 *
 * Migrated from progress-websocket-durable-object/src/index.js
 */
export class ProgressWebSocketDO extends DurableObject {
  constructor(state, env) {
    super(state, env);
    this.webSocket = null;
    this.jobId = null;
  }

  /**
   * Handle WebSocket upgrade request from iOS client
   */
  async fetch(request) {
    const url = new URL(request.url);
    const upgradeHeader = request.headers.get('Upgrade');

    console.log('[ProgressDO] Incoming request', {
      url: url.toString(),
      upgradeHeader,
      method: request.method
    });

    // Validate WebSocket upgrade
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
      console.warn('[ProgressDO] Invalid upgrade header', { upgradeHeader });
      return new Response('Expected Upgrade: websocket', {
        status: 426,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'text/plain'
        }
      });
    }

    // Extract jobId from query params
    const jobId = url.searchParams.get('jobId');
    if (!jobId) {
      console.error('[ProgressDO] Missing jobId parameter');
      return new Response('Missing jobId parameter', { status: 400 });
    }

    console.log(`[ProgressDO] Creating WebSocket for job ${jobId}`);

    // Create WebSocket pair
    const [client, server] = Object.values(new WebSocketPair());

    // Store server-side WebSocket
    this.webSocket = server;
    this.jobId = jobId;

    // Accept connection
    this.webSocket.accept();

    console.log(`[${this.jobId}] WebSocket connection accepted`);

    // Setup event handlers
    this.webSocket.addEventListener('message', (event) => {
      console.log(`[${this.jobId}] Received message:`, event.data);
    });

    this.webSocket.addEventListener('close', (event) => {
      console.log(`[${this.jobId}] WebSocket closed:`, event.code, event.reason);
      this.cleanup();
    });

    this.webSocket.addEventListener('error', (event) => {
      console.error(`[${this.jobId}] WebSocket error:`, event);
      this.cleanup();
    });

    // Return client-side WebSocket to iOS app
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: {
        'Access-Control-Allow-Origin': '*'
      }
    });
  }

  /**
   * RPC Method: Push progress update to connected client
   * Called by background workers (enrichment, CSV import, etc.)
   */
  async pushProgress(progressData) {
    console.log(`[ProgressDO] pushProgress called for job ${this.jobId}`, {
      hasWebSocket: !!this.webSocket,
      progressData
    });

    if (!this.webSocket) {
      const error = new Error('No WebSocket connection available');
      console.error(`[${this.jobId}] No WebSocket connection`, { error });
      throw error;
    }

    const message = JSON.stringify({
      type: 'progress',
      jobId: this.jobId,
      timestamp: Date.now(),
      data: progressData
    });

    try {
      this.webSocket.send(message);
      console.log(`[${this.jobId}] Progress sent successfully`, { messageLength: message.length });
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send message:`, error);
      throw error;
    }
  }

  /**
   * RPC Method: Close WebSocket connection
   */
  async closeConnection(reason = 'Job completed') {
    if (this.webSocket) {
      this.webSocket.close(1000, reason);
      this.cleanup();
    }
    return { success: true };
  }

  /**
   * Internal cleanup
   */
  cleanup() {
    this.webSocket = null;
    this.jobId = null;
  }
}
