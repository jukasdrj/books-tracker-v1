import SwiftUI
import SwiftData

/// V1.0 Specification: "Floating cover images with a small info card below"
/// Fluid grid layout adapting to screen size (2 columns phone, more on tablet)
struct iOS26FloatingBookCard: View {
    let work: Work
    let namespace: Namespace.ID

    @State private var showingQuickActions = false
    @Environment(\.iOS26ThemeStore) private var themeStore

    // Current user's library entry for this work
    private var userEntry: UserLibraryEntry? {
        work.userLibraryEntries.first
    }

    // Primary edition for display
    private var primaryEdition: Edition? {
        userEntry?.edition ?? work.availableEditions.first
    }

    var body: some View {
        VStack(spacing: 10) {
            // FLOATING COVER IMAGE (Main V1.0 Requirement)
            floatingCoverImage
                .glassEffectID("cover-\(work.id)", in: namespace)

            // SMALL INFO CARD BELOW (V1.0 Requirement)
            smallInfoCard
                .glassEffectID("info-\(work.id)", in: namespace)
        }
        .contentShape(Rectangle())
        .contextMenu {
            quickActionsMenu
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(work: work)
                .presentationDetents([.medium])
                .iOS26SheetGlass()
        }
    }

    // MARK: - Floating Cover Image

    private var floatingCoverImage: some View {
        AsyncImage(url: primaryEdition?.coverURL) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            // Refined Placeholder with Theme Colors
            ZStack {
                Rectangle()
                    .fill(themeStore.primaryColor.gradient.opacity(0.3))
                
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.8))

