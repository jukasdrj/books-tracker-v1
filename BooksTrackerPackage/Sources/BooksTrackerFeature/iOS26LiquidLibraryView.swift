import SwiftUI
import SwiftData

// MARK: - Library Layout Options

enum LibraryLayout: String, CaseIterable, Identifiable {
    case floatingGrid = "floating_grid"
    case adaptiveCards = "adaptive_cards"
    case liquidList = "liquid_list"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floatingGrid: return "Floating Grid"
        case .adaptiveCards: return "Adaptive Cards"
        case .liquidList: return "Liquid List"
        }
    }

    var icon: String {
        switch self {
        case .floatingGrid: return "grid"
        case .adaptiveCards: return "rectangle.grid.2x2"
        case .liquidList: return "list.bullet"
        }
    }
}

@MainActor
public struct iOS26LiquidLibraryView: View {
    @Query private var works: [Work]
    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var showingFilters = false
    @State private var searchText = ""
    @Namespace private var layoutTransition

    // Cultural diversity insights
    @State private var showingDiversityInsights = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background with glass extension
                Color.clear
                    .background {
                        LinearGradient(
                            colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    }

                // Main content
                ScrollView([.vertical], showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        // Cultural insights header
                        if !works.isEmpty {
                            culturalInsightsHeader
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                        }

                        // Library content based on selected layout
                        Group {
                            switch selectedLayout {
                            case .floatingGrid:
                                floatingGridLayout
                            case .adaptiveCards:
                                adaptiveCardsLayout
                            case .liquidList:
                                liquidListLayout
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .searchable(text: $searchText, prompt: "Search your library")
            }
            .navigationTitle("My Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Insights") {
                        showingDiversityInsights.toggle()
                    }
                    .buttonStyle(GlassButtonStyle())

                    Menu {
                        Picker("Layout", selection: $selectedLayout.animation(.smooth)) {
                            ForEach(LibraryLayout.allCases, id: \.self) { layout in
                                Label(layout.displayName, systemImage: layout.icon)
                                    .tag(layout)
                            }
                        }
                    } label: {
                        Image(systemName: selectedLayout.icon)
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .navigationDestination(for: Work.self) { work in
                WorkDetailView(work: work)
            }
            .sheet(isPresented: $showingDiversityInsights) {
                CulturalDiversityInsightsView(works: filteredWorks)
                    .presentationDetents([.medium, .large])
                    .iOS26SheetGlass()
            }
        }
    }

    // MARK: - Cultural Insights Header

    private var culturalInsightsHeader: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(filteredWorks.count) Books")
                            .font(.title2.bold())
                            .foregroundColor(.primary)

                        Text("Reading Goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Cultural diversity indicator
                    culturalDiversityIndicator
                }

                // Reading progress overview
                readingProgressOverview
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.3))
        .glassEffectID("insights-header", in: layoutTransition)
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 8) {
            let diverseAuthors = calculateDiverseAuthors()

            Circle()
                .fill(diverseAuthors > 0.3 ? .green : diverseAuthors > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                .glassEffect(.regular, interactive: true)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(diverseAuthors * 100))%")
                    .font(.headline.bold())
                    .foregroundColor(.primary)

                Text("Diverse")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onTapGesture {
            showingDiversityInsights.toggle()
        }
    }

    private var readingProgressOverview: some View {
        HStack(spacing: 16) {
            ForEach(ReadingStatus.allCases.prefix(4), id: \.self) { status in
                let count = filteredWorks.flatMap(\.userLibraryEntries).filter { $0.readingStatus == status }.count

                VStack(spacing: 4) {
                    Image(systemName: status.systemImage)
                        .font(.title3)
                        .foregroundColor(status.color)
                        .glassEffect(.regular, interactive: true)

                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundColor(.primary)

                    Text(status.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Layout Implementations

    @ViewBuilder
    private var floatingGridLayout: some View {
        GeometryReader { geometry in
            iOS26FluidGridSystem(
                items: filteredWorks,
                columns: adaptiveColumns(for: geometry.size),
                spacing: 20
            ) { work in
                NavigationLink(value: work) {
                    iOS26FloatingBookCard(
                        work: work,
                        namespace: layoutTransition
                    )
                }
                .buttonStyle(.plain)
                .glassEffectID("book-\(work.id)", in: layoutTransition)
            }
        }
    }

    @ViewBuilder
    private var adaptiveCardsLayout: some View {
        GeometryReader { geometry in
            LazyVGrid(columns: adaptiveColumns(for: geometry.size), spacing: 16) {
                ForEach(filteredWorks, id: \.id) { work in
                    NavigationLink(value: work) {
                        iOS26AdaptiveBookCard(work: work)
                    }
                    .buttonStyle(.plain)
                    .glassEffectID("adaptive-\(work.id)", in: layoutTransition)
                }
            }
        }
    }

    @ViewBuilder
    private var liquidListLayout: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work) {
                    iOS26LiquidListRow(work: work)
                }
                .buttonStyle(.plain)
                .glassEffectID("list-\(work.id)", in: layoutTransition)
            }
        }
    }

    // MARK: - Helper Properties

    private var filteredWorks: [Work] {
        if searchText.isEmpty {
            return works
        }
        return works.filter { work in
            work.title.localizedCaseInsensitiveContains(searchText) ||
            work.authorNames.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let screenWidth = size.width
        let columnCount: Int

        if screenWidth > 1000 { // iPad Pro
            columnCount = 6
        } else if screenWidth > 800 { // iPad
            columnCount = 4
        } else if screenWidth > 600 { // Large phone landscape
            columnCount = 3
        } else { // Phone portrait - V1.0 spec
            columnCount = 2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    // MARK: - Cultural Analytics

    private func calculateDiverseAuthors() -> Double {
        let allAuthors = filteredWorks.flatMap(\.authors)
        guard !allAuthors.isEmpty else { return 0.0 }

        let diverseCount = allAuthors.filter { author in
            author.representsMarginalizedVoices() || author.representsIndigenousVoices()
        }.count

        return Double(diverseCount) / Double(allAuthors.count)
    }
}

// MARK: - Cultural Diversity Insights Sheet

struct CulturalDiversityInsightsView: View {
    let works: [Work]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.vertical], showsIndicators: true) {
                LazyVStack(spacing: 20) {
                    // Diversity metrics
                    diversityMetricsSection

                    // Cultural regions breakdown
                    culturalRegionsSection

                    // Author gender distribution
                    genderDistributionSection

                    // Reading goals progress
                    readingGoalsSection
                }
                .padding()
            }
            .navigationTitle("Cultural Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(GlassProminentButtonStyle())
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var diversityMetricsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diversity Overview")
                    .font(.headline.bold())

                let metrics = calculateDiversityMetrics()

                HStack(spacing: 20) {
                    MetricView(
                        title: "Diverse Voices",
                        value: "\(Int(metrics.diversePercentage * 100))%",
                        color: metrics.diversePercentage > 0.3 ? .green : .orange
                    )

                    MetricView(
                        title: "Cultural Regions",
                        value: "\(metrics.regionCount)",
                        color: .blue
                    )

                    MetricView(
                        title: "Languages",
                        value: "\(metrics.languageCount)",
                        color: .purple
                    )
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.2))
    }

    private var culturalRegionsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cultural Regions")
                    .font(.headline.bold())

                let regionStats = calculateRegionStatistics()

                ForEach(regionStats.sorted(by: { $0.value > $1.value }), id: \.key) { region, count in
                    HStack {
                        Text(region.emoji)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.displayName)
                                .font(.body.bold())

                            Text("\(count) books")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("\(Int(Double(count) / Double(works.count) * 100))%")
                            .font(.callout.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .green.opacity(0.2))
    }

    private var genderDistributionSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Author Gender Distribution")
                    .font(.headline.bold())

                let genderStats = calculateGenderStatistics()

                ForEach(genderStats.sorted(by: { $0.value > $1.value }), id: \.key) { gender, count in
                    HStack {
                        Image(systemName: gender.icon)
                            .font(.title3)
                            .foregroundColor(.primary)
                            .frame(width: 24)

                        Text(gender.displayName)
                            .font(.body)

                        Spacer()

                        Text("\(count)")
                            .font(.callout.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .purple.opacity(0.2))
    }

    private var readingGoalsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reading Goals Progress")
                    .font(.headline.bold())

                // Placeholder for reading goals - implement based on user's goals
                VStack(spacing: 8) {
                    ProgressView(value: 0.65) {
                        Text("Diverse Authors Goal")
                            .font(.subheadline)
                    }
                    .tint(.green)

                    ProgressView(value: 0.8) {
                        Text("Annual Reading Goal")
                            .font(.subheadline)
                    }
                    .tint(.blue)
                }
            }
            .padding()
        }
        .glassEffect(.regular, tint: .orange.opacity(0.2))
    }

    // MARK: - Helper Methods

    private func calculateDiversityMetrics() -> (diversePercentage: Double, regionCount: Int, languageCount: Int) {
        let allAuthors = works.flatMap(\.authors)
        let diverseCount = allAuthors.filter { $0.representsMarginalizedVoices() }.count
        let diversePercentage = allAuthors.isEmpty ? 0.0 : Double(diverseCount) / Double(allAuthors.count)

        let regions = Set(allAuthors.compactMap(\.culturalRegion))
        let languages = Set(works.compactMap(\.originalLanguage))

        return (diversePercentage, regions.count, languages.count)
    }

    private func calculateRegionStatistics() -> [CulturalRegion: Int] {
        let allAuthors = works.flatMap(\.authors)
        var regionCounts: [CulturalRegion: Int] = [:]

        for author in allAuthors {
            if let region = author.culturalRegion {
                regionCounts[region, default: 0] += 1
            }
        }

        return regionCounts
    }

    private func calculateGenderStatistics() -> [AuthorGender: Int] {
        let allAuthors = works.flatMap(\.authors)
        var genderCounts: [AuthorGender: Int] = [:]

        for author in allAuthors {
            genderCounts[author.gender, default: 0] += 1
        }

        return genderCounts
    }
}

// MARK: - Metric View Component

struct MetricView: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    iOS26LiquidLibraryView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}