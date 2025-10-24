export default {
  async fetch(request, env, ctx) {
    return new Response(JSON.stringify({
      status: 'ok',
      worker: 'api-worker',
      version: '1.0.0'
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
};
