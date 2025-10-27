import SwiftUI
import Charts

struct DiversityInsightsView: View {
    let authorGenderDistribution: [AuthorGender: Int]
    let culturalRegionDistribution: [CulturalRegion: Int]
    let originalLanguageDistribution: [String: Int]

    private var totalBooks: Int {
        authorGenderDistribution.values.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Diversity Insights")
                .font(.title2)
                .fontWeight(.bold)

            if totalBooks > 0 {
                // Author Gender Distribution
                VStack(alignment: .leading, spacing: 12) {
                    Text("Author Gender")
                        .font(.headline)
                    Chart(authorGenderDistribution.sorted(by: { $0.key.displayName < $1.key.displayName }), id: \.key) { gender, count in
                        BarMark(
                            x: .value("Gender", gender.displayName),
                            y: .value("Count", count)
                        )
                        .foregroundStyle(by: .value("Gender", gender.displayName))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                }

                // Cultural Region Distribution
                VStack(alignment: .leading, spacing: 12) {
                    Text("Author Cultural Region")
                        .font(.headline)
                    Chart(culturalRegionDistribution.sorted(by: { $0.key.displayName < $1.key.displayName }), id: \.key) { region, count in
                        BarMark(
                            x: .value("Region", region.displayName),
                            y: .value("Count", count)
                        )
                        .foregroundStyle(by: .value("Region", region.displayName))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                }

                // Original Language Distribution
                VStack(alignment: .leading, spacing: 12) {
                    Text("Original Language")
                        .font(.headline)
                    Chart(originalLanguageDistribution.sorted(by: { $0.key < $1.key }), id: \.key) { language, count in
                        BarMark(
                            x: .value("Language", language),
                            y: .value("Count", count)
                        )
                        .foregroundStyle(by: .value("Language", language))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                }
            } else {
                VStack {
                    Spacer()
                    Text("No diversity data available.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 300)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}