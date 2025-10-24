import { GeminiProvider } from './geminiProvider.js';
import { CloudflareProvider } from './cloudflareProvider.js';

/**
 * Factory for creating AI provider instances based on configuration
 */
export class AIProviderFactory {
    /**
     * Create provider instance from environment configuration
     * @param {Object} env - Cloudflare Worker environment bindings
     * @returns {AIProvider} Configured provider instance
     * @throws {Error} If provider configuration is invalid
     */
    static createProvider(env) {
        if (!env || typeof env !== 'object') {
            throw new Error('AIProviderFactory.createProvider() requires valid env object');
        }
        const providerType = env.AI_PROVIDER || 'gemini';

        switch (providerType.toLowerCase()) {
            case 'gemini':
                if (!env.GEMINI_API_KEY) {
                    throw new Error('GEMINI_API_KEY required for gemini provider');
                }
                console.log('[AIProviderFactory] Creating Gemini provider');
                return new GeminiProvider(env.GEMINI_API_KEY);

            case 'cloudflare':
                if (!env.AI) {
                    throw new Error('AI binding required for cloudflare provider');
                }
                console.log('[AIProviderFactory] Creating Cloudflare Workers AI provider');
                return new CloudflareProvider(env.AI);

            default:
                throw new Error(`Unknown AI provider: ${providerType}`);
        }
    }

    /**
     * Get list of supported provider types
     * @returns {Array<string>} Supported provider names
     */
    static getSupportedProviders() {
        return ['gemini', 'cloudflare'];
    }
}
