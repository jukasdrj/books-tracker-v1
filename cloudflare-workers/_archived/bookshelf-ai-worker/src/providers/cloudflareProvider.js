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

            // AI prompt for book detection (optimized for Llama 3.2 Vision with step-by-step instructions)
            const prompt = `You are an expert at analyzing bookshelf images and extracting book information.

TASK: Carefully scan this bookshelf image from left to right, top to bottom. For each book spine you can read:

1. Extract the EXACT title as written (preserve capitalization, subtitles, series info)
2. Extract the EXACT author name as written (first and last name)
3. If an ISBN is visible, extract all 10 or 13 digits exactly
4. Estimate your confidence (0.0-1.0) based on text clarity
5. Provide normalized bounding box coordinates (x1, y1, x2, y2) where:
   - x1, y1 = top-left corner (0 = left edge, 1 = right edge)
   - x2, y2 = bottom-right corner (0 = top edge, 1 = bottom edge)

CONFIDENCE SCORING GUIDE:
- 0.9-1.0: Text is crystal clear, no ambiguity
- 0.7-0.89: Text is mostly clear, minor blur or glare
- 0.5-0.69: Text is partially readable, some guessing involved
- 0.3-0.49: Text is barely readable, low confidence
- 0.0-0.29: Text is unreadable or heavily obscured

IMPORTANT RULES:
- Only include books where you can read AT LEAST the title
- Use null for author if not visible or unreadable
- Use null for ISBN if not visible (ISBNs are usually on spine bottom)
- Bounding boxes should tightly wrap each book spine (not the entire shelf)
- Books are typically vertical rectangles (height > width)
- If you're unsure about a title, include it with lower confidence

IMAGE QUALITY ANALYSIS:
After extracting all readable books, analyze the image for quality issues:

- Blur/motion blur → type: "blurry_image", severity: "medium"
- Glare/reflections blocking text → type: "glare_detected", severity: "high"
- Books cut off at edges → type: "edge_cutoff", severity: "low"
- Camera too far to read spines → type: "distance_too_far", severity: "high"
- Poor lighting/deep shadows → type: "lighting_issues", severity: "medium"
- Angled shot (not perpendicular) → type: "angle_issues", severity: "low"
- Multiple shelves visible (confusing) → type: "multiple_shelves", severity: "low"

Only include suggestions if you detect actual issues. If the image quality is good, return an empty suggestions array.`;

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
