import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("AIProvider Tests")
struct AIProviderTests {
    @Test("Provider has correct raw values")
    func testRawValues() {
        #expect(AIProvider.gemini.rawValue == "gemini")
        #expect(AIProvider.cloudflare.rawValue == "cloudflare")
    }

    @Test("Provider has correct display names")
    func testDisplayNames() {
        #expect(AIProvider.gemini.displayName == "Gemini (Accurate)")
        #expect(AIProvider.cloudflare.displayName == "Cloudflare (Fast)")
    }

    @Test("Provider is Codable")
    func testCodable() throws {
        let encoded = try JSONEncoder().encode(AIProvider.gemini)
        let decoded = try JSONDecoder().decode(AIProvider.self, from: encoded)
        #expect(decoded == .gemini)
    }

    @Test("Provider has detailed descriptions")
    func testDescriptions() {
        #expect(AIProvider.gemini.description.contains("25-40 seconds"))
        #expect(AIProvider.cloudflare.description.contains("3-8 seconds"))
    }

    @Test("Provider has correct SF Symbol icons")
    func testIcons() {
        #expect(AIProvider.gemini.icon == "sparkles")
        #expect(AIProvider.cloudflare.icon == "bolt.fill")
    }

    @Test("Gemini has high-quality preprocessing config")
    func testGeminiPreprocessing() {
        let config = AIProvider.gemini.preprocessingConfig
        #expect(config.maxDimension == 3072)
        #expect(config.jpegQuality == 0.90)
        #expect(config.targetFileSizeKB == 400...600)
    }

    @Test("Cloudflare has fast preprocessing config")
    func testCloudflarePreprocessing() {
        let config = AIProvider.cloudflare.preprocessingConfig
        #expect(config.maxDimension == 1536)
        #expect(config.jpegQuality == 0.85)
        #expect(config.targetFileSizeKB == 150...300)
    }

    @Test("AIProviderSettings persists to UserDefaults")
    func testSettingsPersistence() {
        let settings = AIProviderSettings.shared

        // Set Cloudflare
        settings.selectedProvider = .cloudflare
        #expect(settings.selectedProvider == .cloudflare)

        // Verify UserDefaults
        let stored = UserDefaults.standard.string(forKey: "aiProvider")
        #expect(stored == "cloudflare")

        // Change back to Gemini
        settings.selectedProvider = .gemini
        #expect(settings.selectedProvider == .gemini)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "aiProvider")
    }
}
