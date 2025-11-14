import SwiftUI
import SwiftData

struct AIConfidenceSettingsView: View {
    @AppStorage("aiConfidenceThreshold") private var threshold: Double = 0.6
    @Environment(\.modelContext) private var modelContext

    var affectedBooksCount: Int {
        // Calculate how many books would be affected by threshold change
        let predicate = #Predicate<UserLibraryEntry> { entry in
            (entry.aiConfidence ?? 1.0) < threshold
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Confidence Threshold: \(Int(threshold * 100))%")
                        .font(.headline)

                    Slider(value: $threshold, in: 0.5...0.8, step: 0.05)

                    HStack {
                        Text("Permissive (50%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Strict (80%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("AI Confidence Threshold")
            } footer: {
                Text("Books detected with confidence below \(Int(threshold * 100))% will be sent to the review queue for manual verification. Currently, \(affectedBooksCount) books in your library fall below this threshold.")
            }

            Section {
                Link("Learn About Confidence Scores", destination: URL(string: "https://help.bookstrack.app/ai-confidence")!)
            }
        }
        .navigationTitle("AI Confidence")
    }
}
