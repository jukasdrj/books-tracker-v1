import SwiftUI
import SwiftData

// MARK: - Complete Integration Example

/// Example showing how all Live Activity components work together
/// This demonstrates the complete user flow with all UI elements
@available(iOS 16.2, *)
struct CompleteImportFlowExample: View {

    // MARK: - State

    @StateObject private var importService: CSVImportService
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.dismiss) private var dismiss

    // Banner visibility
    @State private var showBackgroundBanner = false
    @State private var showFloatingButton = false

    // Completion notification
    @State private var showCompletionNotification = false
    @State private var completionType: ImportCompletionNotification.NotificationType?

    // Navigation
    @State private var isShowingImportView = true
    @State private var lastProgress: Double = 0

    // Accessibility
    private let accessibilityAnnouncer = ImportProgressAccessibilityAnnouncer.shared
    private let stateAnnouncer = ImportStateChangeAnnouncer.shared

    // MARK: - Initialization

    init(importService: CSVImportService) {
        _importService = StateObject(wrappedValue: importService)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Main content area
            mainContent

            // Background import indicators (when user navigates away)
            backgroundIndicators

            // Completion notification
            completionNotificationView
        }
        .onChange(of: importService.importState) { _, newState in
            handleStateChange(newState)
        }
        .onChange(of: importService.progress.percentComplete) { _, newProgress in
            handleProgressChange(newProgress)
        }
        .onAppear {
            setupAccessibility()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isShowingImportView {
            // Import view (shows progress)
            CSVImportFlowView()
                .transition(.move(edge: .trailing))
        } else {
            // Other app content (library, search, etc.)
            LibraryPlaceholderView {
                // User wants to return to import
                withAnimation {
                    isShowingImportView = true
                    showBackgroundBanner = false
                    showFloatingButton = false
                }
            }
        }
    }

    // MARK: - Background Indicators

    @ViewBuilder
    private var backgroundIndicators: some View {
        if !isShowingImportView && importService.importState == .importing {
            VStack(spacing: 16) {
                // Top banner
                BackgroundImportBanner(
                    isShowing: $showBackgroundBanner,
                    processedBooks: importService.progress.processedRows,
                    totalBooks: importService.progress.totalRows,
                    currentBookTitle: importService.progress.currentBook
                ) {
                    // Return to import view
                    withAnimation(.smooth(duration: 0.4)) {
                        isShowingImportView = true
                        showBackgroundBanner = false
                    }
                }
                .zIndex(100)

                Spacer()

                // Floating action button (bottom of screen)
                ReturnToImportButton(isShowing: $showFloatingButton) {
                    withAnimation(.smooth(duration: 0.4)) {
                        isShowingImportView = true
                        showFloatingButton = false
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Completion Notification

    @ViewBuilder
    private var completionNotificationView: some View {
        if showCompletionNotification, let type = completionType {
            ImportCompletionNotification(
                isShowing: $showCompletionNotification,
                notificationType: type,
                onDismiss: {
                    completionType = nil
                },
                onViewDetails: {
                    withAnimation {
                        isShowingImportView = true
                    }
                }
            )
            .zIndex(200)
        }
    }

    // MARK: - State Handling

    private func handleStateChange(_ newState: CSVImportService.ImportState) {
        // Announce state changes for VoiceOver
        stateAnnouncer.announceStateChange(newState)

        switch newState {
        case .idle:
            break

        case .analyzingFile:
            break

        case .mappingColumns:
            break

        case .importing:
            // Import started
            accessibilityAnnouncer.announceImportStart(
                totalBooks: importService.progress.totalRows
            )

            // Show background indicators if user navigates away
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !isShowingImportView {
                    showBackgroundBanner = true
                    showFloatingButton = true
                }
            }

        case .completed(let result):
            // Import finished successfully
            handleImportCompletion(result)

        case .failed(let error):
            // Import failed
            handleImportFailure(error)
        }
    }

    private func handleProgressChange(_ newProgress: Double) {
        // Announce milestone progress
        accessibilityAnnouncer.announceProgressMilestone(
            newProgress,
            processedBooks: importService.progress.processedRows,
            totalBooks: importService.progress.totalRows
        )

        lastProgress = newProgress
    }

    private func handleImportCompletion(_ result: CSVImportService.ImportResult) {
        // Hide background indicators
        showBackgroundBanner = false
        showFloatingButton = false

        // Announce final results
        accessibilityAnnouncer.announceFinalResults(
            imported: result.successCount,
            duplicates: result.duplicateCount,
            errors: result.errorCount,
            duration: result.duration
        )

        // Show completion notification
        completionType = .success(
            imported: result.successCount,
            duplicates: result.duplicateCount,
            errors: result.errorCount
        )

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            showCompletionNotification = true
        }

        // Auto-dismiss notification after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                showCompletionNotification = false
            }
        }
    }

    private func handleImportFailure(_ error: String) {
        // Hide background indicators
        showBackgroundBanner = false
        showFloatingButton = false

        // Show failure notification
        completionType = .failure(message: error)

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            showCompletionNotification = true
        }
    }

    private func setupAccessibility() {
        // Configure accessibility for this view
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

// MARK: - Library Placeholder View

/// Placeholder for main app content
struct LibraryPlaceholderView: View {
    let onReturnToImport: () -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(themeStore.primaryColor.gradient)

                Text("Your Library")
                    .font(.largeTitle.bold())

                Text("Import in progress in background")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    onReturnToImport()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("View Import Progress")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(themeStore.primaryColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Library")
        }
    }
}

