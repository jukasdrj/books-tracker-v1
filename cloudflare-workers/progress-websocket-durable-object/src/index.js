/**
 * Durable Object for managing WebSocket connections per job
 * One instance per jobId - stores WebSocket connection and forwards progress messages
 */
export class ProgressWebSocketDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.webSocket = null;
    this.jobId = null;
  }

  /**
   * Handle WebSocket upgrade request from iOS client
   */
  async fetch(request) {
    const url = new URL(request.url);
    const upgradeHeader = request.headers.get('Upgrade');

    // Validate WebSocket upgrade
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
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
      return new Response('Missing jobId parameter', { status: 400 });
    }

    // Create WebSocket pair
    const [client, server] = Object.values(new WebSocketPair());

    // Store server-side WebSocket
    this.webSocket = server;
    this.jobId = jobId;

    // Accept connection
    this.webSocket.accept();

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
    if (!this.webSocket) {
      throw new Error('No WebSocket connection available');
    }

    const message = JSON.stringify({
      type: 'progress',
      jobId: this.jobId,
      timestamp: Date.now(),
      data: progressData
    });

    try {
      this.webSocket.send(message);
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

export default {
  async fetch(request, env) {
    return new Response('Progress WebSocket Durable Object', { status: 200 });
  }
};
