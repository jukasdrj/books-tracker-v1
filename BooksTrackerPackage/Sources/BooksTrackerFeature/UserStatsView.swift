import SwiftUI

struct UserStatsView: View {
    @Binding var selectedTimePeriod: InsightsModel.TimePeriod
    let readingStats: InsightsModel.ReadingStats

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your Stats")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Picker("Time Period", selection: $selectedTimePeriod) {
                    ForEach(InsightsModel.TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            // Stats Grid
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    StatBox(title: "Books Read", value: "\(readingStats.booksRead)")
                    StatBox(title: "Pages Read", value: "\(readingStats.pagesRead)")
                }
                HStack(spacing: 15) {
                    StatBox(title: "Avg. Pace", value: String(format: "%.1f p/day", readingStats.averagePace))
                    StatBox(title: "Avg. Rating", value: String(format: "%.1f ★", readingStats.averageRating))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

@available(iOS 17.0, *)
#Preview {
    // Create a dummy binding for the preview
    @State var timePeriod = InsightsModel.TimePeriod.thisYear
    let stats = InsightsModel.ReadingStats(booksRead: 12, pagesRead: 3456, averagePace: 11.2, averageRating: 4.3)

    return UserStatsView(selectedTimePeriod: $timePeriod, readingStats: stats)
        .padding()
}