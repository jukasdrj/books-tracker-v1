// test/gemini-structured-output.test.js
import { describe, test, expect, vi } from 'vitest';
import { scanImageWithGemini } from '../src/providers/gemini-provider.js';
import { parseCSVWithGemini } from '../src/providers/gemini-csv-provider.js';

describe('Gemini Structured Output - Bookshelf Scanner', () => {
  test('includes responseSchema in API call', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                author: 'Test Author',
                format: 'hardcover',
                confidence: 0.95,
                boundingBox: { x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4 }
              }])
            }]
          }
        }],
        usageMetadata: {
          promptTokenCount: 100,
          candidatesTokenCount: 50,
          totalTokenCount: 150
        }
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    expect(mockFetch).toHaveBeenCalled();
    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify responseSchema is included
    expect(requestBody.generationConfig.responseSchema).toBeDefined();
    expect(requestBody.generationConfig.responseSchema.type).toBe('ARRAY');
    expect(requestBody.generationConfig.responseSchema.items.type).toBe('OBJECT');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('title');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('confidence');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('boundingBox');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('format');
  });

  test('schema enforces format enum values', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                format: 'hardcover',
                confidence: 0.9,
                boundingBox: { x1: 0, y1: 0, x2: 1, y2: 1 }
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify format field has enum constraint
    const formatProperty = requestBody.generationConfig.responseSchema.items.properties.format;
    expect(formatProperty.enum).toEqual(['hardcover', 'paperback', 'mass-market', 'unknown']);
  });

  test('schema enforces confidence range (0-1)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                format: 'paperback',
                confidence: 0.85,
                boundingBox: { x1: 0, y1: 0, x2: 1, y2: 1 }
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify confidence has min/max constraints
    const confidenceProperty = requestBody.generationConfig.responseSchema.items.properties.confidence;
    expect(confidenceProperty.minimum).toBe(0);
    expect(confidenceProperty.maximum).toBe(1);
  });

  test('schema enforces boundingBox coordinate ranges (0-1)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                format: 'unknown',
                confidence: 0.5,
                boundingBox: { x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75 }
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    await scanImageWithGemini(imageData, env);

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify boundingBox coordinates have min/max constraints
    const boundingBoxProps = requestBody.generationConfig.responseSchema.items.properties.boundingBox.properties;
    expect(boundingBoxProps.x1.minimum).toBe(0);
    expect(boundingBoxProps.x1.maximum).toBe(1);
    expect(boundingBoxProps.y1.minimum).toBe(0);
    expect(boundingBoxProps.y1.maximum).toBe(1);
    expect(boundingBoxProps.x2.minimum).toBe(0);
    expect(boundingBoxProps.x2.maximum).toBe(1);
    expect(boundingBoxProps.y2.minimum).toBe(0);
    expect(boundingBoxProps.y2.maximum).toBe(1);
  });

  test('does not manually clamp confidence values (schema-enforced)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                format: 'paperback',
                confidence: 0.95,  // Valid value from schema
                boundingBox: { x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4 }
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    const result = await scanImageWithGemini(imageData, env);

    // Confidence should pass through directly (no Math.max/Math.min clamping)
    expect(result.books[0].confidence).toBe(0.95);
  });

  test('does not manually validate boundingBox coordinates (schema-enforced)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Test Book',
                format: 'hardcover',
                confidence: 0.88,
                boundingBox: { x1: 0.15, y1: 0.25, x2: 0.85, y2: 0.75 }
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const imageData = new ArrayBuffer(8);
    const env = { GEMINI_API_KEY: 'test-key' };

    const result = await scanImageWithGemini(imageData, env);

    // BoundingBox should pass through directly (no validation loop)
    expect(result.books[0].boundingBox).toEqual({
      x1: 0.15,
      y1: 0.25,
      x2: 0.85,
      y2: 0.75
    });
  });
});

describe('Gemini Structured Output - CSV Parser', () => {
  test('includes responseSchema in API call', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Book1',
                author: 'Author1'
              }])
            }]
          }
        }],
        usageMetadata: {
          promptTokenCount: 50,
          candidatesTokenCount: 25,
          totalTokenCount: 75
        }
      })
    }));

    global.fetch = mockFetch;

    const csvText = 'Title,Author\nBook1,Author1';
    const prompt = 'Parse this CSV';
    const apiKey = 'test-key';

    await parseCSVWithGemini(csvText, prompt, apiKey);

    expect(mockFetch).toHaveBeenCalled();
    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify responseSchema is included
    expect(requestBody.generationConfig.responseSchema).toBeDefined();
    expect(requestBody.generationConfig.responseSchema.type).toBe('ARRAY');
    expect(requestBody.generationConfig.responseSchema.items.type).toBe('OBJECT');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('title');
    expect(requestBody.generationConfig.responseSchema.items.required).toContain('author');
  });

  test('schema guarantees title and author are required', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Required Title',
                author: 'Required Author'
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const csvText = 'Title,Author\nBook1,Author1';
    const prompt = 'Parse this CSV';
    const apiKey = 'test-key';

    await parseCSVWithGemini(csvText, prompt, apiKey);

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify title and author are in required array
    expect(requestBody.generationConfig.responseSchema.items.required).toEqual(['title', 'author']);
  });

  test('schema defines optional fields as nullable', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Book Title',
                author: 'Book Author',
                isbn: null,
                publisher: null
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    await parseCSVWithGemini('csv', 'prompt', 'key');

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify optional fields are nullable
    const properties = requestBody.generationConfig.responseSchema.items.properties;
    expect(properties.isbn.nullable).toBe(true);
    expect(properties.publisher.nullable).toBe(true);
    expect(properties.pageCount.nullable).toBe(true);
  });

  test('schema enforces rating range (0-5)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([{
                title: 'Great Book',
                author: 'Famous Author',
                rating: 4.5
              }])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    await parseCSVWithGemini('csv', 'prompt', 'key');

    const callArgs = mockFetch.mock.calls[0];
    const requestBody = JSON.parse(callArgs[1].body);

    // Verify rating has min/max constraints
    const ratingProperty = requestBody.generationConfig.responseSchema.items.properties.rating;
    expect(ratingProperty.minimum).toBe(0);
    expect(ratingProperty.maximum).toBe(5);
  });

  test('returns books directly without filtering (schema guarantees title+author)', async () => {
    const mockFetch = vi.fn(() => Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify([
                { title: 'Book1', author: 'Author1' },
                { title: 'Book2', author: 'Author2' }
              ])
            }]
          }
        }],
        usageMetadata: {}
      })
    }));

    global.fetch = mockFetch;

    const result = await parseCSVWithGemini('csv', 'prompt', 'key');

    // All books should be returned (no filtering for missing title/author)
    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({ title: 'Book1', author: 'Author1' });
    expect(result[1]).toEqual({ title: 'Book2', author: 'Author2' });
  });
});
