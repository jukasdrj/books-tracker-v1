import SwiftUI

@available(iOS 26.0, *)
public struct GlassCard<Content: View>: View {
    let title: String?
    let icon: String?
    let content: Content

    public init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || icon != nil {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    if let title {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    }
}

@available(iOS 26.0, *)
#Preview("GlassCard") {
    VStack(spacing: 20) {
        GlassCard(title: "Representation", icon: "chart.pie") {
            Text("Preview content goes here.")
                .foregroundStyle(.secondary)
        }
        GlassCard {
            Text("No header variant")
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(.regularMaterial)
}
