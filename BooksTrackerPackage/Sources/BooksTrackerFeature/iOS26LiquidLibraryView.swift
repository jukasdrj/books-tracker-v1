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
    // ✅ FIX 1: Optimized SwiftData query with sorting and minimal loading
    @Query(
        filter: #Predicate<Work> { work in
            !work.userLibraryEntries.isEmpty
        },
        sort: \Work.lastModified,
        order: .reverse
    ) private var libraryWorks: [Work]
    
    // ✅ FIX 2: Simplified state management
    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var searchText = ""
    @State private var showingDiversityInsights = false
    
    // ✅ FIX 3: Performance optimizations
    @State private var cachedFilteredWorks: [Work] = []
    @State private var cachedDiversityScore: Double = 0.0
    @State private var lastSearchText = ""
    
    @Namespace private var layoutTransition
    @State private var scrollPosition = ScrollPosition()

    public init() {}

    public var body: some View {
        NavigationStack {
            mainContentView
                .searchable(text: $searchText, prompt: "Search your library")
                .onChange(of: searchText) { _, newValue in
                    updateFilteredWorks()
                }
                .onChange(of: libraryWorks) { _, _ in
                    updateFilteredWorks()
                }
                .onAppear {
                    updateFilteredWorks()
                }
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
        // ✅ FIX 4: Safe navigation with Work IDs instead of objects
        .navigationDestination(for: UUID.self) { workID in
            if let work = libraryWorks.first(where: { $0.id == workID }) {
                WorkDetailView(work: work)
            }
        }
        .sheet(isPresented: $showingDiversityInsights) {
            CulturalDiversityInsightsView(works: cachedFilteredWorks)
                .presentationDetents([.medium, .large])
                .iOS26SheetGlass()
        }
    }

    // MARK: - Main Content View

    private var mainContentView: some View {
        ZStack {
            Color.clear
                .background {
                    LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Cultural insights header
                    if !cachedFilteredWorks.isEmpty {
                        culturalInsightsHeader
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                    }

                    // Library content based on selected layout
                    Group {
                        switch selectedLayout {
                        case .floatingGrid:
                            optimizedFloatingGridLayout
                        case .adaptiveCards:
                            optimizedAdaptiveCardsLayout
                        case .liquidList:
                            optimizedLiquidListLayout
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .scrollPosition($scrollPosition)
        }
    }

    // MARK: - Optimized Layout Implementations

    @ViewBuilder
    private var optimizedFloatingGridLayout: some View {
        LazyVGrid(columns: adaptiveColumns(for: UIScreen.main.bounds.size), spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    OptimizedFloatingBookCard(work: work, namespace: layoutTransition)
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id) // ✅ Explicit ID for view recycling
            }
        }
    }

    @ViewBuilder
    private var optimizedAdaptiveCardsLayout: some View {
        LazyVGrid(columns: adaptiveColumns(for: UIScreen.main.bounds.size), spacing: 16) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    iOS26AdaptiveBookCard(work: work)
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id)
            }
        }
    }

    @ViewBuilder
    private var optimizedLiquidListLayout: some View {
        LazyVStack(spacing: 12) {
            ForEach(cachedFilteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    iOS26LiquidListRow(work: work)
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id)
            }
        }
    }

    // MARK: - Cultural Insights Header

    private var culturalInsightsHeader: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(cachedFilteredWorks.count) Books")
                            .font(.title2.bold())
                            .foregroundColor(.primary)

                        Text("Reading Goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    culturalDiversityIndicator
                }

                readingProgressOverview
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.3))
    }

    private var culturalDiversityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cachedDiversityScore > 0.3 ? .green : cachedDiversityScore > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                .glassEffect(.regular, interactive: true)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(cachedDiversityScore * 100))%")
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
                let count = cachedFilteredWorks.flatMap(\.userLibraryEntries).filter { $0.readingStatus == status }.count

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

    // MARK: - Performance Optimizations

    private func updateFilteredWorks() {
        // ✅ FIX 5: Cached filtering and diversity calculation
        let filtered: [Work]
        
        if searchText.isEmpty {
            filtered = Array(libraryWorks)
        } else {
            filtered = libraryWorks.filter { work in
                work.title.localizedCaseInsensitiveContains(searchText) ||
                work.authorNames.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Only update if actually changed
        if filtered.map(\.id) != cachedFilteredWorks.map(\.id) {
            cachedFilteredWorks = filtered
            cachedDiversityScore = calculateDiverseAuthors(for: filtered)
        }
    }

    private func calculateDiverseAuthors(for works: [Work]) -> Double {
        let allAuthors = works.flatMap(\.authors)
        guard !allAuthors.isEmpty else { return 0.0 }

        let diverseCount = allAuthors.filter { author in
            author.representsMarginalizedVoices() || author.representsIndigenousVoices()
        }.count

        return Double(diverseCount) / Double(allAuthors.count)
    }

    private func adaptiveColumns(for size: CGSize) -> [GridItem] {
        let screenWidth = size.width
        let columnCount: Int

        if screenWidth > 1000 {
            columnCount = 6
        } else if screenWidth > 800 {
            columnCount = 4
        } else if screenWidth > 600 {
            columnCount = 3
        } else {
            columnCount = 2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }
}

// MARK: - Ultra-Optimized Library View

/// ✅ CRITICAL FIXES: This version addresses all the major iOS UX issues
@MainActor
public struct UltraOptimizedLibraryView: View {
    // ✅ FIX 1: Highly optimized SwiftData query - only loads library entries
    @Query(
        filter: #Predicate<UserLibraryEntry> { entry in
            true // Get all library entries, works will be loaded lazily
        },
        sort: \UserLibraryEntry.lastModified,
        order: .reverse
    ) private var libraryEntries: [UserLibraryEntry]
    
    // ✅ FIX 2: Minimal state management
    @State private var selectedLayout: LibraryLayout = .floatingGrid
    @State private var searchText = ""
    @State private var showingDiversityInsights = false
    
    // ✅ FIX 3: Performance-optimized data source
    @State private var dataSource = OptimizedLibraryDataSource()
    @State private var filteredWorks: [Work] = []
    @State private var diversityScore: Double = 0.0
    
    @Namespace private var layoutTransition
    @State private var scrollPosition = ScrollPosition()
    
    // ✅ FIX 4: Memory management
    private let memoryHandler = MemoryPressureHandler.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            optimizedMainContent
                .searchable(text: $searchText, prompt: "Search your library")
                .task {
                    await updateData()
                }
                .onChange(of: searchText) { _, _ in
                    Task { await updateData() }
                }
                .onChange(of: libraryEntries) { _, _ in
                    Task { await updateData() }
                }
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
        .modifier(SafeWorkNavigation(
            workID: UUID(), // Will be overridden by individual NavigationLinks
            allWorks: filteredWorks
        ))
        .sheet(isPresented: $showingDiversityInsights) {
            CulturalDiversityInsightsView(works: filteredWorks)
                .presentationDetents([.medium, .large])
                .iOS26SheetGlass()
        }
        .performanceMonitor("UltraOptimizedLibraryView")
    }

    // MARK: - Optimized Main Content

    private var optimizedMainContent: some View {
        ZStack {
            Color.clear
                .background {
                    LinearGradient(
                        colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }

            if filteredWorks.isEmpty {
                emptyStateView
            } else {
                contentScrollView
            }
        }
    }

    private var contentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Insights header
                optimizedInsightsHeader
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .performanceMonitor("InsightsHeader")

                // Books grid/list
                optimizedBooksLayout
                    .padding(.horizontal)
                    .performanceMonitor("BooksLayout")
            }
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(.visible, axes: .vertical)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Books in Library")
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text("Start building your library by searching for books!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Optimized Layout Implementations

    @ViewBuilder
    private var optimizedBooksLayout: some View {
        switch selectedLayout {
        case .floatingGrid:
            ultraOptimizedGrid
        case .adaptiveCards:
            ultraOptimizedAdaptiveGrid
        case .liquidList:
            ultraOptimizedList
        }
    }

    private var ultraOptimizedGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    OptimizedFloatingBookCard(
                        work: work, 
                        namespace: layoutTransition
                    )
                    .performanceMonitor("BookCard-\(work.title)")
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id)
            }
        }
    }

    private var ultraOptimizedAdaptiveGrid: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    iOS26AdaptiveBookCard(work: work)
                        .performanceMonitor("AdaptiveCard-\(work.title)")
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id)
            }
        }
    }

    private var ultraOptimizedList: some View {
        LazyVStack(spacing: 12) {
            ForEach(filteredWorks, id: \.id) { work in
                NavigationLink(value: work.id) {
                    iOS26LiquidListRow(work: work)
                        .performanceMonitor("ListRow-\(work.title)")
                }
                .buttonStyle(BookCardButtonStyle())
                .id(work.id)
            }
        }
    }

    // MARK: - Optimized Insights Header

    private var optimizedInsightsHeader: some View {
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

                    optimizedDiversityIndicator
                }

                optimizedProgressOverview
            }
            .padding()
        }
        .glassEffect(.regular, tint: .blue.opacity(0.3))
    }

    private var optimizedDiversityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(diversityScore > 0.3 ? .green : diversityScore > 0.15 ? .orange : .red)
                .frame(width: 12, height: 12)
                .glassEffect(.regular, interactive: true)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(diversityScore * 100))%")
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

    private var optimizedProgressOverview: some View {
        HStack(spacing: 16) {
            ForEach(ReadingStatus.allCases.prefix(4), id: \.self) { status in
                let count = libraryEntries.filter { $0.readingStatus == status }.count

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

    // MARK: - Performance Optimizations

    private var adaptiveColumns: [GridItem] {
        let screenWidth = UIScreen.main.bounds.width
        let columnCount: Int

        if screenWidth > 1000 {
            columnCount = 6
        } else if screenWidth > 800 {
            columnCount = 4
        } else if screenWidth > 600 {
            columnCount = 3
        } else {
            columnCount = 2
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    @MainActor
    private func updateData() async {
        // Convert library entries to works efficiently
        let works = libraryEntries.compactMap(\.work)
        
        let filtered = dataSource.getFilteredWorks(
            from: works,
            searchText: searchText
        )
        
        // Update diversity score efficiently
        let newDiversityScore = calculateDiversityScore(for: filtered)
        
        // Only update if changed to prevent unnecessary re-renders
        if filtered.map(\.id) != filteredWorks.map(\.id) {
            filteredWorks = filtered
        }
        
        if abs(newDiversityScore - diversityScore) > 0.01 {
            diversityScore = newDiversityScore
        }
    }

    private func calculateDiversityScore(for works: [Work]) -> Double {
        let allAuthors = works.flatMap(\.authors)
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
            ScrollView {
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
                .scrollTargetLayout()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
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

// MARK: - Book Card Button Style

struct BookCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    iOS26LiquidLibraryView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}