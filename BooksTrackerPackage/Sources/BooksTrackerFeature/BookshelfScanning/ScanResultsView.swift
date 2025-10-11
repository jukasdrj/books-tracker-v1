import SwiftUI
import SwiftData

// MARK: - Scan Results View

/// Review and confirm detected books before adding to library
@MainActor
public struct ScanResultsView: View {
    let scanResult: ScanResult?
    let modelContext: ModelContext
    let onDismiss: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var resultsModel: ScanResultsModel

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
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

    // MARK: - Detected Books List

    private var detectedBooksList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Detected Books")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(resultsModel.detectedBooks.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(resultsModel.detectedBooks) { book in
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

                    // Confidence
                    HStack(spacing: 4) {
                        Text("Confidence:")
                        Text("\(Int(detectedBook.confidence * 100))%")
                            .fontWeight(.medium)
                    }
                    .font(.caption2)
                    .foregroundStyle(detectedBook.confidence >= 0.7 ? .green : .orange)
                }

                Spacer()

                // Selection toggle
                Button {
                    onToggle()
                } label: {
                    Image(systemName: detectedBook.status == .confirmed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(detectedBook.status == .confirmed ? .green : .secondary)
                }
                .buttonStyle(.plain)
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
                            detectedBook.status == .alreadyInLibrary ? Color.orange.opacity(0.5) :
                            detectedBook.status == .confirmed ? Color.green.opacity(0.3) :
                            Color.clear,
                            lineWidth: 2
                        )
                }
        }
    }
}

// MARK: - Scan Results Model

@MainActor
@Observable
class ScanResultsModel {
    var detectedBooks: [DetectedBook]
    var isAdding = false
    var selectedCount: Int {
        detectedBooks.filter { $0.status == .confirmed }.count
    }

    init(scanResult: ScanResult?) {
        self.detectedBooks = scanResult?.detectedBooks ?? []
    }

    // MARK: - Duplicate Detection

    func performDuplicateCheck(modelContext: ModelContext) async {
        for index in detectedBooks.indices {
            let book = detectedBooks[index]

            // Check if already in library
            if await isDuplicate(book, in: modelContext) {
                detectedBooks[index].status = .alreadyInLibrary
            } else if book.confidence >= 0.7 && (book.isbn != nil || (book.title != nil && book.author != nil)) {
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

        let confirmedBooks = detectedBooks.filter { $0.status == .confirmed }

        for detectedBook in confirmedBooks {
            // Create Work and Edition from detected metadata
            let authors = detectedBook.author.map { [Author(name: $0)] } ?? []
            let work = Work(
                title: detectedBook.title ?? "Unknown Title",
                authors: authors,
                originalLanguage: "English",
                firstPublicationYear: nil
            )

            modelContext.insert(work)

            // Create edition if ISBN available
            if let isbn = detectedBook.isbn {
                let edition = Edition(
                    isbn: isbn,
                    publisher: nil,
                    publicationDate: nil,
                    pageCount: nil,
                    format: .paperback,
                    work: work
                )
                modelContext.insert(edition)

                // Create library entry (owned)
                let libraryEntry = UserLibraryEntry.createOwnedEntry(
                    for: work,
                    edition: edition,
                    status: .toRead
                )
                modelContext.insert(libraryEntry)

            } else {
                // Create wishlist entry (no edition)
                let libraryEntry = UserLibraryEntry.createWishlistEntry(for: work)
                modelContext.insert(libraryEntry)
            }
        }

        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save books: \(error)")
        }

        isAdding = false
    }
}

// MARK: - Preview

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
    .environment(iOS26ThemeStore())
}
