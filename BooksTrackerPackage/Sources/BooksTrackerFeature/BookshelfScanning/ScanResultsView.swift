import SwiftUI
import SwiftData

#if canImport(UIKit)

// MARK: - Confidence Thresholds

/// Shared confidence thresholds for scan result categorization
private enum ConfidenceThreshold {
    static let high: Double = 0.7
    static let medium: Double = 0.1
}

// MARK: - Photo Overlay Info

/// Data structure for photo overlay sheet presentation
private struct PhotoOverlayInfo: Identifiable {
    let id = UUID()
    let image: UIImage
    let books: [DetectedBook]
}

// MARK: - Scan Results View

/// Review and confirm detected books before adding to library
@MainActor
public struct ScanResultsView: View {
    let scanResult: ScanResult?
    let modelContext: ModelContext
    let onDismiss: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var resultsModel: ScanResultsModel
    @State private var dismissedSuggestionTypes: Set<String> = []
    @State private var photoOverlayInfo: PhotoOverlayInfo?
    @State private var showOnlyLowConfidence = false

    public init(
        scanResult: ScanResult?,
        modelContext: ModelContext,
        onDismiss: @escaping () -> Void
    ) {
        self.scanResult = scanResult
        self.modelContext = modelContext
        self.onDismiss = onDismiss
        self._resultsModel = State(initialValue: ScanResultsModel(scanResult: scanResult))
    }

    private var activeSuggestions: [SuggestionViewModel] {
        (scanResult?.suggestions ?? []).filter { suggestion in
            !dismissedSuggestionTypes.contains(suggestion.type)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                if let result = scanResult {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Summary card
                            summaryCard(result: result)

                            // Suggestions banner (NEW - between summary and books)
                            suggestionsBanner()

                            // Detected books list
                            detectedBooksList

                            // Add all button
                            if !resultsModel.detectedBooks.isEmpty {
                                addAllButton
                            }

                            // Bottom spacer
                            Color.clear.frame(height: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let image = scanResult?.capturedImage, let books = scanResult?.detectedBooks, !books.isEmpty {
                        Button(action: { 
                            self.photoOverlayInfo = PhotoOverlayInfo(image: image, books: books)
                        }) {
                            Image(systemName: "photo.on.rectangle")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(item: $photoOverlayInfo) { info in
                BoundingBoxOverlayView(image: info.image, detectedBooks: info.books)
            }
            .task {
                await resultsModel.performDuplicateCheck(modelContext: modelContext)
            }
        }
    }

    // MARK: - Summary Card

    private func summaryCard(result: ScanResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan Complete")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Processed in \(String(format: "%.1f", result.totalProcessingTime))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
            }

            Divider()

            // Statistics
            HStack(spacing: 20) {
                statBadge(
                    value: "\(result.statistics.totalDetected)",
                    label: "Detected",
                    color: .blue
                )

                statBadge(
                    value: "\(result.statistics.withISBN)",
                    label: "With ISBN",
                    color: .green
                )

                statBadge(
                    value: "\(result.statistics.needsReview)",
                    label: "Uncertain",
                    color: .orange
                )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Suggestions Banner

    @ViewBuilder
    private func suggestionsBanner() -> some View {
        if !activeSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(themeStore.primaryColor)
                    Text("Suggestions")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                // Suggestion rows
                ForEach(Array(activeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 36)
                    }
                    suggestionRow(suggestion)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 1)
                    }
            }
        }
    }

    private func suggestionRow(_ suggestion: SuggestionViewModel) -> some View {
        HStack(spacing: 12) {
            // Severity icon
            Image(systemName: suggestion.iconName)
                .font(.body)
                .foregroundStyle(colorForSeverity(suggestion.severity))
                .frame(width: 24)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let count = suggestion.affectedCount {
                    Text("\(count) book\(count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Dismiss button ("Got it" pattern)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    _ = dismissedSuggestionTypes.insert(suggestion.type)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(themeStore.primaryColor.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(suggestion.type.replacingOccurrences(of: "_", with: " ")) as understood")
        }
        .padding(.vertical, 8)
    }

    private func colorForSeverity(_ severity: String) -> Color {
        switch severity {
        case "high": return .red
        case "medium": return .orange
        default: return themeStore.primaryColor
        }
    }

    // MARK: - Detected Books List

    private var detectedBooksList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Detected Books")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(resultsModel.filteredBooks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show only low confidence", isOn: $showOnlyLowConfidence)
                .padding(.bottom, 8)
                .onChange(of: showOnlyLowConfidence) { _, newValue in
                    resultsModel.showOnlyLowConfidence = newValue
                }

            ForEach(resultsModel.filteredBooks) { book in
                DetectedBookRow(
                    detectedBook: book,
                    onSearch: {
                        await resultsModel.searchBook(book, modelContext: modelContext)
                    },
                    onToggle: {
                        resultsModel.toggleBookSelection(book)
                    }
                )
            }
        }
    }

    // MARK: - Add All Button

    private var addAllButton: some View {
        Button {
            Task {
                await resultsModel.addAllToLibrary(modelContext: modelContext)
                onDismiss()
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)

                Text("Add \(resultsModel.selectedCount) to Library")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeStore.primaryColor.gradient)
            }
        }
        .disabled(resultsModel.selectedCount == 0 || resultsModel.isAdding)
        .opacity((resultsModel.selectedCount == 0 || resultsModel.isAdding) ? 0.5 : 1.0)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Results")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Text("No books were detected in the selected photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Detected Book Row

