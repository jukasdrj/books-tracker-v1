import SwiftUI
import SwiftData

// MARK: - Import Results View

struct ImportResultsView: View {
    let result: CSVImportService.ImportResult
    let themeStore: iOS26ThemeStore
    let onDone: () -> Void
    @State private var showingErrorDetails = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Success animation
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.green.gradient)
                    .symbolEffect(.bounce)

                // Summary
                VStack(spacing: 16) {
                    Text("Import Complete!")
                        .font(.title.bold())

                    Text("Your library has been updated")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Statistics grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        icon: "books.vertical.fill",
                        title: "Imported",
                        value: "\(result.successCount)",
                        color: .green
                    )

                    StatCard(
                        icon: "doc.on.doc",
                        title: "Duplicates",
                        value: "\(result.duplicateCount)",
                        color: .orange
                    )

                    if result.errorCount > 0 {
                        StatCard(
                            icon: "exclamationmark.triangle",
                            title: "Errors",
                            value: "\(result.errorCount)",
                            color: .red
                        )
                        .onTapGesture {
                            showingErrorDetails = true
                        }
                    }

                    StatCard(
                        icon: "clock",
                        title: "Time",
                        value: formatDuration(result.duration),
                        color: themeStore.primaryColor
                    )
                }

                // Recently imported books preview
                if !result.importedWorks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Imported")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(result.importedWorks.prefix(5), id: \.persistentModelID) { work in
                                    ImportedBookCard(work: work, themeStore: themeStore)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onDone()
                    } label: {
                        HStack {
                            Image(systemName: "books.vertical")
                            Text("View Library")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(themeStore: themeStore))

                    Button {
                        // Navigate to import again
                    } label: {
                        Text("Import Another File")
                    }
                    .buttonStyle(SecondaryButtonStyle(themeStore: themeStore))
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 32)
        }
        .sheet(isPresented: $showingErrorDetails) {
            ErrorDetailsSheet(
                errors: result.errors,
                themeStore: themeStore
            )
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return String(format: "%.1fh", duration / 3600)
        }
    }
}

// MARK: - Import Error View

struct ImportErrorView: View {
    let error: String
    let themeStore: iOS26ThemeStore
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.red.gradient)

            VStack(spacing: 12) {
                Text("Import Failed")
                    .font(.title.bold())

                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                onRetry()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
            }
            .buttonStyle(PrimaryButtonStyle(themeStore: themeStore))
            .padding(.horizontal, 40)
        }
        .padding(40)
    }
}

// MARK: - Service Template Section

struct ServiceTemplateSection: View {
    let themeStore: iOS26ThemeStore
    @State private var selectedService: BookService?

    enum BookService: String, CaseIterable {
        case goodreads = "Goodreads"
        case libraryThing = "LibraryThing"
        case storyGraph = "StoryGraph"
        case generic = "Generic CSV"

        var icon: String {
            switch self {
            case .goodreads: return "book.circle"
            case .libraryThing: return "books.vertical.circle"
            case .storyGraph: return "chart.line.uptrend.xyaxis.circle"
            case .generic: return "doc.circle"
            }
        }

        var expectedColumns: [String] {
            switch self {
            case .goodreads:
                return ["Title", "Author", "ISBN13", "My Rating", "Date Read", "Exclusive Shelf"]
            case .libraryThing:
                return ["Title", "Primary Author", "ISBN", "Rating", "Date Started", "Date Read", "Tags"]
            case .storyGraph:
                return ["Title", "Authors", "ISBN/UID", "Star Rating", "Read Status", "Date Finished"]
            case .generic:
                return ["Title", "Author", "ISBN", "Rating", "Status"]
            }
        }

        var exportInstructions: String {
            switch self {
            case .goodreads:
                return "My Books → Import and export → Export Library"
            case .libraryThing:
                return "Home → Tools → Export"
            case .storyGraph:
                return "Manage Account → Export your data"
            case .generic:
                return "Ensure your CSV has Title and Author columns"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export from Services")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BookService.allCases, id: \.self) { service in
                        ServiceCard(
                            service: service,
                            isSelected: selectedService == service,
                            themeStore: themeStore
                        ) {
                            withAnimation(.smooth(duration: 0.2)) {
                                selectedService = selectedService == service ? nil : service
                            }
                        }
                    }
                }
            }

