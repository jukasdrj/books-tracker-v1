import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
public struct CSVImportFlowView: View {

    // MARK: - State

    @StateObject private var syncCoordinator = SyncCoordinator.shared
    @StateObject private var progressTracker = PollingProgressTracker.shared
    @State private var fileContent: String?
    @State private var mappings: [CSVParsingActor.ColumnMapping] = []
    @State private var duplicateStrategy: CSVImportService.DuplicateStrategy = .smart
    @State private var showingFilePicker = false

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore

    public init() {}

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                themeStore.backgroundGradient.ignoresSafeArea()

                Group {
                    switch viewState {
                    case .idle:
                        FileSelectionView(showingFilePicker: $showingFilePicker, themeStore: themeStore)
                    case .analyzing:
                        AnalyzingFileView(themeStore: themeStore)
                    case .mapping:
                        ColumnMappingView(mappings: $mappings, themeStore: themeStore, onStartImport: startImport)
                    case .importing:
                        ImportProgressView(jobId: syncCoordinator.activeJobId, themeStore: themeStore)
                    case .enriching:
                        EnrichmentProgressView(jobId: syncCoordinator.activeJobId, themeStore: themeStore)
                    case .completed:
                        if let result = syncCoordinator.jobResult {
                            ImportResultsView(result: result, themeStore: themeStore, onDone: { dismiss() })
                        } else {
                            ImportCompletedView(onDone: { dismiss() })
                        }
                    case .failed(let error):
                        ImportErrorView(error: error, themeStore: themeStore, onRetry: { self.fileContent = nil })
                    }
                }
                .animation(.smooth(duration: 0.3), value: viewState)
            }
            .navigationTitle("Import Books")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                handleFileSelection(result)
            }
        }
    }

    // MARK: - Computed Properties

    private var viewState: ViewState {
        guard let jobId = syncCoordinator.activeJobId, let status = progressTracker.jobStatus[jobId] else {
            if fileContent != nil {
                return .mapping
            }
            return .idle
        }

        switch status {
        case .queued:
            return .analyzing
        case .active:
            if jobId.jobType == "ENRICHMENT" {
                return .enriching
            }
            return .importing
        case .completed:
            if jobId.jobType == "ENRICHMENT" {
                return .completed
            }
            return .enriching // In a real scenario, you'd want to wait for the enrichment job to start
        case .failed(let error):
            return .failed(error)
        case .cancelled:
            return .idle
        }
    }

    // MARK: - Private Methods

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    self.fileContent = content
                    let parsedData = try await CSVParsingActor.shared.parseCSV(content)
                    self.mappings = await CSVParsingActor.shared.detectColumns(headers: parsedData.headers, sampleRows: Array(parsedData.rows.prefix(10)))
                } catch {
                    // Handle error
                }
            }
        case .failure(let error):
            // Handle error
            print(error)
        }
    }

    private func startImport() {
        guard let fileContent = fileContent else { return }

        _ = syncCoordinator.startCsvImport(
            fileName: "import.csv",
            csvContent: fileContent,
            mappings: mappings,
            duplicateStrategy: duplicateStrategy,
            modelContext: modelContext
        )
    }
}

// MARK: - ViewState Enum

extension CSVImportFlowView {
    enum ViewState: Equatable {
        case idle
        case analyzing
        case mapping
        case importing
        case enriching
        case completed
        case failed(String)
    }
}

// MARK: - Subviews

private struct ImportProgressView: View {
    var jobId: JobIdentifier?
    @StateObject private var progressTracker = PollingProgressTracker.shared
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack {
            if let jobId = jobId, let status = progressTracker.jobStatus[jobId], case .active(let progress) = status {
                ProgressView(value: progress.fractionCompleted)
                Text("Importing: \(progress.currentStatus)")
            } else {
                Text("Preparing to import...")
            }
        }
    }
}

private struct EnrichmentProgressView: View {
    var jobId: JobIdentifier?
    @StateObject private var progressTracker = PollingProgressTracker.shared
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack {
            if let jobId = jobId, let status = progressTracker.jobStatus[jobId], case .active(let progress) = status {
                ProgressView(value: progress.fractionCompleted)
                Text("Enriching: \(progress.currentStatus)")
            } else {
                Text("Preparing to enrich...")
            }
        }
    }
}

private struct ImportCompletedView: View {
    var onDone: () -> Void

    var body: some View {
        VStack {
            Text("Import and Enrichment Complete")
            Button("Done", action: onDone)
        }
    }
}

private struct ImportErrorView: View {
    var error: String
    var onRetry: () -> Void
    let themeStore: iOS26ThemeStore

    var body: some View {
        VStack {
            Text("Import Failed: \(error)")
            Button("Retry", action: onRetry)
        }
    }
}

// ... (Rest of the original subviews can be kept if they are used)