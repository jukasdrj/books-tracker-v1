import SwiftUI

// MARK: - iOS 26 Theme System

/// Theme variants optimized for iOS 26 Liquid Glass design
enum iOS26Theme: String, CaseIterable, Identifiable {
    case liquidBlue = "liquid_blue"
    case cosmicPurple = "cosmic_purple"
    case forestGreen = "forest_green"
    case sunsetOrange = "sunset_orange"
    case moonlightSilver = "moonlight_silver"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidBlue: return "Liquid Blue"
        case .cosmicPurple: return "Cosmic Purple"
        case .forestGreen: return "Forest Green"
        case .sunsetOrange: return "Sunset Orange"
        case .moonlightSilver: return "Moonlight Silver"
        }
    }

    var icon: String {
        switch self {
        case .liquidBlue: return "drop.fill"
        case .cosmicPurple: return "sparkles"
        case .forestGreen: return "leaf.fill"
        case .sunsetOrange: return "sun.max.fill"
        case .moonlightSilver: return "moon.stars.fill"
        }
    }

    /// Primary brand color for the theme
    var primaryColor: Color {
        switch self {
        case .liquidBlue: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .cosmicPurple: return Color(red: 0.55, green: 0.27, blue: 0.96)
        case .forestGreen: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .sunsetOrange: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .moonlightSilver: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }

    /// Secondary accent color
    var secondaryColor: Color {
        switch self {
        case .liquidBlue: return Color(red: 0.30, green: 0.69, blue: 1.0)
        case .cosmicPurple: return Color(red: 0.75, green: 0.52, blue: 0.98)
        case .forestGreen: return Color(red: 0.40, green: 0.87, blue: 0.55)
        case .sunsetOrange: return Color(red: 1.0, green: 0.78, blue: 0.35)
        case .moonlightSilver: return Color(red: 0.72, green: 0.72, blue: 0.74)
        }
    }

    /// Background gradient colors
    var backgroundGradient: [Color] {
        switch self {
        case .liquidBlue:
            return [
                Color(red: 0.05, green: 0.15, blue: 0.35),
                Color(red: 0.10, green: 0.25, blue: 0.45)
            ]
        case .cosmicPurple:
            return [
                Color(red: 0.15, green: 0.05, blue: 0.35),
                Color(red: 0.25, green: 0.15, blue: 0.45)
            ]
        case .forestGreen:
            return [
                Color(red: 0.05, green: 0.25, blue: 0.15),
                Color(red: 0.15, green: 0.35, blue: 0.25)
            ]
        case .sunsetOrange:
            return [
                Color(red: 0.35, green: 0.15, blue: 0.05),
                Color(red: 0.45, green: 0.25, blue: 0.15)
            ]
        case .moonlightSilver:
            return [
                Color(red: 0.12, green: 0.12, blue: 0.15),
                Color(red: 0.18, green: 0.18, blue: 0.22)
            ]
        }
    }

    /// Cultural diversity colors
    var culturalColors: CulturalColorPalette {
        CulturalColorPalette(
            africa: Color(red: 0.96, green: 0.65, blue: 0.14),
            asia: Color(red: 0.85, green: 0.33, blue: 0.31),
            europe: Color(red: 0.30, green: 0.69, blue: 0.31),
            americas: Color(red: 0.20, green: 0.60, blue: 0.86),
            oceania: Color(red: 0.00, green: 0.74, blue: 0.83),
            middleEast: Color(red: 0.61, green: 0.35, blue: 0.71),
            indigenous: Color(red: 0.55, green: 0.27, blue: 0.08),
            international: primaryColor
        )
    }
}

// MARK: - Cultural Color Palette

struct CulturalColorPalette {
    let africa: Color
    let asia: Color
    let europe: Color
    let americas: Color
    let oceania: Color
    let middleEast: Color
    let indigenous: Color
    let international: Color

    func color(for region: CulturalRegion) -> Color {
        switch region {
        case .africa: return africa
        case .asia: return asia
        case .europe: return europe
        case .northAmerica, .southAmerica, .caribbean: return americas
        case .oceania: return oceania
        case .middleEast, .centralAsia: return middleEast
        case .indigenous: return indigenous
        case .international: return international
        }
    }
}

// MARK: - Theme Store

@Observable
public class iOS26ThemeStore: @unchecked Sendable {
    private(set) var currentTheme: iOS26Theme = .liquidBlue
    private(set) var isSystemAppearance: Bool = true

    // Theme transition state
    private(set) var isTransitioning: Bool = false

    public init() {
        loadSavedTheme()
    }

    // MARK: - Theme Management

    func setTheme(_ theme: iOS26Theme, animated: Bool = true) {
        guard theme != currentTheme else { return }

        if animated {
            withAnimation(.smooth(duration: 0.8)) {
                isTransitioning = true
                currentTheme = theme
            }

            Task {
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                await MainActor.run {
                    isTransitioning = false
                }
            }
        } else {
            currentTheme = theme
        }

        saveTheme()
        Task { @MainActor in
            triggerHapticFeedback()
        }
    }

    func toggleSystemAppearance() {
        isSystemAppearance.toggle()
        saveTheme()
    }

    // MARK: - Computed Theme Properties

    var primaryColor: Color {
        currentTheme.primaryColor
    }

    var secondaryColor: Color {
        currentTheme.secondaryColor
    }

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: currentTheme.backgroundGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var culturalColors: CulturalColorPalette {
        currentTheme.culturalColors
    }

