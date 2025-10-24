import { CloudflareProvider } from '../src/providers/cloudflareProvider.js';
import { AIProvider } from '../src/providers/AIProvider.interface.js';

/**
 * Tests for CloudflareProvider
 * These tests verify the CloudflareProvider implements AIProvider interface correctly
 */

// Test 1: Constructor validation
console.log('Test 1: Constructor should throw error if AI binding is missing');
try {
    new CloudflareProvider(null);
    console.error('  ❌ FAILED: Should have thrown error for missing AI binding');
} catch (error) {
    if (error.message.includes('CloudflareProvider requires AI binding')) {
        console.log('  ✅ PASSED: Correctly throws error for missing AI binding');
    } else {
        console.error(`  ❌ FAILED: Wrong error message: ${error.message}`);
    }
}

// Test 2: Constructor with valid binding
console.log('\nTest 2: Constructor should accept valid AI binding');
try {
    const mockAI = { run: async () => ({}) };
    const provider = new CloudflareProvider(mockAI);
    console.log('  ✅ PASSED: Constructor accepts valid AI binding');
} catch (error) {
    console.error(`  ❌ FAILED: ${error.message}`);
}

// Test 3: Implements AIProvider interface
console.log('\nTest 3: Should implement AIProvider interface');
try {
    const mockAI = { run: async () => ({}) };
    const provider = new CloudflareProvider(mockAI);

    // Check inheritance
    if (!(provider instanceof AIProvider)) {
        console.error('  ❌ FAILED: Not an instance of AIProvider');
    } else if (typeof provider.scanImage !== 'function') {
        console.error('  ❌ FAILED: Missing scanImage method');
    } else if (typeof provider.getProviderName !== 'function') {
        console.error('  ❌ FAILED: Missing getProviderName method');
    } else {
        console.log('  ✅ PASSED: Implements AIProvider interface');
    }
} catch (error) {
    console.error(`  ❌ FAILED: ${error.message}`);
}

// Test 4: getProviderName() returns correct value
console.log('\nTest 4: getProviderName() should return "cloudflare"');
try {
    const mockAI = { run: async () => ({}) };
    const provider = new CloudflareProvider(mockAI);
    const name = provider.getProviderName();

    if (name === 'cloudflare') {
        console.log('  ✅ PASSED: Returns "cloudflare"');
    } else {
        console.error(`  ❌ FAILED: Expected "cloudflare", got "${name}"`);
    }
} catch (error) {
    console.error(`  ❌ FAILED: ${error.message}`);
}

// Test 5: scanImage() is callable
console.log('\nTest 5: scanImage() method should be callable');
try {
    const mockAI = { run: async () => ({}) };
    const provider = new CloudflareProvider(mockAI);

    if (typeof provider.scanImage === 'function') {
        console.log('  ✅ PASSED: scanImage is a function');
    } else {
        console.error('  ❌ FAILED: scanImage is not a function');
    }
} catch (error) {
    console.error(`  ❌ FAILED: ${error.message}`);
}

// Test 6: scanImage() with mock AI binding (basic flow test)
console.log('\nTest 6: scanImage() should call AI binding and return structured result');
(async () => {
    try {
        const mockBooks = [
            {
                title: "Test Book",
                author: "Test Author",
                isbn: null,
                confidence: 0.9,
                boundingBox: { x1: 0.1, y1: 0.2, x2: 0.15, y2: 0.8 }
            }
        ];

        const mockSuggestions = [
            {
                type: "glare_detected",
                message: "Some glare detected",
                severity: "warning"
            }
        ];

        const mockAI = {
            run: async (model, params) => {
                // Verify model name
                if (!model.includes('llama-3.2-11b-vision')) {
                    throw new Error(`Wrong model: ${model}`);
                }

                // Return mock response
                return {
                    books: mockBooks,
                    suggestions: mockSuggestions
                };
            }
        };

        const provider = new CloudflareProvider(mockAI);

        // Create mock image data (minimal ArrayBuffer)
        const mockImageData = new ArrayBuffer(100);

        const result = await provider.scanImage(mockImageData, {});

        // Verify result structure
        if (!result.books || !Array.isArray(result.books)) {
            console.error('  ❌ FAILED: Result missing books array');
        } else if (!result.suggestions || !Array.isArray(result.suggestions)) {
            console.error('  ❌ FAILED: Result missing suggestions array');
        } else if (!result.metadata || result.metadata.provider !== 'cloudflare') {
            console.error('  ❌ FAILED: Result missing or invalid metadata');
        } else if (!result.metadata.model || !result.metadata.timestamp) {
            console.error('  ❌ FAILED: Metadata missing required fields');
        } else {
            console.log('  ✅ PASSED: Returns properly structured result with metadata');
        }

    } catch (error) {
        console.error(`  ❌ FAILED: ${error.message}`);
    }
})();

console.log('\n========================================');
console.log('CloudflareProvider Tests Complete');
console.log('========================================\n');
console.log('Note: Run with: node tests/cloudflare-provider.test.js');
