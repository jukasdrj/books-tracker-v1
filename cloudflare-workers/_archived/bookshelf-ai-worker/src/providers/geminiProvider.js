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

            // AI prompt for book detection (optimized for Gemini 2.5 Flash)
            const systemPrompt = `You are an expert at analyzing bookshelf images and extracting book information with high precision.

TASK: Systematically scan this bookshelf image from left to right, top to bottom. For each visible book spine:

1. Extract the EXACT title as written (preserve ALL capitalization, punctuation, subtitles, series markers)
2. Extract the EXACT author name (full first and last name, include middle initials if visible)
3. If an ISBN-10 or ISBN-13 is visible on the spine, extract ALL digits exactly (ISBNs are typically near the bottom)
4. Provide a confidence score (0.0-1.0) based on text clarity and your certainty
5. Provide precise normalized bounding box coordinates (x1, y1, x2, y2) where:
   - x1, y1 = top-left corner of book spine (0.0 = left/top edge, 1.0 = right/bottom edge)
   - x2, y2 = bottom-right corner of book spine
   - Coordinates must be normalized to image dimensions (0.0-1.0 range)

CONFIDENCE SCORING RUBRIC:
- 0.95-1.0: Perfect clarity, absolutely certain of title and author
- 0.85-0.94: Very clear text, minor ambiguity (e.g., small font or slight blur)
- 0.70-0.84: Mostly clear, some guessing on author or subtitle
- 0.50-0.69: Partially readable, significant uncertainty
- 0.30-0.49: Barely readable, very low confidence
- Below 0.30: Text is illegible or heavily obscured

CRITICAL RULES:
- Include ONLY books where you can read at least the title
- If author is not visible or unreadable, use null (do NOT guess)
- If ISBN is not visible, use null (most books won't have visible ISBNs on spine)
- Bounding boxes must tightly wrap ONLY the book spine (not shelf edges or neighboring books)
- Books are typically tall vertical rectangles (height >> width)
- Preserve exact capitalization (e.g., "The GREAT Gatsby" not "The Great Gatsby")
- Include series markers if present (e.g., "Book Title (Series, #3)")

IMAGE QUALITY DIAGNOSTICS:
After extracting all readable books, analyze the image for quality issues:

COMMON ISSUES TO DETECT:
1. "unreadable_books" → Some spines are too small/blurry to read → severity: "medium"
   Message: "X books have text too small or blurry to read clearly"

2. "low_confidence" → Multiple books extracted with confidence <0.7 → severity: "medium"
   Message: "Several book titles/authors are unclear due to image quality"

3. "edge_cutoff" → Books cut off at image edges → severity: "low"
   Message: "Some books are partially cut off at the edges of the photo"

4. "blurry_image" → Overall motion blur or out-of-focus → severity: "high"
   Message: "Image appears blurry or out of focus - try steadying the camera"

5. "glare_detected" → Reflective glare obscuring text → severity: "high"
   Message: "Glare is making some book spines hard to read - adjust lighting or angle"

6. "distance_too_far" → Camera too far away, text illegible → severity: "high"
   Message: "Camera is too far from the shelf - move closer for better text recognition"

7. "multiple_shelves" → Multiple shelf rows visible (confusing layout) → severity: "low"
   Message: "Multiple shelves detected - focus on one shelf per scan for best results"

8. "lighting_issues" → Shadows or poor illumination → severity: "medium"
   Message: "Lighting is uneven - try using more consistent light or avoiding shadows"

9. "angle_issues" → Photo taken at an angle (not perpendicular) → severity: "low"
   Message: "Photo is angled - try taking the photo more directly facing the shelf"

IMPORTANT: Only include suggestions if you actually detect these issues. If the image quality is good, return an empty suggestions array []`;

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
                                isbn: {
                                    type: "STRING",
                                    description: "ISBN-10 or ISBN-13 if visible on spine.",
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
