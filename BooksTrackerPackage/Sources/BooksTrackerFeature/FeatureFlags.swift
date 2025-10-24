import SwiftUI

/// Feature flags for experimental iOS 26 features
///
/// This observable class manages feature toggles that can be enabled/disabled
/// via Settings. Flags are persisted using UserDefaults for user preference retention.
@Observable
public final class FeatureFlags: Sendable {
    /// Enable tab bar minimize behavior on scroll
    ///
    /// When enabled, the tab bar automatically hides when scrolling down
    /// and reappears when scrolling up. This provides more screen space
    /// for content while maintaining easy access to navigation.
    ///
    /// Default: `true` (enabled)
    ///
    /// Note: This behavior is automatically disabled for VoiceOver and
    /// Reduce Motion accessibility settings, regardless of this flag.
    public var enableTabBarMinimize: Bool {
        get {
            UserDefaults.standard.object(forKey: "enableTabBarMinimize") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableTabBarMinimize")
        }
    }

    public static let shared = FeatureFlags()

    private init() {}

    /// Reset all feature flags to default values
    /// Called during library reset to restore clean state
    public func resetToDefaults() {
        enableTabBarMinimize = true  // Default enabled
        print("✅ FeatureFlags reset to defaults (tabBarMinimize: true)")
    }
}
