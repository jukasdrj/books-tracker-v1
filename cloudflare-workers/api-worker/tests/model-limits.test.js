import { describe, it, expect } from 'vitest';
import { getModelConfig, estimateTokens, shouldResize } from '../src/config/model-limits.js';

describe('Model Limits', () => {
  it('should return config for known models', () => {
    const llama = getModelConfig('@cf/meta/llama-3.2-11b-vision-instruct');
    expect(llama.maxImageSize).toBe(1536);
    expect(llama.quality).toBe(0.85);
    expect(llama.contextWindow).toBe(128000);
  });

  it('should return default for unknown models', () => {
    const unknown = getModelConfig('unknown-model');
    expect(unknown.maxImageSize).toBe(1024);
  });

  it('should estimate tokens correctly', () => {
    const tokens = estimateTokens(5000000); // 5MB image
    expect(tokens).toBeGreaterThan(1000000);
    expect(tokens).toBeLessThan(2000000);
  });

  it('should correctly determine when resize is needed', () => {
    // 5MB image, Llama model (128K limit)
    const decision = shouldResize(5_000_000, '@cf/meta/llama-3.2-11b-vision-instruct');
    expect(decision.needsResize).toBe(true);
    expect(decision.targetSize).toBe(1536);

    // 500KB image still exceeds 128K token limit (500/3*1000 = 166K tokens)
    const medium = shouldResize(500_000, '@cf/meta/llama-3.2-11b-vision-instruct');
    expect(medium.needsResize).toBe(true); // Still needs resize

    // 100KB image, Llama model (should fit)
    const small = shouldResize(100_000, '@cf/meta/llama-3.2-11b-vision-instruct');
    expect(small.needsResize).toBe(false); // 100/3*1000 = 33K tokens < 102K limit
  });
});
