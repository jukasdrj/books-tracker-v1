import { AIProvider } from './AIProvider.interface.js';

/**
 * Gemini AI vision provider implementation
 * Uses Google Gemini 2.5 Flash for bookshelf scanning
 */
export class GeminiProvider extends AIProvider {
    constructor(apiKey) {
        super();
        if (!apiKey) {
            throw new Error('GeminiProvider requires GEMINI_API_KEY');
        }
        this.apiKey = apiKey;
        this.modelName = 'gemini-2.5-flash-preview-05-20';
        this.apiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/${this.modelName}:generateContent`;
        this.userAgent = 'BooksTracker/3.0.0 (nerd@ooheynerds.com) BookshelfAIWorker/1.0.0';
    }

    getProviderName() {
        return 'gemini';
    }

    async scanImage(imageData, env) {
        const startTime = Date.now();

        try {
            // Convert ArrayBuffer to Base64
            const base64Image = this.arrayBufferToBase64(imageData);

            // AI prompt for book detection
            const systemPrompt = `You are a book detection specialist. Analyze the provided image of a bookshelf. Your task is to identify every book spine visible.

For each book you identify, perform the following actions:
1. Extract the book's title.
2. Extract the author's name.
3. Determine the bounding box coordinates for the book's spine.
4. Provide a confidence score (from 0.0 to 1.0) indicating how certain you are about the extracted title and author. A score of 1.0 means absolute certainty, while a score below 0.5 indicates a guess.
5. Return your findings as a JSON object that strictly adheres to the provided schema.
6. Analyze image quality issues and provide actionable suggestions ONLY if problems are detected.

If the image has quality issues (blurry, poor lighting, bad angle, glare, too far, multiple shelves, or many unreadable books), populate a 'suggestions' array with objects identifying the specific problems.

Otherwise, leave the 'suggestions' array empty or omit it entirely.

Available suggestion types:
- unreadable_books: Books detected but text unclear
- low_confidence: Many books with confidence < 0.7
- edge_cutoff: Books cut off at image edges
- blurry_image: Image lacks sharpness/focus
- glare_detected: Reflections obscuring book covers
- distance_too_far: Camera too far from shelf
- multiple_shelves: Multiple shelves in frame
- lighting_issues: Insufficient or uneven lighting
- angle_issues: Camera angle makes spines hard to read

Only include suggestions when you detect issues. Perfect scans should have an empty suggestions array.

If you can clearly identify a book's spine but the text is unreadable, you MUST still include it. In such cases, set 'title' and 'author' to null and the 'confidence' to 0.0.

Here is an example of a good detection:
{
  "title": "The Hitchhiker's Guide to the Galaxy",
  "author": "Douglas Adams",
  "confidence": 0.95,
  "boundingBox": { "x1": 0.1, "y1": 0.2, "x2": 0.15, "y2": 0.8 }
}

Here is an example of an unreadable book:
{
  "title": null,
  "author": null,
  "confidence": 0.0,
  "boundingBox": { "x1": 0.2, "y1": 0.3, "x2": 0.25, "y2": 0.9 }
}

Here is an example response with suggestions:
{
  "books": [
    { "title": "Example Book", "author": "Author", "confidence": 0.95, "boundingBox": {"x1": 0.1, "y1": 0.2, "x2": 0.15, "y2": 0.8} },
    { "title": null, "author": null, "confidence": 0.0, "boundingBox": {"x1": 0.2, "y1": 0.3, "x2": 0.25, "y2": 0.9} }
  ],
  "suggestions": [
    {
      "type": "unreadable_books",
      "severity": "medium",
      "message": "2 books detected but text is unreadable. Try capturing from a more direct angle or with better lighting.",
      "affectedCount": 2
    }
  ]
}`;

            // JSON schema for structured output
            const schema = {
                type: "OBJECT",
                properties: {
                    books: {
                        type: "ARRAY",
                        items: {
                            type: "OBJECT",
                            properties: {
                                title: {
                                    type: "STRING",
                                    description: "The full title of the book.",
                                    nullable: true
                                },
                                author: {
                                    type: "STRING",
                                    description: "The full name of the author.",
                                    nullable: true
                                },
                                confidence: {
                                    type: "NUMBER",
                                    description: "Confidence score (0.0-1.0) for the extracted title/author."
                                },
                                boundingBox: {
                                    type: "OBJECT",
                                    description: "The normalized coordinates of the book spine in the image.",
                                    properties: {
                                        x1: { type: "NUMBER", description: "Top-left corner X coordinate (0-1)." },
                                        y1: { type: "NUMBER", description: "Top-left corner Y coordinate (0-1)." },
                                        x2: { type: "NUMBER", description: "Bottom-right corner X coordinate (0-1)." },
                                        y2: { type: "NUMBER", description: "Bottom-right corner Y coordinate (0-1)." },
                                    },
                                    required: ["x1", "y1", "x2", "y2"],
                                },
                            },
                            required: ["boundingBox", "title", "author", "confidence"],
                        },
                    },
                    suggestions: {
                        type: "ARRAY",
                        description: "Optional actionable suggestions for improving scan quality (only present if issues detected)",
                        items: {
                            type: "OBJECT",
                            properties: {
                                type: {
                                    type: "STRING",
                                    description: "Category of suggestion",
                                    enum: [
                                        "unreadable_books",
                                        "low_confidence",
                                        "edge_cutoff",
                                        "blurry_image",
                                        "glare_detected",
                                        "distance_too_far",
                                        "multiple_shelves",
                                        "lighting_issues",
                                        "angle_issues"
                                    ]
                                },
                                severity: {
                                    type: "STRING",
                                    description: "Severity level",
                                    enum: ["low", "medium", "high"]
                                },
                                message: {
                                    type: "STRING",
                                    description: "User-friendly suggestion message"
                                },
                                affectedCount: {
                                    type: "NUMBER",
                                    description: "Number of books affected by this issue (optional)"
                                }
                            },
                            required: ["type", "severity", "message"]
                        }
                    }
                },
                required: ["books"],
            };

            // Build Gemini-specific payload
            const payload = {
                contents: [
                    {
                        parts: [
                            { text: systemPrompt },
                            {
                                inlineData: {
                                    mimeType: "image/jpeg",
                                    data: base64Image,
                                },
                            },
                        ],
                    },
                ],
                generationConfig: {
                    responseMimeType: "application/json",
                    responseSchema: schema,
                },
            };

            // Call Gemini API with timeout
            const controller = new AbortController();
            const timeoutMs = 50000; // 50s timeout for large images
            const timeout = setTimeout(() => controller.abort(), timeoutMs);

            try {
                const response = await fetch(
                    `${this.apiEndpoint}?key=${this.apiKey}`,
                    {
                        method: "POST",
                        headers: {
                            "Content-Type": "application/json",
                            "User-Agent": this.userAgent
                        },
                        body: JSON.stringify(payload),
                        signal: controller.signal,
                    }
                );

                if (!response.ok) {
                    const errorText = await response.text();
                    throw new Error(`Gemini API Error: ${response.status} ${response.statusText} - ${errorText}`);
                }

                const result = await response.json();

                const candidate = result.candidates?.[0];
                if (!candidate || !candidate.content?.parts?.[0]?.text) {
                    throw new Error("Invalid response structure from Gemini API.");
                }

                // Parse the JSON response from Gemini
                const scanResult = JSON.parse(candidate.content.parts[0].text);

                // Add provider metadata
                return {
                    books: scanResult.books || [],
                    suggestions: scanResult.suggestions || [],
                    metadata: {
                        provider: 'gemini',
                        model: this.modelName,
                        timestamp: new Date().toISOString(),
                        processingTimeMs: Date.now() - startTime
                    }
                };

            } finally {
                clearTimeout(timeout);
            }

        } catch (error) {
            console.error('[GeminiProvider] Scan failed:', error);
            throw error;
        }
    }

    /**
     * Utility to convert ArrayBuffer to Base64 string
     * @param {ArrayBuffer} buffer - The buffer to convert
     * @returns {string} The Base64 encoded string
     */
    arrayBufferToBase64(buffer) {
        let binary = '';
        const bytes = new Uint8Array(buffer);
        const len = bytes.byteLength;
        for (let i = 0; i < len; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
    }
}
