import { AIProviderFactory } from './src/providers/AIProviderFactory.js';

// Test 1: Valid configuration
const validEnv = { AI_PROVIDER: 'gemini', GEMINI_API_KEY: 'test-key' };
try {
    const provider = AIProviderFactory.createProvider(validEnv);
    console.log('✅ Test 1: Factory created provider:', provider.getProviderName());
} catch (error) {
    console.error('❌ Test 1 failed:', error);
    process.exit(1);
}

// Test 2: Default to gemini
const defaultEnv = { GEMINI_API_KEY: 'test-key' }; // No AI_PROVIDER
try {
    const provider = AIProviderFactory.createProvider(defaultEnv);
    console.log('✅ Test 2: Defaults to gemini:', provider.getProviderName());
} catch (error) {
    console.error('❌ Test 2 failed:', error);
    process.exit(1);
}

// Test 3: Missing API key
const noKeyEnv = { AI_PROVIDER: 'gemini' };
try {
    AIProviderFactory.createProvider(noKeyEnv);
    console.error('❌ Test 3: Should have thrown error for missing API key');
    process.exit(1);
} catch (error) {
    console.log('✅ Test 3: Correctly throws error:', error.message);
}

// Test 4: Unknown provider
const unknownEnv = { AI_PROVIDER: 'unknown', GEMINI_API_KEY: 'test-key' };
try {
    AIProviderFactory.createProvider(unknownEnv);
    console.error('❌ Test 4: Should have thrown error for unknown provider');
    process.exit(1);
} catch (error) {
    console.log('✅ Test 4: Correctly throws error:', error.message);
}

// Test 5: Case-insensitive
const upperEnv = { AI_PROVIDER: 'GEMINI', GEMINI_API_KEY: 'test-key' };
try {
    const provider = AIProviderFactory.createProvider(upperEnv);
    console.log('✅ Test 5: Case-insensitive matching:', provider.getProviderName());
} catch (error) {
    console.error('❌ Test 5 failed:', error);
    process.exit(1);
}

// Test 6: Null/undefined env guard (NEW from code review)
console.log('\n--- Testing null/undefined env guards ---');
try {
    AIProviderFactory.createProvider(null);
    console.error('❌ Test 6a: Should have thrown error for null env');
    process.exit(1);
} catch (error) {
    console.log('✅ Test 6a: Correctly rejects null env:', error.message);
}

try {
    AIProviderFactory.createProvider(undefined);
    console.error('❌ Test 6b: Should have thrown error for undefined env');
    process.exit(1);
} catch (error) {
    console.log('✅ Test 6b: Correctly rejects undefined env:', error.message);
}

try {
    AIProviderFactory.createProvider('not-an-object');
    console.error('❌ Test 6c: Should have thrown error for string env');
    process.exit(1);
} catch (error) {
    console.log('✅ Test 6c: Correctly rejects non-object env:', error.message);
}

console.log('\n--- Supported providers ---');
console.log('✅ Test 7: Supported providers:', AIProviderFactory.getSupportedProviders());

console.log('\n🎉 All factory tests passed!');
