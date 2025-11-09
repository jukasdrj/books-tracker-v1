/**
 * JSON Schemas for Gemini Structured Output
 *
 * These schemas guarantee the structure and types of the JSON objects
 * returned by the Gemini API, eliminating the need for manual validation.
 *
 * Docs: https://ai.google.dev/gemini-api/docs/structured-output
 */

// Schema for the bookshelf scanner (gemini-provider.js)
export const BookshelfResponseSchema = {
  type: "array",
  items: {
    type: "object",
    properties: {
      title: { type: "string" },
      author: { type: "string" },
      format: {
        type: "string",
        enum: ["hardcover", "paperback", "mass-market", "unknown"]
      },
      confidence: {
        type: "number",
        minimum: 0,
        maximum: 1
      },
      boundingBox: {
        type: "object",
        properties: {
          x1: { type: "number", minimum: 0, maximum: 1 },
          y1: { type: "number", minimum: 0, maximum: 1 },
          x2: { type: "number", minimum: 0, maximum: 1 },
          y2: { type: "number", minimum: 0, maximum: 1 }
        },
        required: ["x1", "y1", "x2", "y2"]
      }
    },
    required: ["title", "confidence", "boundingBox"]
  }
};

// Schema for the CSV importer (gemini-csv-provider.js)
export const CSVBookSchema = {
  type: "array",
  items: {
    type: "object",
    properties: {
      title: { type: "string" },
      author: { type: "string" },
      isbn: { type: "string" },
      publisher: { type: "string" },
      publicationYear: { type: "number" },
      // ... other fields from canonical.ts could be added here
    },
    required: ["title", "author"]
  }
};
