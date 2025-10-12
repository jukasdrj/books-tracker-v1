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
    @State private var showingResults = false
    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var cameraManager = CameraManager()

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
                        cameraSection

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
            .fullScreenCover(isPresented: $showCamera) {
                BookshelfCameraView(cameraManager: cameraManager) { imageData in
                    if let image = UIImage(data: imageData) {
                        capturedImage = image
                        Task {
                            await scanModel.uploadImage(image)
                        }
                    }
                    showCamera = false
                }
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

                    Text("Your photo is uploaded for AI analysis and is not stored.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
        .accessibilityLabel("Privacy notice: Your photo is uploaded for AI analysis and is not stored.")
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        VStack(spacing: 16) {
            Button(action: { showCamera = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(themeStore.primaryColor.gradient)
                        .symbolRenderingMode(.hierarchical)

                    Text("Scan with Camera")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Use your camera to scan a bookshelf")
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
                                .strokeBorder(
                                    themeStore.primaryColor.opacity(0.3),
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                )
                        }
                }
            }
            .accessibilityLabel("Scan with Camera")
            .accessibilityHint("Open the camera to scan your bookshelf")

            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .frame(maxHeight: 300)
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
                    // Action is now handled by the camera capture
                } label: {
                    HStack {
                        Image(systemName: "viewfinder")
                            .font(.title3)

                        Text("Analyze Photo")
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
                .disabled(capturedImage == nil)
                .opacity(capturedImage == nil ? 0.5 : 1.0)

            } else if scanModel.scanState == .processing {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Uploading and analyzing...")
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

@MainActor
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

    #if canImport(UIKit)
    func uploadImage(_ image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            scanState = .error("Failed to convert image to data")
            return
        }

        scanState = .processing

        // URL for the Cloudflare worker
        guard let url = URL(string: "https://books-api-proxy.your-worker-subdomain.workers.dev/api/scan-bookshelf") else {
            scanState = .error("Invalid worker URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            // For now, we'll just use the mocked response from the worker.
            // In the future, we would decode the actual response from the AI service.
            let decodedResponse = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)

            let detectedBooks = decodedResponse.items.map { item in
                DetectedBook(title: item.volumeInfo.title, author: item.volumeInfo.authors?.first ?? "", confidence: 0.9)
            }

            detectedCount = detectedBooks.count
            confirmedCount = detectedBooks.count
            uncertainCount = 0

            scanResult = ScanResult(
                detectedBooks: detectedBooks,
                totalProcessingTime: 1.0 // Placeholder
            )

            scanState = .completed

        } catch {
            scanState = .error(error.localizedDescription)
        }
    }
    #endif
}

// MARK: - Helper structs for decoding the mocked response

struct GoogleBooksResponse: Codable {
    let items: [GoogleBookItem]
}

struct GoogleBookItem: Codable {
    let volumeInfo: VolumeInfo
}

struct VolumeInfo: Codable {
    let title: String
    let authors: [String]?
}

// MARK: - Preview

#Preview {
    BookshelfScannerView()
        .modelContainer(for: [Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        .environment(iOS26ThemeStore())
}
