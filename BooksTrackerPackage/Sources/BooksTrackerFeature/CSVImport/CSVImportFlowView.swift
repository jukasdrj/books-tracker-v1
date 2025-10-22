import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSV Import Flow View
/// Main orchestrator view for the CSV import workflow
@available(iOS 26.0, *)
@MainActor
public struct CSVImportFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    @StateObject private var coordinator = SyncCoordinator.shared
    @State private var currentJobId: JobIdentifier?
    @State private var showingFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var parsedCSVData: (headers: [String], rows: [[String]])?
    @State private var columnMappings: [CSVParsingActor.ColumnMapping] = []
    @State private var duplicateStrategy: CSVImportService.DuplicateStrategy = .smart
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // iOS 26 Liquid Glass background
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                Group {
                    if let jobId = currentJobId,
                       let status = coordinator.getJobStatus(for: jobId) {
                        // Job is running - show progress
                        jobProgressView(for: jobId, status: status)
                    } else if let parsedData = parsedCSVData {
                        // CSV parsed - show column mapping
                        ColumnMappingView(
                            headers: parsedData.headers,
                            rows: parsedData.rows,
                            onMappingsConfirmed: { mappings in
                                columnMappings = mappings
                                Task { await startImport() }
                            },
                            onCancel: { parsedCSVData = nil },
                            themeStore: themeStore
                        )
                    } else {
                        // Idle state - show file picker
                        FileSelectionView(
                            showingFilePicker: $showingFilePicker,
                            themeStore: themeStore
                        )
                    }
                }
                .animation(.smooth(duration: 0.3), value: currentJobId != nil)
            }
            .navigationTitle("Import Books")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(currentJobId != nil)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Import Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onDisappear {
                if let jobId = currentJobId {
                    coordinator.cancelJob(jobId)
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await parseCSV(from: url) }

        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func parseCSV(from url: URL) async {
        do {
            // Read file content
            let csvContent = try String(contentsOf: url, encoding: .utf8)

            // Parse using CSVParsingActor
            let (headers, rows) = try await CSVParsingActor.shared.parseCSV(csvContent)

            // Store for column mapping
            parsedCSVData = (headers, rows)

        } catch {
            errorMessage = "CSV parsing failed: \(error.localizedDescription)"
        }
    }

    private func startImport() async {
        guard let parsedData = parsedCSVData else { return }

        // Reconstruct CSV content with proper RFC 4180 escaping
        let csvContent = ([parsedData.headers] + parsedData.rows)
            .map { row in
                row.map { field in
                    // CSV RFC 4180 escaping: wrap fields containing special chars
                    if field.contains(",") || field.contains("\"") || field.contains("\n") {
                        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return field
                }.joined(separator: ",")
            }
            .joined(separator: "\n")

        // Clear memory BEFORE async call
        parsedCSVData = nil

        // Start import via coordinator
        currentJobId = await coordinator.startCSVImport(
            csvContent: csvContent,
            mappings: columnMappings,
            strategy: duplicateStrategy,
            modelContext: modelContext
        )
    }

    @ViewBuilder
    private func jobProgressView(for jobId: JobIdentifier, status: JobStatus) -> some View {
        switch status {
        case .queued:
            PollingIndicator(stageName: "Preparing import...")

        case .active(let progress):
            VStack(spacing: 24) {
                ProgressBanner(
                    isShowing: .constant(true),
                    title: "Importing CSV",
                    message: progress.currentStatus
                )

                StagedProgressView(
                    stages: ["Parsing", "Importing", "Enriching"],
                    currentStageIndex: .constant(determineStage(progress)),
                    progress: .constant(progress.fractionCompleted)
                )

                // Progress details
                Text("\(progress.processedItems) of \(progress.totalItems) items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let eta = progress.estimatedTimeRemaining {
                    EstimatedTimeRemaining(completionDate: Date().addingTimeInterval(eta))
                }
            }
            .padding()

        case .completed(let log):
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Import Complete")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(log, id: \.self) { message in
                        HStack {
                            Text(message)
                                .font(.callout)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)
            }
            .padding()

        case .failed(let error):
            VStack(spacing: 16) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Import Failed")
                    .font(.title2.bold())

                Text(error)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }

                HStack(spacing: 12) {
                    Button("Retry") {
                        currentJobId = nil
                        showingFilePicker = true
                    }
                    .buttonStyle(.bordered)

                    Button("Dismiss") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeStore.primaryColor)
                }
            }
            .padding()

        case .cancelled:
            VStack(spacing: 16) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Import Cancelled")
                    .font(.title2.bold())

                Button("Start New Import") {
                    currentJobId = nil
                    showingFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .tint(themeStore.primaryColor)
            }
            .padding()
        }
    }

    private func determineStage(_ progress: JobProgress) -> Int {
        // Heuristic based on status message
        let status = progress.currentStatus.lowercased()
        if status.contains("pars") || status.contains("analyz") {
            return 0  // Parsing
        } else if status.contains("enrich") {
            return 2  // Enriching
        } else {
            return 1  // Importing
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
                        .foregroundStyle(.secondary)

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
    let headers: [String]
    let rows: [[String]]
    let onMappingsConfirmed: ([CSVParsingActor.ColumnMapping]) -> Void
    let onCancel: () -> Void
    let themeStore: iOS26ThemeStore

    @State private var mappings: [CSVParsingActor.ColumnMapping] = []
    @State private var showingPreview = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing columns...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
                .task {
                    await detectMappings()
                }
            } else {
                // Status header
                MappingStatusHeader(
                    mappings: mappings,
                    themeStore: themeStore
                )
                .padding()

                ScrollView {
                    VStack(spacing: 16) {
                        // Auto-detected mappings
                        ForEach(mappings.indices, id: \.self) { index in
                            MappingRowView(
                                mapping: $mappings[index],
                                themeStore: themeStore,
                                onFieldChange: { field in
                                    mappings[index].mappedField = field
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
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(SecondaryButtonStyle(themeStore: themeStore))

                    Button {
                        onMappingsConfirmed(mappings)
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Start Import")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(themeStore: themeStore))
                    .disabled(!canProceedWithImport())
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showingPreview) {
            PreviewSheetView(
                mappings: mappings,
                themeStore: themeStore
            )
        }
    }

    private func detectMappings() async {
        // Auto-detect column mappings
        let detected = await CSVParsingActor.shared.detectColumns(
            headers: headers,
            sampleRows: Array(rows.prefix(10))
        )
        mappings = detected
        isLoading = false
    }

    private func canProceedWithImport() -> Bool {
        let hasTitle = mappings.contains { $0.mappedField == .title }
        let hasAuthor = mappings.contains { $0.mappedField == .author }
        return hasTitle && hasAuthor
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)

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
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let remaining = progress.estimatedTimeRemaining {
                        Text(formatTimeRemaining(remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)

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