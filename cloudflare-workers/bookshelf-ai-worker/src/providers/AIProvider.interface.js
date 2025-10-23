/**
 * Standard interface for AI vision providers
 * All providers must implement this interface to scan bookshelf images
 */

/**
 * @typedef {Object} ScanResult
 * @property {Array<DetectedBook>} books - Array of detected books
 * @property {Array<Suggestion>} suggestions - Image quality suggestions
 * @property {Object} metadata - Provider-specific metadata
 */

/**
 * @typedef {Object} DetectedBook
 * @property {string} title - Book title
 * @property {string|null} author - Author name (if detected)
 * @property {string|null} isbn - ISBN (if detected)
 * @property {number} confidence - Detection confidence (0.0-1.0)
 * @property {Object} boundingBox - Bounding box coordinates (normalized 0-1)
 * @property {number} boundingBox.x - X coordinate
 * @property {number} boundingBox.y - Y coordinate
 * @property {number} boundingBox.width - Width
 * @property {number} boundingBox.height - Height
 */

/**
 * @typedef {Object} Suggestion
 * @property {string} type - Suggestion type (blurry, glare, cutoff, etc.)
 * @property {string} message - Human-readable message
 * @property {string} severity - Severity level (warning, error, info)
 */

export class AIProvider {
    /**
     * Scan a bookshelf image and extract book information
     * @param {ArrayBuffer} imageData - Raw image data
     * @param {Object} env - Cloudflare Worker environment bindings
     * @returns {Promise<ScanResult>} Scan results with books, suggestions, metadata
     * @throws {Error} If scanning fails
     */
    async scanImage(imageData, env) {
        throw new Error('AIProvider.scanImage() must be implemented by subclass');
    }

    /**
     * Get provider name for logging/debugging
     * @returns {string} Provider name
     */
    getProviderName() {
        throw new Error('AIProvider.getProviderName() must be implemented by subclass');
    }
}
