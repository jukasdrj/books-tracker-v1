import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
  },
  resolve: {
    alias: {
      'cloudflare:workers': new URL('./test/mocks/cloudflare-workers.js', import.meta.url).pathname,
    },
  },
});
