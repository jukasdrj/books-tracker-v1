import SwiftUI

/// Settings for AI provider selection
///
/// This observable class manages AI provider preference that persists
/// via UserDefaults. Follows the same pattern as FeatureFlags.swift.
@Observable
public final class AIProviderSettings: Sendable {
    /// Currently selected AI provider
    ///
    /// Default: `.gemini` (proven accuracy)
    public var selectedProvider: AIProvider {
        get {
            let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
            return AIProvider(rawValue: raw) ?? .gemini
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "aiProvider")
        }
    }

    public static let shared = AIProviderSettings()

    private init() {}
}
