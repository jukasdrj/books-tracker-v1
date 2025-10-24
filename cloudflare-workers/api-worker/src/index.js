import { ProgressWebSocketDO } from './durable-objects/progress-socket.js';

// Export the Durable Object class for Cloudflare Workers runtime
export { ProgressWebSocketDO };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Route WebSocket connections to the Durable Object
    if (url.pathname === '/ws/progress') {
      const jobId = url.searchParams.get('jobId');
      if (!jobId) {
        return new Response('Missing jobId parameter', { status: 400 });
      }

      // Get Durable Object instance for this specific jobId
      const doId = env.PROGRESS_WEBSOCKET_DO.idFromName(jobId);
      const doStub = env.PROGRESS_WEBSOCKET_DO.get(doId);

      // Forward the request to the Durable Object
      return doStub.fetch(request);
    }

    // Health check endpoint
    return new Response(JSON.stringify({
      status: 'ok',
      worker: 'api-worker',
      version: '1.0.0',
      endpoints: [
        '/ws/progress?jobId={id}'
      ]
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
