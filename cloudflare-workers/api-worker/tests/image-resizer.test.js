import { describe, it, expect } from 'vitest';

describe('Image Resizer', () => {
  // Note: These tests verify the module structure and API surface.
  // Full end-to-end testing requires Cloudflare Workers runtime (OffscreenCanvas).
  // Integration tests will be run via wrangler dev environment.

  it('should export resizeImage function', async () => {
    const { resizeImage } = await import('../src/utils/image-resizer.js');
    expect(typeof resizeImage).toBe('function');
  });

  it('should export getImageDimensions function', async () => {
    const { getImageDimensions } = await import('../src/utils/image-resizer.js');
    expect(typeof getImageDimensions).toBe('function');
  });

  // Integration tests to be run with `wrangler dev` or in deployed environment
  it.todo('should resize image to max dimension preserving aspect ratio (e2e)');
  it.todo('should not upscale smaller images (e2e)');
  it.todo('should calculate correct dimensions for different aspect ratios (e2e)');
});
