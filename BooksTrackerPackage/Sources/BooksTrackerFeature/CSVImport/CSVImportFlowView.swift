import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSV Import Flow View
/// Main orchestrator view for the CSV import workflow
@MainActor
public struct CSVImportFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var importService: CSVImportService?
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // iOS 26 Liquid Glass background
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                Group {
                    switch importService?.importState ?? .idle {
                    case .idle:
                        FileSelectionView(
                            showingFilePicker: $showingFilePicker,
                            themeStore: themeStore
                        )

                    case .analyzingFile:
                        AnalyzingFileView(themeStore: themeStore)

                    case .mappingColumns:
                        if let service = importService {
                            ColumnMappingView(
                                importService: service,
                                themeStore: themeStore
                            )
                        }

                    case .importing:
                        if let service = importService {
                            ImportProgressView(
                                progress: service.progress,
                                themeStore: themeStore
                            )
                        }

                    case .completed(let result):
                        ImportResultsView(
                            result: result,
                            themeStore: themeStore,
                            onDone: { dismiss() }
                        )

                    case .failed(let error):
                        ImportErrorView(
                            error: error,
                            themeStore: themeStore,
                            onRetry: { showingFilePicker = true }
                        )
                    }
                }
                .animation(.smooth(duration: 0.3), value: importService?.importState)
            }
            .navigationTitle("Import Books")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(importService?.importState == .importing)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
        .onAppear {
            // Initialize service with actual model context
            if importService == nil {
                importService = CSVImportService(modelContext: modelContext)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await importService?.loadFile(at: url)
            }

        case .failure(let error):
            importService?.importState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - File Selection View

struct FileSelectionView: View {
    @Binding var showingFilePicker: Bool
    let themeStore: iOS26ThemeStore
    @State private var isDragging = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 60))
                        .foregroundStyle(themeStore.primaryColor.gradient)
                        .symbolEffect(.bounce.up, value: isDragging)

                    Text("Import Your Library")
                        .font(.title.bold())

                    Text("Import books from CSV files exported from\nGoodreads, LibraryThing, StoryGraph, or any service")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Drop zone
                FileDropZone(
                    isDragging: $isDragging,
                    showingPicker: $showingFilePicker,
                    themeStore: themeStore
                )

                // Service templates
                ServiceTemplateSection(themeStore: themeStore)

                // Supported formats
                SupportedFormatsCard(themeStore: themeStore)
            }
            .padding()
        }
    }
}

struct FileDropZone: View {
    @Binding var isDragging: Bool
    @Binding var showingPicker: Bool
    let themeStore: iOS26ThemeStore

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        isDragging ? themeStore.primaryColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: isDragging ? [] : [8])
                    )
            )
            .overlay(
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(themeStore.primaryColor.gradient)

                    Text("Drop CSV file here")
                        .font(.headline)

                    Text("or tap to browse")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Choose File")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(themeStore.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(32)
            )
            .frame(height: 200)
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(.smooth(duration: 0.2), value: isDragging)
            .onTapGesture {
                showingPicker = true
            }
    }
}

// MARK: - Column Mapping View

struct ColumnMappingView: View {
    @ObservedObject var importService: CSVImportService
    let themeStore: iOS26ThemeStore
    @State private var showingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            MappingStatusHeader(
                mappings: importService.mappings,
                themeStore: themeStore
            )
            .padding()

            ScrollView {
                VStack(spacing: 16) {
                    // Auto-detected mappings
                    ForEach(importService.mappings.indices, id: \.self) { index in
                        MappingRowView(
                            mapping: $importService.mappings[index],
                            themeStore: themeStore,
                            onFieldChange: { field in
                                importService.updateMapping(
                                    for: importService.mappings[index].csvColumn,
                                    to: field
                                )
                            }
                        )
                    }

                    // Preview button
                    Button {
                        showingPreview.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "eye")
                            Text("Preview Import")
                        }
                        .font(.headline)
                        .foregroundColor(themeStore.primaryColor)
                    }
                    .padding(.top)
                }
                .padding()
            }

            // Action bar
            HStack(spacing: 12) {
                Button("Reset Auto-Detect") {
                    // Reset mappings to auto-detected values
                }
                .buttonStyle(SecondaryButtonStyle(themeStore: themeStore))

                Button {
                    Task {
                        await importService.startImport()
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Start Import")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(themeStore: themeStore))
                .disabled(!importService.canProceedWithImport())
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingPreview) {
            PreviewSheetView(
                mappings: importService.mappings,
                themeStore: themeStore
            )
        }
    }
}