// MARK: - Usage Examples

#if DEBUG
@available(iOS 16.2, *)
struct ImportProgressIntegration_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Example 1: Import in progress (foreground)
            CompleteImportFlowExample(
                importService: MockImportService.importing()
            )
            .previewDisplayName("Importing (Foreground)")

            // Example 2: Import in progress (background)
            CompleteImportFlowExample(
                importService: MockImportService.importing()
            )
            .previewDisplayName("Importing (Background)")

            // Example 3: Import completed
            CompleteImportFlowExample(
                importService: MockImportService.completed()
            )
            .previewDisplayName("Completed")

            // Example 4: Import failed
            CompleteImportFlowExample(
                importService: MockImportService.failed()
            )
            .previewDisplayName("Failed")
        }
    }
}

// MARK: - Mock Service for Previews

class MockImportService: CSVImportService {
    static func importing() -> MockImportService {
        let service = MockImportService(modelContext: .preview)
        service.importState = .importing
        service.progress = ImportProgress(
            totalRows: 1500,
            processedRows: 750,
            successfulImports: 725,
            skippedDuplicates: 20,
            failedImports: 5,
            currentBook: "The Way of Kings by Brandon Sanderson",
            startTime: Date().addingTimeInterval(-600)
        )
        return service
    }

    static func completed() -> MockImportService {
        let service = MockImportService(modelContext: .preview)
        service.importState = .completed(
            ImportResult(
                successCount: 1450,
                duplicateCount: 45,
                errorCount: 5,
                importedWorks: [],
                errors: [],
                duration: 720
            )
        )
        return service
    }

    static func failed() -> MockImportService {
        let service = MockImportService(modelContext: .preview)
        service.importState = .failed("Network connection lost during import")
        return service
    }
}

extension ModelContext {
    static var preview: ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self,
            configurations: config
        )
        return ModelContext(container)
    }
}
#endif

// MARK: - Integration Checklist

/**
 ## Integration Checklist for Live Activity

 ### Prerequisites
 - [x] iOS 16.2+ target
 - [x] ActivityKit framework imported
 - [x] Live Activity entitlement enabled
 - [x] Widget extension configured

 ### Implementation Steps
 1. [x] Add ImportActivityAttributes.swift to project
 2. [x] Add ImportLiveActivityView.swift to widget target
 3. [x] Update CSVImportService with Live Activity calls
 4. [x] Add BackgroundImportBanner to parent views
 5. [x] Integrate ImportProgressAccessibility
 6. [x] Test on physical device (Live Activity doesn't work in simulator)

 ### Testing
 - [ ] Start import and verify Live Activity appears
 - [ ] Lock device and check Lock Screen
 - [ ] Long-press Dynamic Island (iPhone 14 Pro+)
 - [ ] Navigate away and verify background banner
 - [ ] Complete import and verify notification
 - [ ] Test with VoiceOver enabled
 - [ ] Test with largest Dynamic Type
 - [ ] Test with Reduce Motion enabled

 ### Accessibility Verification
 - [ ] VoiceOver announces progress milestones
 - [ ] All buttons have accessibility labels
 - [ ] Progress view has accessibility value
 - [ ] Custom actions work correctly
 - [ ] Text contrast meets WCAG AA (4.5:1)
 - [ ] Layout works at 320% text size

 ### Performance Verification
 - [ ] Updates throttled to 1/second maximum
 - [ ] Battery impact < 5% for 1500 book import
 - [ ] Memory usage < 20MB
 - [ ] No crashes or hangs
 - [ ] Graceful handling of failures
 */
