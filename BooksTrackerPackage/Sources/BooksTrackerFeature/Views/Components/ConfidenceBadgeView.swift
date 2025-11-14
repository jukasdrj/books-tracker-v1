import SwiftUI

struct ConfidenceBadgeView: View {
    let confidence: Double
    @AppStorage("aiConfidenceThreshold") private var threshold: Double = 0.6

    var body: some View {
        HStack(spacing: 4) {
            confidenceIcon
            Text("\(Int(confidence * 100))%")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.2))
        .foregroundColor(confidenceColor)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var confidenceIcon: Image {
        switch confidence {
        case 0.8...1.0: return Image(systemName: "checkmark.circle.fill")
        case threshold..<0.8: return Image(systemName: "exclamationmark.circle.fill")
        default: return Image(systemName: "questionmark.circle.fill")
        }
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.8...1.0: return .green
        case threshold..<0.8: return .orange
        default: return .red
        }
    }

    private var accessibilityLabel: String {
        let confidencePercentage = Int(confidence * 100)
        let level: String
        switch confidence {
        case 0.8...1.0:
            level = "High"
        case threshold..<0.8:
            level = "Medium"
        default:
            level = "Low"
        }
        return "\(level) confidence, \(confidencePercentage) percent"
    }
}