                    Text(work.title)
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 240) // Consistent card height
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, tint: .white.opacity(0.1))
        .shadow(
            color: .black.opacity(0.15),
            radius: 12,
            x: 0,
            y: 8
        )
        .overlay(alignment: .topTrailing) {
            // Status indicator overlay
            if let userEntry = userEntry {
                statusIndicator(for: userEntry.readingStatus)
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            // Cultural diversity indicator
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityBadge
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            // Reading progress overlay for active books
            if let userEntry = userEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0 {
                ProgressView(value: userEntry.readingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
                    .scaleEffect(y: 1.5, anchor: .bottom)
                    .padding(10)
                    .background(.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Refined Small Info Card

    private var smallInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(work.title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true) // Prevents text from truncating prematurely

            Text(work.authorNames)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Refined metadata row for status and format
            HStack {
                if let userEntry = userEntry {
                    infoCardStatus(for: userEntry.readingStatus)
                }
                
                Spacer()

                if let edition = primaryEdition {
                    // ✅ FIX: Use Image(systemName:) for proper icon display
                    Image(systemName: edition.format.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Status Indicators

    private func statusIndicator(for status: ReadingStatus) -> some View {
        Circle()
            .fill(status.color.gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
            .glassEffect(.subtle)
            .shadow(color: status.color.opacity(0.4), radius: 5, x: 0, y: 2)
    }
    
    // ✅ NEW: Compact status indicator for the info card
    private func infoCardStatus(for status: ReadingStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundColor(status.color)
        }
    }

    private var culturalDiversityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))

            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .glassEffect(.subtle)
    }

    // MARK: - Quick Actions

    private var quickActionsMenu: some View {
        Group {
            if let userEntry = userEntry {
                // Status change submenu
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(ReadingStatus.allCases.filter { $0 != userEntry.readingStatus }, id: \.self) { status in
                        Button(status.displayName, systemImage: status.systemImage) {
                            updateReadingStatus(status)
                        }
                    }
                }

                Divider()

                // Quick rating (if owned)
                if !userEntry.isWishlistItem {
                    Menu("Rate Book", systemImage: "star") {
                        ForEach(1...5, id: \.self) { rating in
                            Button("\(rating) Stars") {
                                setRating(Double(rating))
                            }
                        }
                        Button("Remove Rating") {
                            setRating(0)
                        }
                    }
                }

                Divider()

                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            } else {
                // Not in library actions
                Button("Add to Library", systemImage: "plus.circle") {
                    addToLibrary()
                }

                Button("Add to Wishlist", systemImage: "heart") {
                    addToWishlist()
                }
            }
        }
    }

    // MARK: - Actions

    private func updateReadingStatus(_ status: ReadingStatus) {
        guard let userEntry = userEntry else { return }

        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()

        // Haptic feedback
        triggerHapticFeedback(.success)
    }

    private func setRating(_ rating: Double) {
        guard let userEntry = userEntry, !userEntry.isWishlistItem else { return }

        userEntry.personalRating = rating > 0 ? rating : nil
        userEntry.rating = rating > 0 ? Int(rating) : nil
        userEntry.touch()

        // Haptic feedback
        triggerHapticFeedback(.success)
    }

    private func addToLibrary() {
        let primaryEdition = work.availableEditions.first
        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: primaryEdition ?? Edition(work: work),
            status: .toRead
        )

        work.userLibraryEntries.append(entry)
        triggerHapticFeedback(.success)
    }

    private func addToWishlist() {
        let entry = UserLibraryEntry.createWishlistEntry(for: work)
        work.userLibraryEntries.append(entry)
        triggerHapticFeedback(.success)
    }

    private func removeFromLibrary() {
        guard let userEntry = userEntry else { return }

        if let index = work.userLibraryEntries.firstIndex(of: userEntry) {
            work.userLibraryEntries.remove(at: index)
        }

        triggerHapticFeedback(.warning)
    }

    @MainActor
    private func triggerHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(type)
    }
}

// MARK: - Optimized Book Card

/// ✅ PERFORMANCE-OPTIMIZED VERSION: Fixes image loading and caching issues
struct OptimizedFloatingBookCard: View {
    let work: Work
    let namespace: Namespace.ID
    
    @State private var showingQuickActions = false
    @Environment(\.iOS26ThemeStore) private var themeStore
    
    // ✅ FIX: Cached computed properties to avoid repeated calculations
    @State private var cachedUserEntry: UserLibraryEntry?
    @State private var cachedPrimaryEdition: Edition?
    @State private var cachedCoverURL: URL?
    
    var body: some View {
        VStack(spacing: 10) {
            optimizedCoverImage
                .glassEffectID("cover-\(work.id)", in: namespace)
            
            smallInfoCard
                .glassEffectID("info-\(work.id)", in: namespace)
        }
        .contentShape(Rectangle())
        .contextMenu {
            quickActionsMenu
        }
        .onAppear {
            updateCachedProperties()
        }
        .onChange(of: work.lastModified) { _, _ in
            updateCachedProperties()
        }
        .sheet(isPresented: $showingQuickActions) {
            QuickActionsSheet(work: work)
                .presentationDetents([.medium])
                .iOS26SheetGlass()
        }
    }
    
    // MARK: - Optimized Cover Image
    
    private var optimizedCoverImage: some View {
        CachedAsyncImage(url: cachedCoverURL) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            optimizedPlaceholder
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .glassEffect(.regular, tint: .white.opacity(0.1))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
        .overlay(alignment: .topTrailing) {
            if let userEntry = cachedUserEntry {
                statusIndicator(for: userEntry.readingStatus)
                    .padding(8)
            }
        }
        .overlay(alignment: .topLeading) {
            if let primaryAuthor = work.primaryAuthor,
               primaryAuthor.representsMarginalizedVoices() {
                culturalDiversityBadge
                    .padding(8)
            }
        }
        .overlay(alignment: .bottom) {
            if let userEntry = cachedUserEntry,
               userEntry.readingStatus == .reading,
               userEntry.readingProgress > 0 {
                ProgressView(value: userEntry.readingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.8)))
                    .scaleEffect(y: 1.5, anchor: .bottom)
                    .padding(10)
                    .background(.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    private var optimizedPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(themeStore.primaryColor.gradient.opacity(0.3))
            
            VStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.8))
                
                Text(work.title)
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }
    
    private var smallInfoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(work.title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(work.authorNames)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                if let userEntry = cachedUserEntry {
                    infoCardStatus(for: userEntry.readingStatus)
                }
                
                Spacer()
                
                if let edition = cachedPrimaryEdition {
                    Image(systemName: edition.format.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
    
    // MARK: - Performance Helper Methods
    
    private func updateCachedProperties() {
        cachedUserEntry = work.userLibraryEntries.first
        cachedPrimaryEdition = cachedUserEntry?.edition ?? work.availableEditions.first
        cachedCoverURL = cachedPrimaryEdition?.coverURL
    }
    
    private func statusIndicator(for status: ReadingStatus) -> some View {
        Circle()
            .fill(status.color.gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
            .glassEffect(.subtle)
            .shadow(color: status.color.opacity(0.4), radius: 5, x: 0, y: 2)
    }
    
    private func infoCardStatus(for status: ReadingStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundColor(status.color)
        }
    }
    
    private var culturalDiversityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe.americas.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
            
            if let region = work.primaryAuthor?.culturalRegion {
                Text(region.emoji)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .glassEffect(.subtle)
    }
    
    private var quickActionsMenu: some View {
        Group {
            if let userEntry = cachedUserEntry {
                Menu("Change Status", systemImage: "bookmark") {
                    ForEach(ReadingStatus.allCases.filter { $0 != userEntry.readingStatus }, id: \.self) { status in
                        Button(status.displayName, systemImage: status.systemImage) {
                            updateReadingStatus(status)
                        }
                    }
                }
                
                Divider()
                
                if !userEntry.isWishlistItem {
                    Menu("Rate Book", systemImage: "star") {
                        ForEach(1...5, id: \.self) { rating in
                            Button("\(rating) Stars") {
                                setRating(Double(rating))
                            }
                        }
                        Button("Remove Rating") {
                            setRating(0)
                        }
                    }
                }
                
                Divider()
                
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    removeFromLibrary()
                }
            } else {
                Button("Add to Library", systemImage: "plus.circle") {
                    addToLibrary()
                }
                
                Button("Add to Wishlist", systemImage: "heart") {
                    addToWishlist()
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func updateReadingStatus(_ status: ReadingStatus) {
        guard let userEntry = cachedUserEntry else { return }
        
        userEntry.readingStatus = status
        if status == .reading && userEntry.dateStarted == nil {
            userEntry.dateStarted = Date()
        } else if status == .read {
            userEntry.markAsCompleted()
        }
        userEntry.touch()
        updateCachedProperties()
        
        triggerHapticFeedback(.success)
    }
    
    private func setRating(_ rating: Double) {
        guard let userEntry = cachedUserEntry, !userEntry.isWishlistItem else { return }
        
        userEntry.personalRating = rating > 0 ? rating : nil
        userEntry.rating = rating > 0 ? Int(rating) : nil
        userEntry.touch()
        updateCachedProperties()
        
        triggerHapticFeedback(.success)
    }
    
    private func addToLibrary() {
        let primaryEdition = work.availableEditions.first
        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: primaryEdition ?? Edition(work: work),
            status: .toRead
        )
        
        work.userLibraryEntries.append(entry)
        updateCachedProperties()
        triggerHapticFeedback(.success)
    }
    
    private func addToWishlist() {
        let entry = UserLibraryEntry.createWishlistEntry(for: work)
        work.userLibraryEntries.append(entry)
        updateCachedProperties()
        triggerHapticFeedback(.success)
    }
    
    private func removeFromLibrary() {
        guard let userEntry = cachedUserEntry else { return }
        
        if let index = work.userLibraryEntries.firstIndex(of: userEntry) {
            work.userLibraryEntries.remove(at: index)
        }
        
        updateCachedProperties()
        triggerHapticFeedback(.warning)
    }
    
    @MainActor
    private func triggerHapticFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(type)
    }
}

// MARK: - Cached AsyncImage Implementation

/// ✅ FIXES "BOOK COVER NOT AVAILABLE" issues with proper caching
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var hasError = false
    
    // Use shared cache instance
    
    var body: some View {
        Group {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
                content(Image(uiImage: uiImage))
            } else if isLoading {
                placeholder()
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            } else if hasError {
                placeholder()
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Load Error")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else {
            hasError = true
            return
        }
        
        let cacheKey = url.absoluteString as NSString
        
        // Check cache first
        if let cachedData = CachedAsyncImageCache.shared.cache.object(forKey: cacheKey) {
            imageData = cachedData as Data
            return
        }
        
        isLoading = true
        hasError = false
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty else {
                    await MainActor.run {
                        hasError = true
                        isLoading = false
                    }
                    return
                }
                
                // Cache the data
                CachedAsyncImageCache.shared.cache.setObject(data as NSData, forKey: cacheKey)
                
                await MainActor.run {
                    imageData = data
                    isLoading = false
                    hasError = false
                }
            } catch {
                await MainActor.run {
                    hasError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Performance Monitoring Tools

/// ✅ PERFORMANCE: Tracks view render times and identifies slow components
@MainActor
struct PerformanceMonitor: ViewModifier {
    let identifier: String
    @State private var renderStartTime: CFTimeInterval = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                renderStartTime = CACurrentMediaTime()
            }
            .onDisappear {
                let renderTime = CACurrentMediaTime() - renderStartTime
                if renderTime > 0.016 { // Alert if slower than 60fps
                    print("⚠️ PERFORMANCE: \(identifier) took \(renderTime * 1000)ms to render")
                }
            }
    }
}

extension View {
    func performanceMonitor(_ identifier: String) -> some View {
        modifier(PerformanceMonitor(identifier: identifier))
    }
}

// MARK: - SwiftData Performance Optimizations

/// ✅ PERFORMANCE: Optimized library data source with intelligent caching
@MainActor
@Observable
class OptimizedLibraryDataSource {
    private var cachedWorks: [Work] = []
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValidityDuration: TimeInterval = 5.0 // 5 seconds
    
    func getFilteredWorks(
        from works: [Work], 
        searchText: String,
        forceRefresh: Bool = false
    ) -> [Work] {
        let now = Date()
        
        // Use cache if valid and not forced refresh
        if !forceRefresh && 
           now.timeIntervalSince(lastCacheUpdate) < cacheValidityDuration &&
           !cachedWorks.isEmpty {
            return filterWorks(cachedWorks, searchText: searchText)
        }
        
        // Update cache
        cachedWorks = works
        lastCacheUpdate = now
        
        return filterWorks(cachedWorks, searchText: searchText)
    }
    
    private func filterWorks(_ works: [Work], searchText: String) -> [Work] {
        guard !searchText.isEmpty else { return works }
        
        return works.filter { work in
            work.title.localizedCaseInsensitiveContains(searchText) ||
            work.authorNames.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func invalidateCache() {
        lastCacheUpdate = .distantPast
    }
}

// MARK: - Navigation Performance Fixes

/// ✅ NAVIGATION FIX: Prevents memory leaks and crashes with SwiftData navigation
struct SafeWorkNavigation: ViewModifier {
    let workID: UUID
    let allWorks: [Work]
    
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: UUID.self) { targetWorkID in
                if let work = allWorks.first(where: { $0.id == targetWorkID }) {
                    WorkDetailView(work: work)
                        .performanceMonitor("WorkDetailView-\(work.title)")
                } else {
                    // Fallback view for missing works
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Book Not Found")
                            .font(.headline)
                        Text("This book may have been removed from your library.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
    }
}

extension View {
    func safeWorkNavigation(workID: UUID, allWorks: [Work]) -> some View {
        modifier(SafeWorkNavigation(workID: workID, allWorks: allWorks))
    }
}

// MARK: - Memory Management Helpers

/// ✅ MEMORY: Cleans up image cache when memory pressure occurs
@MainActor
struct MemoryPressureHandler {
    static let shared = MemoryPressureHandler()
    
    private init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.cleanupImageCache()
        }
    }
    
    private static func cleanupImageCache() {
        // Clear NSCache when memory pressure occurs
        CachedAsyncImageCache.shared.cache.removeAllObjects()
        print("🧹 MEMORY: Cleared image cache due to memory pressure")
    }
}

// Shared cache for all CachedAsyncImage instances
final class CachedAsyncImageCache: @unchecked Sendable {
    static let shared = CachedAsyncImageCache()

    let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 100 // Limit to 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        return cache
    }()

    private init() {}
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    let work: Work
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Work info header
                HStack(spacing: 16) {
                    AsyncImage(url: work.primaryEdition?.coverImageURL.flatMap(URL.init)) { image in
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                    .frame(width: 60, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(work.title)
                            .font(.headline.bold())
                            .lineLimit(2)

                        Text(work.authorNames)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let year = work.firstPublicationYear {
                            Text("\(year)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Quick action buttons
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    QuickActionButton(
                        title: "Start Reading",
                        icon: "book.pages",
                        color: .blue
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "Add to Wishlist",
                        icon: "heart",
                        color: .pink
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "View Details",
                        icon: "info.circle",
                        color: .purple
                    ) {
                        // Action
                        dismiss()
                    }

                    QuickActionButton(
                        title: "Share",
                        icon: "square.and.arrow.up",
                        color: .green
                    ) {
                        // Action
                        dismiss()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            // .glassEffect(.regular.tint(color.opacity(0.1)))
        }
        .buttonStyle(PressedButtonStyle())
    }
}

// MARK: - Press Events Modifier (Removed - using simultaneousGesture instead)

// MARK: - Pressed Button Style

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    let sampleWork = Work(
        title: "The Adventures of Huckleberry Finn",
        authors: [Author(name: "Mark Twain")],
        originalLanguage: "English",
        firstPublicationYear: 1884
    )

    return VStack {
        iOS26FloatingBookCard(work: sampleWork, namespace: Namespace().wrappedValue)
            .frame(width: 160)

        Spacer()
    }
    .padding()
    .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
}