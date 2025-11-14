import SwiftUI

struct ConfidenceExplanationSheet: View {
    let confidence: Double
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiConfidenceThreshold") private var threshold: Double = 0.6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confidence Score: \(Int(confidence * 100))%")
                            .font(.title2.bold())

                        Text(confidenceDescription)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What This Means")
                            .font(.headline)

                        if confidence >= 0.8 {
                            Label("High confidence - Book automatically added to library", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if confidence >= threshold {
                            Label("Medium confidence - Added with review recommended", systemImage: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                        } else {
                            Label("Low confidence - Sent to review queue for verification", systemImage: "questionmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How We Calculate Confidence")
                            .font(.headline)

                        Text("Our AI analyzes book spine images using Google Gemini 2.0 Flash. Confidence is based on:")

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Text clarity in the image", systemImage: "text.magnifyingglass")
                            Label("Match quality with book databases", systemImage: "books.vertical")
                            Label("Consistency across multiple detections", systemImage: "checkmark.seal")
                        }
                        .font(.callout)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("About Confidence Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    var confidenceDescription: String {
        switch confidence {
        case 0.8...1.0:
            "This is a high-confidence detection. The AI is very certain about the title and author."
        case threshold..<0.8:
            "This is a medium-confidence detection. The book was added, but you may want to verify details."
        default:
            "This is a low-confidence detection. Please review and correct the title or author if needed."
        }
    }
}
