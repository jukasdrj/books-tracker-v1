import SwiftUI

/// Settings for AI provider selection
///
/// This observable class manages AI provider preference that persists
/// via UserDefaults. Uses stored property to ensure @Observable tracking works.
///
/// Note: @unchecked Sendable because @Observable macro generates mutable storage,
/// but UserDefaults access is thread-safe and class is used only on MainActor.
@Observable
public final class AIProviderSettings: @unchecked Sendable {
    /// Currently selected AI provider
    ///
    /// Default: `.gemini` (proven accuracy)
    ///
    /// Note: Uses stored property with didSet to ensure @Observable notifications fire
    public var selectedProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "aiProvider")
        }
    }

    public static let shared = AIProviderSettings()

    private init() {
        // Load from UserDefaults on init
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        self.selectedProvider = AIProvider(rawValue: raw) ?? .gemini
    }

    /// Reset AI provider settings to default values
    /// Called during library reset to restore clean state
    public func resetToDefaults() {
        selectedProvider = .gemini  // Default to proven accuracy
        print("✅ AIProviderSettings reset to defaults (provider: gemini)")
    }
}
