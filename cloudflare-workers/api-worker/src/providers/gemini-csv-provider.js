// src/providers/gemini-csv-provider.js

const GEMINI_API_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';

/**
 * JSON Schema for CSV parser response
 * Enforces type safety and validation at the Gemini API level
 * Guarantees all books have required title and author fields
 */
const CSV_BOOK_SCHEMA = {
  type: "ARRAY",
  items: {
    type: "OBJECT",
    properties: {
      title: {
        type: "STRING",
        description: "Book title (required)"
      },
      author: {
        type: "STRING",
        description: "Author name (required)"
      },
      isbn: {
        type: "STRING",
        description: "ISBN-10 or ISBN-13",
        nullable: true
      },
      publicationYear: {
        type: "INTEGER",
        description: "Year of publication",
        nullable: true
      },
      publisher: {
        type: "STRING",
        description: "Publisher name",
        nullable: true
      },
      pageCount: {
        type: "INTEGER",
        description: "Number of pages",
        nullable: true
      },
      genre: {
        type: "STRING",
        description: "Primary genre or subject",
        nullable: true
      },
      rating: {
        type: "NUMBER",
        description: "User rating (0-5)",
        nullable: true,
        minimum: 0,
        maximum: 5
      },
      dateRead: {
        type: "STRING",
        description: "Date finished reading (YYYY-MM-DD)",
        nullable: true
      },
      notes: {
        type: "STRING",
        description: "User notes or review",
        nullable: true
      }
    },
    required: ["title", "author"]
  }
};

/**
 * Parse CSV file using Gemini 2.5 Flash-Lite API
 *
 * Features:
 * - System instructions for role definition (Gemini best practice)
 * - Low temperature (0.1) for maximum determinism with Flash-Lite
 * - responseMimeType for guaranteed JSON output (no markdown stripping needed)
 * - responseSchema for type safety (Gemini won't return books without title+author)
 * - Supports large CSVs (up to 8K tokens output)
 *
 * @param {string} csvText - Raw CSV content
 * @param {string} prompt - Gemini prompt with few-shot examples
 * @param {string} apiKey - Gemini API key from env.GEMINI_API_KEY
 * @returns {Promise<Array<Object>>} Parsed book data
 * @throws {Error} If API call fails or response is invalid
 */
export async function parseCSVWithGemini(csvText, prompt, apiKey) {
  const fullPrompt = `${prompt}\n\nCSV Data:\n${csvText}`;

  const response = await fetch(GEMINI_API_ENDPOINT, {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      // System instruction: Define the CSV parser's role
      system_instruction: {
        parts: [{
          text: `You are an expert book data parser specialized in extracting structured book information from CSV exports.

Your primary task is to intelligently map CSV columns to a standardized book data schema, handling various CSV formats from Goodreads, LibraryThing, StoryGraph, and custom exports.

Core capabilities:
- Auto-detect column headers regardless of format variations
- Infer missing metadata (author gender, cultural region, genre) when possible
- Normalize data types and formats (dates, ratings, ISBN formats)
- Handle malformed or incomplete rows gracefully

Always return ONLY a valid JSON array. Do not include explanatory text.`
        }]
      },
      contents: [{
        parts: [{
          text: fullPrompt
        }]
      }],
      generationConfig: {
        temperature: 0.1, // Maximum determinism for structured parsing with Flash-Lite
        topP: 0.95,       // Nucleus sampling for quality
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',  // Force JSON output (eliminates markdown code blocks)
        responseSchema: CSV_BOOK_SCHEMA,  // Schema-enforced validation (guarantees title+author)
        stopSequences: ['\n\n\n']  // Stop on triple newline (prevents unnecessary continuation)
      }
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Gemini API error: ${error}`);
  }

  const data = await response.json();
  const textResponse = data.candidates?.[0]?.content?.parts?.[0]?.text;

  // Extract token usage metrics (Gemini API best practice: cost tracking)
  const tokenUsage = data.usageMetadata || {};
  const promptTokens = tokenUsage.promptTokenCount || 0;
  const outputTokens = tokenUsage.candidatesTokenCount || 0;
  const totalTokens = tokenUsage.totalTokenCount || 0;

  console.log(`[GeminiCSVProvider] Token usage - Prompt: ${promptTokens}, Output: ${outputTokens}, Total: ${totalTokens}`);

  if (!textResponse) {
    throw new Error('Gemini returned empty response');
  }

  // With responseMimeType='application/json', text should be clean JSON
  // Keep markdown stripping as defensive fallback for API version compatibility
  let jsonText = textResponse.trim();

  // Remove markdown code blocks if present (defensive fallback)
  if (jsonText.startsWith('```json')) {
    jsonText = jsonText.replace(/```json\n?/g, '').replace(/```\n?/g, '');
  } else if (jsonText.startsWith('```')) {
    jsonText = jsonText.replace(/```\n?/g, '');
  }

  // Parse JSON (schema guarantees valid array structure)
  try {
    const parsed = JSON.parse(jsonText);
    // Schema guarantees array structure, but defensive check remains
    if (!Array.isArray(parsed)) {
      throw new Error('Gemini response is not an array');
    }
    return parsed;
  } catch (error) {
    throw new Error(`Invalid JSON from Gemini: ${error.message}`);
  }
}
