import SwiftUI
import PhotosUI
import SwiftData

// MARK: - Bookshelf Scanner View

/// Main view for scanning bookshelf photos and detecting books
/// Phase 1: PhotosPicker → VisionProcessingActor → Review → Add to library
@MainActor
public struct BookshelfScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    // MARK: - State Management

    @State private var scanModel = BookshelfScanModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingResults = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        // Privacy disclosure banner
                        privacyDisclosureBanner

                        // Photo selection area
                        photoSelectionSection

                        // Statistics (if scanning or completed)
                        if scanModel.scanState != .idle {
                            statisticsSection
                        }

                        // Action buttons
                        actionButtonsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Scan Bookshelf (Beta)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(themeStore.primaryColor)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if scanModel.scanState == .processing {
                        ProgressView()
                            .tint(themeStore.primaryColor)
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                ScanResultsView(
                    scanResult: scanModel.scanResult,
                    modelContext: modelContext,
                    onDismiss: {
                        showingResults = false
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Privacy Disclosure Banner

    private var privacyDisclosureBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(themeStore.primaryColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Private & Secure")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Analysis happens on this iPhone. Photos are not uploaded to servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(.orange)
                Text("Uses network for book matches after on-device detection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy notice: Analysis happens on this iPhone. Photos are not uploaded.")
    }

    // MARK: - Photo Selection Section

    private var photoSelectionSection: some View {
        VStack(spacing: 16) {
            // PhotosPicker
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(themeStore.primaryColor.gradient)
                        .symbolRenderingMode(.hierarchical)

                    Text("Select Bookshelf Photos")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Choose up to 10 photos of your bookshelf")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(themeStore.primaryColor.opacity(0.3), lineWidth: 2)
                                .strokeStyle(.init(lineWidth: 2, dash: [8, 4]))
                        }
                }
            }
            .photosPickerStyle(.automatic)
            .onChange(of: selectedItems) { oldValue, newValue in
                scanModel.photosSelected(newValue.count)
            }
            .accessibilityLabel("Select bookshelf photos")
            .accessibilityHint("Choose up to 10 photos to scan for book spines")

            // Selected photos count
            if !selectedItems.isEmpty {
                HStack {
                    Image(systemName: "photo.stack")
                        .foregroundStyle(themeStore.primaryColor)
                    Text("\(selectedItems.count) photo\(selectedItems.count == 1 ? "" : "s") selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 12) {
            Text("Scan Progress")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 20) {
                statisticBadge(
                    icon: "books.vertical.fill",
                    value: "\(scanModel.detectedCount)",
                    label: "Detected"
                )

                statisticBadge(
                    icon: "checkmark.circle.fill",
                    value: "\(scanModel.confirmedCount)",
                    label: "Ready"
                )

                statisticBadge(
                    icon: "questionmark.circle.fill",
                    value: "\(scanModel.uncertainCount)",
                    label: "Review"
                )
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func statisticBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(themeStore.primaryColor)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // Primary action button
            if scanModel.scanState == .idle {
                Button {
                    Task {
                        await scanModel.startScanning(selectedItems)
                    }
                } label: {
                    HStack {
                        Image(systemName: "viewfinder")
                            .font(.title3)

                        Text("Analyze Photos")
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
                .disabled(selectedItems.isEmpty)
                .opacity(selectedItems.isEmpty ? 0.5 : 1.0)
                .accessibilityLabel("Analyze photos")
                .accessibilityHint(selectedItems.isEmpty ? "Select photos first" : "Start on-device book detection")

            } else if scanModel.scanState == .processing {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Analyzing on device...")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(themeStore.primaryColor.gradient)
                }

            } else if scanModel.scanState == .completed {
                Button {
                    showingResults = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)

                        Text("Review Results (\(scanModel.detectedCount))")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.gradient)
                    }
                }
                .accessibilityLabel("Review \(scanModel.detectedCount) detected books")
            }

            // Tips section
            if scanModel.scanState == .idle {
                tipsSection
            }
        }
    }

    // MARK: - Tips Section

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips for Best Results")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                tipRow(icon: "sun.max.fill", text: "Use good lighting")
                tipRow(icon: "arrow.up.backward.and.arrow.down.forward", text: "Keep camera level with spines")
                tipRow(icon: "camera.metering.center.weighted", text: "Get close enough to read titles")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.caption)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bookshelf Scan Model

@Observable
class BookshelfScanModel {
    var scanState: ScanState = .idle
    var detectedCount: Int = 0
    var confirmedCount: Int = 0
    var uncertainCount: Int = 0
    var scanResult: ScanResult?

    enum ScanState: Equatable {
        case idle
        case processing
        case completed
        case error(String)
    }

    func photosSelected(_ count: Int) {
        // Reset state when new photos selected
        if scanState != .processing {
            scanState = .idle
            detectedCount = 0
            confirmedCount = 0
            uncertainCount = 0
            scanResult = nil
        }
    }

    #if canImport(UIKit)
    @MainActor
    func startScanning(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        scanState = .processing

        do {
            // Step 1: Load images from PhotosPicker
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }

            guard !images.isEmpty else {
                scanState = .error("Could not load images")
                return
            }

            // Step 2: Process with Vision framework (on-device)
            let startTime = Date()
            let detectedBooks = try await VisionProcessingActor.shared.detectBooks(in: images)
            let processingTime = Date().timeIntervalSince(startTime)

            // Step 3: Update statistics
            detectedCount = detectedBooks.count
            confirmedCount = detectedBooks.filter { $0.confidence >= 0.7 }.count
            uncertainCount = detectedBooks.filter { $0.confidence < 0.5 }.count

            // Step 4: Store results
            scanResult = ScanResult(
                detectedBooks: detectedBooks,
                totalProcessingTime: processingTime
            )

            scanState = .completed

        } catch {
            scanState = .error(error.localizedDescription)
        }
    }
    #endif
}

// MARK: - Preview

#Preview {
    BookshelfScannerView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .environment(iOS26ThemeStore())
}
