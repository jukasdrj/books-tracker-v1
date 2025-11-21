import SwiftUI

@available(iOS 16.0, *)
public struct AuroraGradient: View {
    public enum Direction { case horizontal, vertical, radial }
    let direction: Direction
    let intensity: Double

    public init(direction: Direction = .horizontal, intensity: Double = 1.0) {
        self.direction = direction
        self.intensity = intensity
    }

    public var body: some View {
        Group {
            switch direction {
            case .horizontal:
                LinearGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .vertical:
                LinearGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .radial:
                RadialGradient(
                    colors: colors.map { $0.opacity(intensity) },
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        }
        .drawingGroup()
    }

    private var colors: [Color] {
        [
            Color(red: 0.42, green: 0.39, blue: 1.00), // Indigo
            Color(red: 0.00, green: 0.82, blue: 1.00), // Cyan
            Color(red: 0.07, green: 0.89, blue: 0.64)  // Teal
        ]
    }
}

@available(iOS 16.0, *)
#Preview("AuroraGradient") {
    VStack(spacing: 20) {
        Rectangle().fill(AuroraGradient(direction: .horizontal)).frame(height: 80)
        Rectangle().fill(AuroraGradient(direction: .vertical)).frame(height: 80)
        Circle().fill(AuroraGradient(direction: .radial)).frame(height: 120)
    }
    .padding()
}
