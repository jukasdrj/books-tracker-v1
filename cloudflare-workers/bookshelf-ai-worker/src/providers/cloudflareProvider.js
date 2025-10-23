import { AIProvider } from './AIProvider.interface.js';

/**
 * Cloudflare Workers AI vision provider implementation
 * Uses Llama 3.2 11B Vision with JSON schema mode for structured output
 */
export class CloudflareProvider extends AIProvider {
    constructor(aiBinding) {
        super();
        if (!aiBinding) {
            throw new Error('CloudflareProvider requires AI binding');
        }
        this.ai = aiBinding;
        this.modelName = '@cf/meta/llama-3.2-11b-vision-instruct';
    }

    getProviderName() {
        return 'cloudflare';
    }

    async scanImage(imageData, env) {
        const startTime = Date.now();

        try {
            // Convert ArrayBuffer to array for Workers AI
            const imageArray = [...new Uint8Array(imageData)];

            // Convert to base64 for image input
            const base64Image = this.arrayToBase64(imageArray);

            // Define JSON schema for structured output
            const schema = {
                type: "object",
                properties: {
                    books: {
                        type: "array",
                        items: {
                            type: "object",
                            properties: {
                                title: {
                                    type: ["string", "null"],
                                    description: "The full title of the book"
                                },
                                author: {
                                    type: ["string", "null"],
                                    description: "The full name of the author"
                                },
                                isbn: {
                                    type: ["string", "null"],
                                    description: "ISBN if visible"
                                },
                                confidence: {
                                    type: "number",
                                    description: "Confidence score (0.0-1.0) for the extracted title/author",
                                    minimum: 0.0,
                                    maximum: 1.0
                                },
                                boundingBox: {
                                    type: "object",
                                    description: "Normalized coordinates (0-1) of the book spine in the image",
                                    properties: {
                                        x1: { type: "number", description: "Top-left corner X coordinate (0-1)" },
                                        y1: { type: "number", description: "Top-left corner Y coordinate (0-1)" },
                                        x2: { type: "number", description: "Bottom-right corner X coordinate (0-1)" },
                                        y2: { type: "number", description: "Bottom-right corner Y coordinate (0-1)" }
                                    },
                                    required: ["x1", "y1", "x2", "y2"]
                                }
                            },
                            required: ["title", "author", "confidence", "boundingBox"]
                        }
                    },
                    suggestions: {
                        type: "array",
                        description: "Optional actionable suggestions for improving scan quality",
                        items: {
                            type: "object",
                            properties: {
                                type: {
                                    type: "string",
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
                                message: {
                                    type: "string",
                                    description: "User-friendly suggestion message"
                                },
                                severity: {
                                    type: "string",
                                    description: "Severity level",
                                    enum: ["low", "medium", "high"]
                                }
                            },
                            required: ["type", "message", "severity"]
                        }
                    }
                },
                required: ["books", "suggestions"]
            };

            // AI prompt for book detection (similar to GeminiProvider but optimized for Llama)
            const prompt = `You are a book detection specialist. Analyze this bookshelf image and identify every book spine visible.

For each book:
1. Extract the title
2. Extract the author's name
3. Determine bounding box coordinates (normalized 0-1, corners format: x1, y1, x2, y2)
4. Provide confidence score (0.0-1.0)

Return JSON with this exact structure:
{
  "books": [{"title": "string", "author": "string|null", "isbn": "string|null", "confidence": 0.0-1.0, "boundingBox": {"x1": 0.0-1.0, "y1": 0.0-1.0, "x2": 0.0-1.0, "y2": 0.0-1.0}}],
  "suggestions": [{"type": "string", "message": "string", "severity": "low|medium|high"}]
}

Bounding boxes use normalized coordinates (0-1). Suggestion types: unreadable_books, low_confidence, edge_cutoff, blurry_image, glare_detected, distance_too_far, multiple_shelves, lighting_issues, angle_issues.

If image quality is good, return empty suggestions array. Only include suggestions when issues are detected.`;

            // Call Workers AI with JSON schema mode
            const result = await this.ai.run(this.modelName, {
                messages: [{
                    role: 'user',
                    content: [
                        {
                            type: 'text',
                            text: prompt
                        },
                        {
                            type: 'image',
                            source: {
                                type: 'base64',
                                media_type: 'image/jpeg',
                                data: base64Image
                            }
                        }
                    ]
                }],
                response_format: {
                    type: 'json_object',
                    schema: schema
                }
            });

            // Parse response (Workers AI may return string or object)
            const scanResult = typeof result === 'string' ? JSON.parse(result) : result;

            // Add provider metadata
            return {
                books: scanResult.books || [],
                suggestions: scanResult.suggestions || [],
                metadata: {
                    provider: 'cloudflare',
                    model: this.modelName,
                    timestamp: new Date().toISOString(),
                    processingTimeMs: Date.now() - startTime
                }
            };

        } catch (error) {
            console.error('[CloudflareProvider] Scan failed:', error);
            throw error;
        }
    }

    /**
     * Utility to convert array to Base64 string
     * @param {Array<number>} array - The array to convert
     * @returns {string} The Base64 encoded string
     */
    arrayToBase64(array) {
        let binary = '';
        const len = array.length;
        for (let i = 0; i < len; i++) {
            binary += String.fromCharCode(array[i]);
        }
        return btoa(binary);
    }
}