struct DetectedBookRow: View {
    let detectedBook: DetectedBook
    let onSearch: () async -> Void
    let onToggle: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var isSearching = false
    @State private var showConfidenceExplanation: Bool = false
    @AppStorage("aiConfidenceThreshold") private var threshold: Double = 0.6

    var confidenceColor: Color {
        switch detectedBook.confidence {
        case 0.8...1.0: return .green // High
        case threshold..<0.8: return .orange // Medium
        default: return .red // Low (review queue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Status icon
                Image(systemName: detectedBook.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(detectedBook.status.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    if let title = detectedBook.title {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    // Author
                    if let author = detectedBook.author {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // ISBN
                    if let isbn = detectedBook.isbn {
                        HStack(spacing: 4) {
                            Image(systemName: "barcode")
                                .font(.caption2)
                            Text(isbn)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ConfidenceBadgeView(confidence: detectedBook.confidence)

                // Selection toggle
                Button {
                    onToggle()
                } label: {
                    Image(systemName: detectedBook.status == .confirmed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(detectedBook.status == .confirmed ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }

            if detectedBook.confidence < threshold {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Sent to review queue for verification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Why?") {
                        showConfidenceExplanation = true
                    }
                    .font(.caption)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                // Search button
                Button {
                    Task {
                        isSearching = true
                        await onSearch()
                        isSearching = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Search Matches")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(themeStore.primaryColor)
                    }
                }
                .disabled(isSearching)

                // Status badge
                Text(detectedBook.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(detectedBook.status.color.opacity(0.2))
                    }
                    .foregroundStyle(detectedBook.status.color)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            confidenceColor.opacity(0.5),
                            lineWidth: 2
                        )
                }
        }
        .sheet(isPresented: $showConfidenceExplanation) {
            ConfidenceExplanationSheet(confidence: detectedBook.confidence)
        }
    }
}

// MARK: - Scan Results Model

@MainActor
@Observable
class ScanResultsModel {
    var detectedBooks: [DetectedBook]
    var isAdding = false
    var showOnlyLowConfidence = false
    @AppStorage("aiConfidenceThreshold") private var threshold: Double = 0.6

    var filteredBooks: [DetectedBook] {
        if showOnlyLowConfidence {
            return detectedBooks.filter { $0.confidence < threshold }
        } else {
            return detectedBooks
        }
    }

    var selectedCount: Int {
        filteredBooks.filter { $0.status == .confirmed }.count
    }

    init(scanResult: ScanResult?) {
        self.detectedBooks = scanResult?.detectedBooks.sorted(by: { $0.confidence > $1.confidence }) ?? []
    }

    // MARK: - Duplicate Detection

    func performDuplicateCheck(modelContext: ModelContext) async {
        for index in detectedBooks.indices {
            let book = detectedBooks[index]

            // Check if already in library
            if await isDuplicate(book, in: modelContext) {
                detectedBooks[index].status = .alreadyInLibrary
            } else if book.confidence >= ConfidenceThreshold.high && (book.isbn != nil || (book.title != nil && book.author != nil)) {
                // Auto-select high-confidence books
                detectedBooks[index].status = .confirmed
            }
        }
    }

    private func isDuplicate(_ detectedBook: DetectedBook, in modelContext: ModelContext) async -> Bool {
        // ISBN-first strategy
        if let isbn = detectedBook.isbn, !isbn.isEmpty {
            let descriptor = FetchDescriptor<Edition>(
                predicate: #Predicate<Edition> { edition in
                    edition.isbn == isbn
                }
            )
            if let editions = try? modelContext.fetch(descriptor), !editions.isEmpty {
                return true
            }
        }

        // Title + Author fallback
        if let title = detectedBook.title, let author = detectedBook.author {
            let titleLower = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let authorLower = author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            let descriptor = FetchDescriptor<Work>()
            if let allWorks = try? modelContext.fetch(descriptor) {
                return allWorks.contains { work in
                    guard work.userLibraryEntries?.isEmpty == false else { return false }
                    let workTitle = work.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let workAuthor = work.authorNames.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    return workTitle == titleLower && workAuthor == authorLower
                }
            }
        }

        return false
    }

    // MARK: - Book Search Integration

    @MainActor
    func searchBook(_ detectedBook: DetectedBook, modelContext: ModelContext) async {
        // TODO: Phase 1E - Integrate with BookSearchAPIService
        // For now, just mark as confirmed if not duplicate
        if detectedBook.status != .alreadyInLibrary {
            if let index = detectedBooks.firstIndex(where: { $0.id == detectedBook.id }) {
                detectedBooks[index].status = .confirmed
            }
        }
    }

    func toggleBookSelection(_ detectedBook: DetectedBook) {
        guard let index = detectedBooks.firstIndex(where: { $0.id == detectedBook.id }) else { return }

        // Can't toggle books already in library
        if detectedBooks[index].status == .alreadyInLibrary {
            return
        }

        // Toggle between confirmed and detected
        detectedBooks[index].status = detectedBooks[index].status == .confirmed ? .detected : .confirmed
    }

    // MARK: - Add to Library

    @MainActor
    func addAllToLibrary(modelContext: ModelContext) async {
        isAdding = true

        // Include both auto-selected (.confirmed) and manually selected (.detected) books
        // Exclude only .alreadyInLibrary and .rejected
        let includedStatuses: Set<DetectionStatus> = [.confirmed, .detected]
        let selectedBooks = detectedBooks.filter { includedStatuses.contains($0.status) }
        let dtoMapper = DTOMapper(modelContext: modelContext)
        var enrichedImportCount = 0
        var queuedImportCount = 0
        var addedWorksForQueue: [Work] = []

        for detectedBook in selectedBooks {
            var importedViaPathA = false

            // Path A: Use pre-enriched data from backend
            if let enrichedWork = detectedBook.enrichmentWork,
               let enrichedEditions = detectedBook.enrichmentEditions,
               let enrichedAuthors = detectedBook.enrichmentAuthors {

                do {
                    // Create Authors first (insert before relationships)
                    let authors = try enrichedAuthors.map { authorDTO in
                        try dtoMapper.mapToAuthor(authorDTO)
                    }

                    // Create Work (insert before relationships)
                    let work = try dtoMapper.mapToWork(enrichedWork)

                    // Set review status based on confidence threshold (0.60)
                    work.reviewStatus = detectedBook.needsReview ? ReviewStatus.needsReview : ReviewStatus.verified

                    // Store original image path and bounding box for correction UI
                    work.originalImagePath = detectedBook.originalImagePath
                    work.boundingBox = detectedBook.boundingBox

                    // Create Editions (insert before relationships)
                    let editions = try enrichedEditions.map { editionDTO in
                        try dtoMapper.mapToEdition(editionDTO)
                    }

                    // CRITICAL: Link relationships AFTER all inserts
                    work.authors = authors
                    for edition in editions {
                        edition.work = work
                    }

                    // Create library entry
                    let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)
                    if let primaryEdition = editions.first {
                        entry.edition = primaryEdition
                    }

                    try modelContext.save()

                    #if DEBUG
                    print("✅ Imported enriched book: \(work.title)")
                    #endif
                    enrichedImportCount += 1
                    importedViaPathA = true

                } catch {
                    #if DEBUG
                    print("❌ Path A failed for enriched book: \(error). Falling back to Path B.")
                    #endif
                    // Fall through to Path B below
                }
            }

            // Path B: Minimal import + queue for enrichment (fallback or primary)
            if !importedViaPathA {
                do {
                    #if DEBUG
                    print("[DEBUGGER:ScanResultsView:631] Creating minimal work for: \(detectedBook.title ?? "Unknown")")
                    #endif
                    
                    // Create minimal Work
                    let work = Work(
                        title: detectedBook.title ?? "Unknown Title",
                        originalLanguage: nil,
                        firstPublicationYear: nil,
                        subjectTags: [],
                        synthetic: false,
                        primaryProvider: nil
                    )

                    // Set review status based on confidence threshold (0.60)
                    work.reviewStatus = detectedBook.needsReview ? ReviewStatus.needsReview : ReviewStatus.verified

                    // Store original image path and bounding box for correction UI
                    work.originalImagePath = detectedBook.originalImagePath
                    work.boundingBox = detectedBook.boundingBox

                    modelContext.insert(work)

                    // Create Authors
                    if let authorName = detectedBook.author {
                        let author = Author(
                            name: authorName,
                            nationality: nil,
                            gender: .unknown,
                            culturalRegion: nil,
                            birthYear: nil,
                            deathYear: nil
                        )
                        modelContext.insert(author)
                        work.authors = [author]
                    }

                    // Create library entry
                    let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

                    // If ISBN available, create minimal edition
                    if let isbn = detectedBook.isbn {
                        let edition = Edition(
                            isbn: isbn,
                            publisher: nil,
                            publicationDate: nil,
                            pageCount: nil,
                            format: .paperback
                        )
                        modelContext.insert(edition)
                        edition.work = work
                        entry.edition = edition
                    }

                    try modelContext.save()

                    #if DEBUG
                    print("[DEBUGGER:ScanResultsView:688] Saved work, ID: \(work.persistentModelID)")
                    #endif

                    // Track for enrichment queue
                    addedWorksForQueue.append(work)

                    #if DEBUG
                    print("⚠️ Queued book for enrichment: \(work.title)")
                    #endif
                    queuedImportCount += 1

                } catch {
                    #if DEBUG
                    print("❌ Failed to import book (Path B): \(error)")
                    #endif
                }
            }
        }

        // Queue Path B books for enrichment
        if !addedWorksForQueue.isEmpty {
            let workIDs = addedWorksForQueue.map { $0.persistentModelID }
            EnrichmentQueue.shared.enqueueBatch(workIDs)
            #if DEBUG
            print("📚 Queued \(workIDs.count) books from scan for background enrichment")
            #endif

            // [DEBUGGER:ScanResultsView:addAllToLibrary:707] Starting context merge wait
            // Delay enrichment to allow SwiftData to fully persist newly created works
            Task {
                #if DEBUG
                print("[DEBUGGER:ScanResultsView:713] Before 500ms delay - workIDs.count=\(workIDs.count)")
                #endif
                try? await Task.sleep(for: .milliseconds(500))
                
                #if DEBUG
                print("[DEBUGGER:ScanResultsView:718] After 500ms delay - checking context availability")
                let availableCount = workIDs.compactMap { modelContext.model(for: $0) as? Work }.count
                print("[DEBUGGER:ScanResultsView:720] Works available in context: \(availableCount)/\(workIDs.count)")
                #endif
                
                EnrichmentQueue.shared.startProcessing(in: modelContext) { _, _, _ in
                    // Silent background processing - progress shown via EnrichmentProgressBanner
                }
            }
        }

        #if DEBUG
        // Analytics logging
        print("📊 Import complete: \(enrichedImportCount) enriched, \(queuedImportCount) queued")
        print("📊 Analytics: bookshelf_import_completed - total: \(selectedBooks.count), enriched: \(enrichedImportCount), queued: \(queuedImportCount)")
        #endif

        isAdding = false
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    let mockResult = ScanResult(
        detectedBooks: [
            DetectedBook(
                isbn: "9780062073488",
                title: "Murder on the Orient Express",
                author: "Agatha Christie",
                confidence: 0.95,
                boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.3),
                rawText: "Murder on the Orient Express Agatha Christie",
                status: .detected
            ),
            DetectedBook(
                isbn: nil,
                title: "The Great Gatsby",
                author: "F. Scott Fitzgerald",
                confidence: 0.65,
                boundingBox: CGRect(x: 0.1, y: 0, width: 0.1, height: 0.3),
                rawText: "The Great Gatsby F. Scott Fitzgerald",
                status: .uncertain
            )
        ],
        totalProcessingTime: 2.5
    )

    let container = try! ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self)

    ScanResultsView(
        scanResult: mockResult,
        modelContext: container.mainContext,
        onDismiss: {}
    )
    .environment(BooksTrackerFeature.iOS26ThemeStore())
}

#endif  // canImport(UIKit)