            if let service = selectedService {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to export from \(service.rawValue)")
                        .font(.subheadline.bold())

                    Text(service.exportInstructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Expected columns:")
                        .font(.caption.bold())
                        .padding(.top, 4)

                    Text(service.expectedColumns.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct ServiceCard: View {
    let service: ServiceTemplateSection.BookService
    let isSelected: Bool
    let themeStore: iOS26ThemeStore
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: service.icon)
                .font(.title2)
                .foregroundStyle(isSelected ? themeStore.primaryColor : Color.secondary)

            Text(service.rawValue)
                .font(.caption)
                .foregroundColor(isSelected ? .primary : .secondary)
        }
        .frame(width: 80, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? themeStore.primaryColor.opacity(0.1) : .clear)
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? themeStore.primaryColor : Color.clear,
                    lineWidth: 2
                )
        )
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Supported Formats Card

struct SupportedFormatsCard: View {
    let themeStore: iOS26ThemeStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(themeStore.primaryColor)

                Text("CSV Format Requirements")
                    .font(.subheadline.bold())

                Spacer()

                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.smooth(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    FormatRequirement(label: "Required", items: ["Title", "Author"])
                    FormatRequirement(label: "Optional", items: ["ISBN", "Rating", "Status", "Date Read", "Notes"])
                    FormatRequirement(label: "Auto-detected", items: ["ISBN-10/13", "My Rating", "Year Published"])

                    Text("Tips:")
                        .font(.caption.bold())
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint("Column names are flexible (Title, title, Book Title all work)")
                        BulletPoint("Dates can be in various formats (YYYY-MM-DD, MM/DD/YYYY)")
                        BulletPoint("Ratings are normalized to 1-5 scale")
                        BulletPoint("Duplicate books are detected by ISBN or Title+Author")
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct FormatRequirement: View {
    let label: String
    let items: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(label):")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(items.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview Sheet View

struct PreviewSheetView: View {
    let mappings: [CSVParsingActor.ColumnMapping]
    let themeStore: iOS26ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This preview shows how your data will be imported based on current column mappings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    // Sample preview cards
                    ForEach(0..<3, id: \.self) { index in
                        SampleBookPreview(
                            index: index,
                            mappings: mappings,
                            themeStore: themeStore
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct SampleBookPreview: View {
    let index: Int
    let mappings: [CSVParsingActor.ColumnMapping]
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Extract mapped values
            if let titleMapping = mappings.first(where: { $0.mappedField == .title }),
               index < titleMapping.sampleValues.count {
                Text(titleMapping.sampleValues[index])
                    .font(.headline)
            }

            if let authorMapping = mappings.first(where: { $0.mappedField == .author }),
               index < authorMapping.sampleValues.count {
                Text("by \(authorMapping.sampleValues[index])")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Show other mapped fields
            HStack(spacing: 12) {
                if let isbnMapping = mappings.first(where: {
                    $0.mappedField == .isbn || $0.mappedField == .isbn13 || $0.mappedField == .isbn10
                }), index < isbnMapping.sampleValues.count {
                    Label(isbnMapping.sampleValues[index], systemImage: "barcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let ratingMapping = mappings.first(where: {
                    $0.mappedField == .rating || $0.mappedField == .myRating
                }), index < ratingMapping.sampleValues.count {
                    Label(ratingMapping.sampleValues[index], systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}

// MARK: - Supporting Components

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct ImportedBookCard: View {
    let work: Work
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(work.title)
                .font(.caption.bold())
                .lineLimit(2)

            if let author = work.authors?.first {
                Text(author.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 120, height: 80)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
    }
}

struct ErrorDetailsSheet: View {
    let errors: [CSVImportService.ImportError]
    let themeStore: iOS26ThemeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(errors) { error in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Row \(error.row)")
                            .font(.caption.bold())
                            .foregroundColor(.red)

                        Spacer()

                        Text(error.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Import Errors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}