import SwiftUI

// MARK: - iOS 26 Liquid Glass Effects System

/// Main container for managing multiple glass effects with proper spacing and blending
struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .background {
                // Progressive glass background that enhances contained effects
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.1)
            }
    }
}

// MARK: - Progressive Glass Effects

@available(iOS 26.0, *)
struct ProgressiveGlassEffect: ViewModifier {
    let variant: GlassVariant
    let shape: AnyInsettableShape
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: shape)
            .if(isInteractive) { view in
                view.contentShape(shape)
            }
    }

    // Fallback for when glassEffect is not available (though we're targeting iOS 26+)
    private var fallbackBody: some View {
        // This should never be called since we're iOS 26+ only
        EmptyView()
    }
}

// MARK: - Glass Variants

enum GlassVariant {
    case regular
    case prominent
    case subtle

    // Using string-based glass effect styles for iOS 26
    var glassStyleName: String {
        switch self {
        case .regular: return "regular"
        case .prominent: return "prominent"
        case .subtle: return "subtle"
        }
    }

    var opacity: Double {
        switch self {
        case .regular: return 0.8
        case .prominent: return 0.95
        case .subtle: return 0.5
        }
    }

    var blur: CGFloat {
        switch self {
        case .regular: return 20
        case .prominent: return 30
        case .subtle: return 10
        }
    }
}

// MARK: - Glass Button Styles

@available(iOS 26.0, *)
struct GlassButtonStyle: ButtonStyle {
    let variant: GlassVariant
    let tint: Color?

    init(variant: GlassVariant = .regular, tint: Color? = nil) {
        self.variant = variant
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular, tint: tint ?? .clear, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

@available(iOS 26.0, *)
struct GlassProminentButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = .blue) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(.prominent, tint: tint, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - iOS 26 Navigation Glass

struct iOS26NavigationGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .background {
                // Extends content under navigation
                Rectangle()
                    .fill(.clear)
                    .background(.ultraThinMaterial.opacity(0.1))
                    .ignoresSafeArea()
            }
    }
}

// MARK: - Sheet Glass Presentation

struct iOS26SheetGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(.ultraThinMaterial)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

// MARK: - View Extensions

extension View {
    /// Apply the basic iOS 26 glass effect
    @available(iOS 26.0, *)
    func glassEffect(
        _ variant: GlassVariant = .regular,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: 16),
        interactive: Bool = false
    ) -> some View {
        modifier(ProgressiveGlassEffect(
            variant: variant,
            shape: AnyInsettableShape(shape),
            isInteractive: interactive
        ))
    }

    /// Apply glass effect with custom tint
    @available(iOS 26.0, *)
    func glassEffect(
        _ variant: GlassVariant = .regular,
        tint: Color,
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: 16),
        interactive: Bool = false
    ) -> some View {
        modifier(ProgressiveGlassEffect(
            variant: variant,
            shape: AnyInsettableShape(shape),
            isInteractive: interactive
        ))
        .overlay {
            shape
                .fill(tint.opacity(0.1))
                .blendMode(.overlay)
                .allowsHitTesting(false)  // Allow touches through decorative overlay
        }
    }

    /// Apply iOS 26 navigation glass
    func iOS26NavigationGlass() -> some View {
        modifier(iOS26NavigationGlassModifier())
    }

    /// Apply iOS 26 sheet glass
    func iOS26SheetGlass() -> some View {
        modifier(iOS26SheetGlassModifier())
    }

    /// Conditional view modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Button Style Extensions

@available(iOS 26.0, *)
extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle {
        GlassButtonStyle()
    }

    static func glass(variant: GlassVariant = .regular, tint: Color? = nil) -> GlassButtonStyle {
        GlassButtonStyle(variant: variant, tint: tint)
    }
}

@available(iOS 26.0, *)
extension ButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle {
        GlassProminentButtonStyle()
    }

    static func glassProminent(tint: Color = .blue) -> GlassProminentButtonStyle {
        GlassProminentButtonStyle(tint: tint)
    }
}

// MARK: - Type-erased Shape

struct AnyInsettableShape: InsettableShape, @unchecked Sendable {
    private let _path: (CGRect) -> Path
    private let _inset: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        _path = { shape.path(in: $0) }
        _inset = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        _inset(amount)
    }
}

// MARK: - Morphing Transitions with Namespace

struct GlassMorphTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .matchedGeometryEffect(id: id, in: namespace, properties: .frame)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 1.2).combined(with: .opacity)
            ))
    }
}

extension View {
    func glassEffectID(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(GlassMorphTransition(id: id, namespace: namespace))
    }
}

// MARK: - Preview Helpers

@available(iOS 26.0, *)
#Preview("Glass Effects") {
    ScrollView {
        VStack(spacing: 30) {
            Text("iOS 26 Liquid Glass Effects")
                .font(.title.bold())
                .padding()

            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 16) {
                    Text("Standard Glass Effect")
                        .padding()
                        .glassEffect()

                    Text("Prominent Glass with Tint")
                        .padding()
                        .glassEffect(.prominent, tint: .blue)

                    Text("Interactive Glass")
                        .padding()
                        .glassEffect(.regular, interactive: true)

                    HStack(spacing: 16) {
                        Button("Glass Button") {}
                            .buttonStyle(GlassButtonStyle())

                        Button("Prominent") {}
                            .buttonStyle(GlassProminentButtonStyle())
                    }
                }
                .padding()
            }
            .padding()
        }
    }
    .background(.regularMaterial)
}