struct MappingRowView: View {
    @Binding var mapping: CSVParsingActor.ColumnMapping
    let themeStore: iOS26ThemeStore
    let onFieldChange: (CSVParsingActor.ColumnMapping.BookField?) -> Void

    var body: some View {
        HStack(spacing: 16) {
            // CSV column info
            VStack(alignment: .leading, spacing: 4) {
                Text(mapping.csvColumn)
                    .font(.headline)

                if let firstSample = mapping.sampleValues.first {
                    Text(firstSample)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Confidence indicator
            if mapping.confidence > 0 {
                ConfidenceIndicator(level: mapping.confidence, themeStore: themeStore)
            }

            // Field picker
            Menu {
                Button("None") {
                    onFieldChange(nil)
                }
                Divider()
                ForEach(CSVParsingActor.ColumnMapping.BookField.allCases, id: \.self) { field in
                    Button(field.rawValue) {
                        onFieldChange(field)
                    }
                }
            } label: {
                HStack {
                    Text(mapping.mappedField?.rawValue ?? "Select Field")
                        .foregroundColor(mapping.mappedField != nil ? .primary : .secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

struct ConfidenceIndicator: View {
    let level: Double
    let themeStore: iOS26ThemeStore

    var color: Color {
        switch level {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Double(index) / 3.0 < level ? color : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Import Progress View

struct ImportProgressView: View {
    let progress: CSVImportService.ImportProgress
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated book icon
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 60))
                .foregroundStyle(themeStore.primaryColor.gradient)
                .symbolEffect(.pulse)

            // Current book
            if !progress.currentBook.isEmpty {
                VStack(spacing: 4) {
                    Text("Processing")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(progress.currentBook)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }

            // Progress bar
            VStack(spacing: 12) {
                ProgressView(value: progress.percentComplete)
                    .progressViewStyle(LiquidProgressStyle(themeStore: themeStore))
                    .frame(height: 8)

                HStack {
                    Text("\(progress.processedRows) of \(progress.totalRows)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let remaining = progress.estimatedTimeRemaining {
                        Text(formatTimeRemaining(remaining))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 40)

            // Statistics
            HStack(spacing: 20) {
                StatisticView(
                    icon: "checkmark.circle",
                    value: "\(progress.successfulImports)",
                    label: "Imported",
                    color: .green
                )

                if progress.skippedDuplicates > 0 {
                    StatisticView(
                        icon: "doc.on.doc",
                        value: "\(progress.skippedDuplicates)",
                        label: "Duplicates",
                        color: .orange
                    )
                }

                if progress.failedImports > 0 {
                    StatisticView(
                        icon: "xmark.circle",
                        value: "\(progress.failedImports)",
                        label: "Errors",
                        color: .red
                    )
                }
            }

            Spacer()
        }
        .padding()
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "Less than a minute"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min remaining"
        } else {
            let hours = Int(seconds / 3600)
            return "\(hours) hr remaining"
        }
    }
}

struct StatisticView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.headline)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
    }
}

// MARK: - Supporting Views

struct AnalyzingFileView: View {
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: themeStore.primaryColor))

            Text("Analyzing CSV file...")
                .font(.headline)
                .foregroundStyle(themeStore.primaryColor)

            Text("Detecting column formats and data types")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }
}

struct MappingStatusHeader: View {
    let mappings: [CSVParsingActor.ColumnMapping]
    let themeStore: iOS26ThemeStore

    var requiredFieldsMapped: Bool {
        let hasTitle = mappings.contains { $0.mappedField == .title }
        let hasAuthor = mappings.contains { $0.mappedField == .author }
        return hasTitle && hasAuthor
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Column Mapping")
                    .font(.headline)

                Text(requiredFieldsMapped ? "Required fields mapped ✓" : "Map Title and Author columns")
                    .font(.caption)
                    .foregroundColor(requiredFieldsMapped ? .green : .orange)
            }

            Spacer()

            // Auto-detect quality indicator
            let avgConfidence = mappings.map(\.confidence).reduce(0, +) / Double(mappings.count)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Auto-Detect")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: avgConfidence > 0.7 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(avgConfidence > 0.7 ? .green : .orange)

                    Text("\(Int(avgConfidence * 100))%")
                        .font(.caption.bold())
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    let themeStore: iOS26ThemeStore

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(themeStore.primaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    let themeStore: iOS26ThemeStore

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(themeStore.primaryColor)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Progress Style

struct LiquidProgressStyle: ProgressViewStyle {
    let themeStore: iOS26ThemeStore

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                themeStore.primaryColor,
                                themeStore.secondaryColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                    .animation(.smooth(duration: 0.3), value: configuration.fractionCompleted)
            }
        }
    }
}