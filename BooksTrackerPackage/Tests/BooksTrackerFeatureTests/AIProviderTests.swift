import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("AIProvider Tests")
struct AIProviderTests {
    @Test("AIProvider enum has 4 model options")
    func testAIProviderCases() throws {
        #expect(AIProvider.allCases.count == 4)
        #expect(AIProvider.allCases.contains(.geminiFlash))
        #expect(AIProvider.allCases.contains(.llava))
        #expect(AIProvider.allCases.contains(.qwen))
        #expect(AIProvider.allCases.contains(.llamaVision))
    }

    @Test("Provider has correct raw values")
    func testRawValues() {
        #expect(AIProvider.geminiFlash.rawValue == "gemini-flash")
        #expect(AIProvider.llava.rawValue == "cf-llava-1.5-7b")
        #expect(AIProvider.qwen.rawValue == "cf-uform-gen2-qwen-500m")
        #expect(AIProvider.llamaVision.rawValue == "cf-llama-3.2-11b-vision")
    }

    @Test("AIProvider cloudflareModelId returns correct model strings")
    func testCloudflareModelIds() throws {
        #expect(AIProvider.llava.cloudflareModelId == "@cf/llava-hf/llava-1.5-7b-hf")
        #expect(AIProvider.qwen.cloudflareModelId == "@cf/unum/uform-gen2-qwen-500m")
        #expect(AIProvider.llamaVision.cloudflareModelId == "@cf/meta/llama-3.2-11b-vision-instruct")
        #expect(AIProvider.geminiFlash.cloudflareModelId == nil)
    }

    @Test("AIProvider isCloudflare property is correct")
    func testIsCloudflare() throws {
        #expect(AIProvider.geminiFlash.isCloudflare == false)
        #expect(AIProvider.llava.isCloudflare == true)
        #expect(AIProvider.qwen.isCloudflare == true)
        #expect(AIProvider.llamaVision.isCloudflare == true)
    }

    @Test("Provider has correct display names")
    func testDisplayNames() {
        #expect(AIProvider.geminiFlash.displayName == "Gemini Flash (Google)")
        #expect(AIProvider.llava.displayName == "LLaVA 1.5 (Cloudflare)")
        #expect(AIProvider.qwen.displayName == "Qwen/UForm (Cloudflare - Fast)")
        #expect(AIProvider.llamaVision.displayName == "Llama 3.2 Vision (Cloudflare - Accurate)")
    }

    @Test("Provider is Codable")
    func testCodable() throws {
        let encoded = try JSONEncoder().encode(AIProvider.geminiFlash)
        let decoded = try JSONDecoder().decode(AIProvider.self, from: encoded)
        #expect(decoded == .geminiFlash)
    }

    @Test("Provider has detailed descriptions")
    func testDescriptions() {
        #expect(AIProvider.geminiFlash.description.contains("25-40s"))
        #expect(AIProvider.llava.description.contains("5-12s"))
        #expect(AIProvider.qwen.description.contains("3-8s"))
        #expect(AIProvider.llamaVision.description.contains("8-15s"))
    }

    @Test("Provider has correct SF Symbol icons")
    func testIcons() {
        #expect(AIProvider.geminiFlash.icon == "sparkles")
        #expect(AIProvider.llava.icon == "eye")
        #expect(AIProvider.qwen.icon == "hare")
        #expect(AIProvider.llamaVision.icon == "brain.head.profile")
    }

    @Test("Gemini has high-quality preprocessing config")
    func testGeminiPreprocessing() {
        let config = AIProvider.geminiFlash.preprocessingConfig
        #expect(config.maxDimension == 3072)
        #expect(config.jpegQuality == 0.90)
        #expect(config.targetFileSizeKB == 400...600)
    }

    @Test("LLaVA has balanced preprocessing config")
    func testLlavaPreprocessing() {
        let config = AIProvider.llava.preprocessingConfig
        #expect(config.maxDimension == 2048)
        #expect(config.jpegQuality == 0.87)
        #expect(config.targetFileSizeKB == 250...400)
    }

    @Test("Qwen has fast preprocessing config")
    func testQwenPreprocessing() {
        let config = AIProvider.qwen.preprocessingConfig
        #expect(config.maxDimension == 1536)
        #expect(config.jpegQuality == 0.85)
        #expect(config.targetFileSizeKB == 150...300)
    }

    @Test("Llama Vision has high-quality preprocessing config")
    func testLlamaVisionPreprocessing() {
        let config = AIProvider.llamaVision.preprocessingConfig
        #expect(config.maxDimension == 2560)
        #expect(config.jpegQuality == 0.88)
        #expect(config.targetFileSizeKB == 300...500)
    }

    @Test("AIProviderSettings persists to UserDefaults")
    func testSettingsPersistence() {
        let settings = AIProviderSettings.shared

        // Set LLaVA
        settings.selectedProvider = .llava
        #expect(settings.selectedProvider == .llava)

        // Verify UserDefaults
        let stored = UserDefaults.standard.string(forKey: "aiProvider")
        #expect(stored == "cf-llava-1.5-7b")

        // Change back to Gemini Flash
        settings.selectedProvider = .geminiFlash
        #expect(settings.selectedProvider == .geminiFlash)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "aiProvider")
    }
}