    // MARK: - Reading Status Colors

    func readingStatusColor(_ status: ReadingStatus) -> Color {
        switch status {
        case .wishlist: return Color.pink
        case .toRead: return primaryColor
        case .reading: return Color.orange
        case .read: return Color.green
        case .onHold: return Color.yellow
        case .dnf: return Color.red
        }
    }

    // MARK: - Glass Tinting

    func glassStint(intensity: Double = 0.3) -> Color {
        primaryColor.opacity(intensity)
    }

    func culturalGlassTint(for region: CulturalRegion, intensity: Double = 0.2) -> Color {
        culturalColors.color(for: region).opacity(intensity)
    }

    // MARK: - Persistence

    private func loadSavedTheme() {
        if let savedThemeRaw = UserDefaults.standard.object(forKey: "iOS26Theme") as? String,
           let savedTheme = iOS26Theme(rawValue: savedThemeRaw) {
            currentTheme = savedTheme
        }

        isSystemAppearance = UserDefaults.standard.bool(forKey: "iOS26SystemAppearance")
    }

    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.rawValue, forKey: "iOS26Theme")
        UserDefaults.standard.set(isSystemAppearance, forKey: "iOS26SystemAppearance")
    }

    @MainActor
    private func triggerHapticFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Theme Environment

private struct iOS26ThemeStoreKey: EnvironmentKey {
    static let defaultValue = iOS26ThemeStore()
}

extension EnvironmentValues {
    var iOS26ThemeStore: iOS26ThemeStore {
        get { self[iOS26ThemeStoreKey.self] }
        set { self[iOS26ThemeStoreKey.self] = newValue }
    }
}

public extension View {
    func iOS26ThemeStore(_ store: iOS26ThemeStore) -> some View {
        environment(\.iOS26ThemeStore, store)
    }
}

// MARK: - Theme-Aware View Modifiers

struct ThemedBackground: ViewModifier {
    @Environment(\.iOS26ThemeStore) private var themeStore

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(themeStore.backgroundGradient)
                    .ignoresSafeArea()
            }
    }
}

struct ThemedGlassEffect: ViewModifier {
    @Environment(\.iOS26ThemeStore) private var themeStore
    let variant: GlassVariant
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .glassEffect(variant, tint: themeStore.glassStint(intensity: intensity))
    }
}

struct CulturalGlassEffect: ViewModifier {
    @Environment(\.iOS26ThemeStore) private var themeStore
    let region: CulturalRegion
    let intensity: Double

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, tint: themeStore.culturalGlassTint(for: region, intensity: intensity))
    }
}

// MARK: - View Extensions for Theming

extension View {
    /// Apply themed background
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }

    /// Apply themed glass effect
    func themedGlass(_ variant: GlassVariant = .regular, intensity: Double = 0.3) -> some View {
        modifier(ThemedGlassEffect(variant: variant, intensity: intensity))
    }

    /// Apply cultural glass effect
    func culturalGlass(for region: CulturalRegion, intensity: Double = 0.2) -> some View {
        modifier(CulturalGlassEffect(region: region, intensity: intensity))
    }
}

// MARK: - Theme Picker Component

struct iOS26ThemePicker: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Namespace private var themeSelection

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Your Theme")
                .font(.title2.bold())
                .foregroundColor(.primary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(iOS26Theme.allCases) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: theme == themeStore.currentTheme,
                        namespace: themeSelection
                    ) {
                        themeStore.setTheme(theme)
                    }
                }
            }

            Divider()
                .overlay(Color.secondary.opacity(0.5))

            HStack {
                Text("Follow System Appearance")
                    .font(.subheadline)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { themeStore.isSystemAppearance },
                    set: { _ in themeStore.toggleSystemAppearance() }
                ))
                .tint(themeStore.primaryColor)
            }
        }
        .padding()
    }
}

struct ThemePreviewCard: View {
    let theme: iOS26Theme
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Theme preview circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: theme.backgroundGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Circle()
                                .fill(theme.primaryColor.opacity(0.3))
                                .blendMode(.overlay)
                        }
                        .overlay {
                            Image(systemName: theme.icon)
                                .font(.title2)
                                .foregroundColor(.white)
                        }

                    if isSelected {
                        Circle()
                            .strokeBorder(theme.primaryColor, lineWidth: 3)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .frame(width: 60, height: 60)

                Text(theme.displayName)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
        }
        .scaleEffect(isSelected ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .glassEffect(.subtle, tint: theme.primaryColor, interactive: true)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview

#Preview("Theme System") {
    NavigationStack {
        ScrollView([.vertical], showsIndicators: true) {
            VStack(spacing: 30) {
                iOS26ThemePicker()

                GlassEffectContainer {
                    VStack(spacing: 16) {
                        Text("Themed Components")
                            .font(.headline)

                        HStack(spacing: 16) {
                            Button("Primary Action") {}
                                .buttonStyle(GlassProminentButtonStyle())

                            Button("Secondary") {}
                                .buttonStyle(GlassButtonStyle())
                        }

                        Text("This content uses themed glass effects")
                            .padding()
                            .themedGlass()
                    }
                    .padding()
                }
                .padding()
            }
        }
        .themedBackground()
        .navigationTitle("Theme Preview")
        .iOS26NavigationGlass()
    }
    .iOS26ThemeStore(iOS26ThemeStore())
}