import Foundation

#if canImport(UIKit)
import UIKit

// MARK: - AI Service Errors

enum BookshelfAIError: Error, LocalizedError {
    case imageCompressionFailed
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingFailed(Error)
    case imageQualityRejected(String)

    var errorDescription: String? {
        switch self {
        case .imageCompressionFailed:
            return "Failed to compress image for upload"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received invalid response from AI service"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .imageQualityRejected(let reason):
            return "Image quality issue: \(reason)"
        }
    }
}

// MARK: - AI Response Models

public struct BookshelfAIResponse: Codable, Sendable {
    public let books: [AIDetectedBook]
    public let suggestions: [Suggestion]? // Optional for backward compatibility
    public let metadata: ImageMetadata?

    public struct AIDetectedBook: Codable, Sendable {
        public let title: String?
        public let author: String?
        public let boundingBox: BoundingBox
        public let confidence: Double?
        public let enrichmentStatus: String? // New field for enrichment status
        public let isbn: String?
        public let coverUrl: String?
        public let publisher: String?
        public let publicationYear: Int?

        public struct BoundingBox: Codable, Sendable {
            public let x1: Double
            public let y1: Double
            public let x2: Double
            public let y2: Double
        }
    }

    public struct Suggestion: Codable, Sendable, Identifiable {
        public let type: String
        public let severity: String
        public let message: String
        public let affectedCount: Int?

        public var id: String { type } // Identifiable for ForEach
    }

    public struct ImageMetadata: Codable, Sendable {
        public let imageQuality: String?
        public let lighting: String?
        public let sharpness: String?
        public let readableCount: Int?
    }
}

// MARK: - Bookshelf AI Service

/// Service for communicating with Cloudflare bookshelf-ai-worker.
/// Actor-isolated for thread-safe network operations.
actor BookshelfAIService {
    // MARK: - Configuration

    private let endpoint = URL(string: "https://bookshelf-ai-worker.jukasdrj.workers.dev/scan")!
    private let timeout: TimeInterval = 70.0 // 70 seconds for AI processing + enrichment (Gemini: 25-40s, enrichment: 5-10s)
    private let maxImageSize: Int = 10_000_000 // 10MB max (matches worker limit)

    // MARK: - Singleton

    static let shared = BookshelfAIService()

    private init() {}

    // MARK: - Provider Selection

    /// Read user-selected AI provider from UserDefaults
    /// UserDefaults is thread-safe, safe to call from actor context
    private func getSelectedProvider() -> AIProvider {
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? "gemini"
        return AIProvider(rawValue: raw) ?? .gemini
    }

    // MARK: - Public API

    /// Process bookshelf image and return detected books with suggestions.
    /// - Parameter image: UIImage to process (will be compressed)
    /// - Returns: Tuple of (detected books, suggestions for improvement)
    func processBookshelfImage(_ image: UIImage) async throws -> ([DetectedBook], [SuggestionViewModel]) {
        // Step 1: Compress image to acceptable size
        guard let imageData = compressImage(image, maxSizeBytes: maxImageSize) else {
            throw BookshelfAIError.imageCompressionFailed
        }

        // Step 2: Upload to Cloudflare Worker
        let response = try await uploadImage(imageData)

        // Step 3: Check image quality metadata
        if let metadata = response.metadata, let quality = metadata.imageQuality {
            if quality.lowercased().contains("poor") || quality.lowercased().contains("reject") {
                throw BookshelfAIError.imageQualityRejected(quality)
            }
        }

        // Step 4: Convert AI response to DetectedBook models
        let detectedBooks = response.books.compactMap { aiBook in
            convertToDetectedBook(aiBook)
        }

        // Step 5: Generate suggestions (AI-first, client fallback)
        let suggestions = SuggestionGenerator.generateSuggestions(from: response)

        // Return both books and suggestions
        return (detectedBooks, suggestions)
    }

    // MARK: - Progress Tracking

    /// Process bookshelf image with WebSocket real-time progress tracking.
    /// CRITICAL: Uses WebSocket-first protocol to prevent race conditions
    ///
    /// Flow:
    /// 1. Connect WebSocket BEFORE uploading image
    /// 2. Upload image (server waits for WebSocket ready signal)
    /// 3. Signal WebSocket ready to server
    /// 4. Server starts processing (WebSocket guaranteed listening)
    /// 5. Stream real-time progress
    ///
    /// - Parameters:
    ///   - image: UIImage to process
    ///   - progressHandler: Closure to handle progress updates (called on MainActor)
    /// - Returns: Tuple of detected books and suggestions
    /// - Throws: BookshelfAIError for image compression, network, or processing errors
    func processBookshelfImageWithWebSocket(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws(BookshelfAIError) -> ([DetectedBook], [SuggestionViewModel]) {
        // Read user-selected provider (UserDefaults is thread-safe)
        let provider = getSelectedProvider()

        // Generate jobId upfront - client controls the UUID for predictable WebSocket binding
        let jobId = UUID().uuidString

        // Log scan start (TODO: Replace with Firebase Analytics when configured)
        print("[Analytics] bookshelf_scan_started - provider: \(provider.rawValue), scan_id: \(jobId), image_width: \(Int(image.size.width)), image_height: \(Int(image.size.height))")

        // STEP 1: Connect WebSocket with client-generated jobId (prevents race condition)
        let wsManager = await WebSocketProgressManager()
        do {
            _ = try await wsManager.establishConnection(jobId: jobId)
            try await wsManager.configureForJob(jobId: jobId)
            print("✅ WebSocket connected for job \(jobId)")
        } catch {
            throw .networkError(error)
        }

        // STEP 2: Compress image with adaptive cascade algorithm
        let config = provider.preprocessingConfig
        let processedImage = image.resizeForAI(maxDimension: config.maxDimension)

        guard let imageData = compressImageAdaptive(processedImage, maxSizeBytes: maxImageSize) else {
            await wsManager.disconnect()
            throw .imageCompressionFailed
        }

        let imageSizeKB = imageData.count / 1024
        print("[Compression] Final size: \(imageSizeKB)KB (\(imageData.count) bytes) - Ready for upload")

        // STEP 3: Upload image with client-generated jobId
        do {
            _ = try await startScanJob(imageData, provider: provider, jobId: jobId)
            print("✅ Image uploaded with jobId: \(jobId)")
        } catch {
            await wsManager.disconnect()
            throw .networkError(error)
        }

        // STEP 5: Listen for real-time progress updates
        let result: Result<([DetectedBook], [SuggestionViewModel]), BookshelfAIError> = await withCheckedContinuation { continuation in
            Task { @MainActor in
                // Set progress handler directly (WebSocket already connected and configured)
                wsManager.setProgressHandler { jobProgress in
                    // Skip UI updates for keep-alive pings (prevents redundant re-renders)
                    guard jobProgress.keepAlive != true else {
                        print("🔁 Keep-alive ping received (skipping UI update)")
                        return
                    }

                    // Convert JobProgress to (Double, String) for progress handler
                    progressHandler(jobProgress.fractionCompleted, jobProgress.currentStatus)

                    // Check if job is complete
                    if jobProgress.currentStatus.lowercased().contains("complete") {
                        // Job finished - poll final status to get results
                        Task {
                            do {
                                let finalStatus = try await self.pollJobStatus(jobId: jobId)

                                if let response = finalStatus.result {
                                    wsManager.disconnect()

                                    // Convert to detected books and suggestions
                                    let detectedBooks = response.books.compactMap { aiBook in
                                        self.convertToDetectedBook(aiBook)
                                    }
                                    let suggestions = SuggestionGenerator.generateSuggestions(from: response)

                                    continuation.resume(returning: .success((detectedBooks, suggestions)))
                                }
                            } catch {
                                wsManager.disconnect()
                                continuation.resume(returning: .failure(.networkError(error)))
                            }
                        }
                    }

                    // Check if job errored
                    if jobProgress.currentStatus.lowercased().contains("error") {
                        wsManager.disconnect()
                        continuation.resume(returning: .failure(.serverError(500, "Job failed: \(jobProgress.currentStatus)")))
                    }
                }
            }
        }

        // Unwrap result
        switch result {
        case .success(let value):
            // Log scan completion (TODO: Replace with Firebase Analytics when configured)
            print("[Analytics] bookshelf_scan_completed - provider: \(provider.rawValue), books_detected: \(value.0.count), scan_id: \(jobId), success: true")
            return value
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Private Methods

    /// Upload compressed image data to Cloudflare Worker.
    private func uploadImage(_ imageData: Data) async throws -> BookshelfAIResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = imageData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BookshelfAIError.invalidResponse
            }

            // Check HTTP status
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BookshelfAIError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Decode JSON response
            let decoder = JSONDecoder()
            return try decoder.decode(BookshelfAIResponse.self, from: data)

        } catch let error as BookshelfAIError {
            throw error
        } catch let error as DecodingError {
            throw BookshelfAIError.decodingFailed(error)
        } catch {
            throw BookshelfAIError.networkError(error)
        }
    }

    /// Compress UIImage with adaptive cascade algorithm
    /// Guarantees <10MB output by cascading through resolution levels
    ///
    /// Strategy: Try multiple resolution + quality combinations
    /// - 1920px @ [0.9, 0.85, 0.8, 0.75, 0.7]
    /// - 1280px @ [0.85, 0.8, 0.75, 0.7, 0.6]
    /// - 960px @ [0.8, 0.75, 0.7, 0.6, 0.5]
    /// - 800px @ [0.7, 0.6, 0.5, 0.4]
    ///
    /// Each resolution reduction = ~50% size reduction,
    /// guarantees success without quality degradation
    ///
    /// - Parameter image: UIImage to compress
    /// - Parameter maxSizeBytes: Maximum output size (10MB)
    /// - Returns: Compressed JPEG data, or nil if truly impossible
    nonisolated private func compressImageAdaptive(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        // Adaptive cascade: Try each resolution + quality combination
        let compressionStrategies: [(resolution: CGFloat, qualities: [CGFloat])] = [
            (1920, [0.9, 0.85, 0.8, 0.75, 0.7]),   // Ultra HD
            (1280, [0.85, 0.8, 0.75, 0.7, 0.6]),   // Full HD
            (960,  [0.8, 0.75, 0.7, 0.6, 0.5]),    // HD
            (800,  [0.7, 0.6, 0.5, 0.4])           // VGA (emergency)
        ]

        // Try each resolution cascade
        for (resolution, qualities) in compressionStrategies {
            // Resize image once per resolution
            let resizedImage = image.resizeForAI(maxDimension: resolution)

            // Try quality levels for this resolution
            for quality in qualities {
                if let data = resizedImage.jpegData(compressionQuality: quality),
                   data.count <= maxSizeBytes {
                    let compressionRatio = Double(data.count) / Double(maxSizeBytes) * 100.0
                    print("[Compression] ✅ Success: \(Int(resolution))px @ \(Int(quality * 100))% quality = \(data.count / 1000)KB (\(String(format: "%.1f", compressionRatio))% of limit)")
                    return data
                }
            }
        }

        // Absolute fallback: Minimal quality thumbnail
        // Should only reach here with extremely problematic images
        let fallbackImage = image.resizeForAI(maxDimension: 640)
        if let data = fallbackImage.jpegData(compressionQuality: 0.3) {
            print("[Compression] ⚠️  Fallback: 640px @ 30% quality = \(data.count / 1000)KB (last resort)")
            return data
        }

        // This should never happen in practice
        print("[Compression] ❌ CRITICAL: Image compression completely failed")
        return nil
    }

    /// Legacy compression method (for backward compatibility)
    /// Deprecated: Use compressImageAdaptive() instead
    nonisolated private func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        return compressImageAdaptive(image, maxSizeBytes: maxSizeBytes)
    }

    /// Convert AI response book to DetectedBook model.
    nonisolated private func convertToDetectedBook(_ aiBook: BookshelfAIResponse.AIDetectedBook) -> DetectedBook? {
        // Calculate CGRect from normalized coordinates
        let boundingBox = CGRect(
            x: aiBook.boundingBox.x1,
            y: aiBook.boundingBox.y1,
            width: aiBook.boundingBox.x2 - aiBook.boundingBox.x1,
            height: aiBook.boundingBox.y2 - aiBook.boundingBox.y1
        )

        // Determine initial status from enrichment data
        let status: DetectionStatus
        switch aiBook.enrichmentStatus?.uppercased() {
        case "ENRICHED", "FOUND":
            status = .detected
        case "UNCERTAIN", "NEEDS_REVIEW":
            status = .uncertain
        case "REJECTED":
            status = .rejected
        default:
            // Fallback for nil or unknown status
            if aiBook.title == nil || aiBook.author == nil {
                status = .uncertain
            } else {
                status = .detected
            }
        }

        // Use the direct confidence score from the API
        let confidence = aiBook.confidence ?? 0.5

        // Generate raw text from available data
        let rawText = [aiBook.title, aiBook.author]
            .compactMap { $0 }
            .joined(separator: " by ")

        return DetectedBook(
            isbn: aiBook.isbn,
            title: aiBook.title,
            author: aiBook.author,
            confidence: confidence,
            boundingBox: boundingBox,
            rawText: rawText.isEmpty ? "Unreadable spine" : rawText,
            status: status
        )
    }

    // MARK: - Progress Tracking Methods (Swift 6.2 Task Pattern)

    private func startScanJob(_ imageData: Data, provider: AIProvider, jobId: String) async throws -> ScanJobResponse {
        // Append jobId to URL for client-controlled WebSocket binding
        let urlWithJob = URL(string: "\(endpoint.absoluteString)?jobId=\(jobId)")!

        var request = URLRequest(url: urlWithJob)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(provider.rawValue, forHTTPHeaderField: "X-AI-Provider")
        request.httpBody = imageData
        request.timeoutInterval = timeout // Use same timeout as uploadImage (70s for AI + enrichment)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 202 else {
            throw BookshelfAIError.invalidResponse
        }

        return try JSONDecoder().decode(ScanJobResponse.self, from: data)
    }

    /// Calculate expected progress based on elapsed time and stages
    nonisolated func calculateExpectedProgress(
        elapsed: Int,
        stages: [ScanJobResponse.StageMetadata]
    ) -> Double {
        var cumulativeTime = 0

        for (index, stage) in stages.enumerated() {
            cumulativeTime += stage.typicalDuration

            if elapsed < cumulativeTime {
                let stageElapsed = elapsed - (cumulativeTime - stage.typicalDuration)
                let stageProgress = Double(stageElapsed) / Double(stage.typicalDuration)

                let previousProgress = index > 0 ? stages[index - 1].progress : 0.0
                let currentStageRange = stage.progress - previousProgress

                return min(1.0, previousProgress + (stageProgress * currentStageRange))
            }
        }

        return stages.last?.progress ?? 1.0
    }

    /// Poll job status from server (used by BookshelfScanJob)
    func pollJobStatus(jobId: String) async throws -> JobStatusResponse {
        let statusURL = URL(string: "https://bookshelf-ai-worker.jukasdrj.workers.dev/scan/status/\(jobId)")!

        // Retry logic (3 attempts)
        var retries = 3

        while retries > 0 {
            do {
                let (data, response) = try await URLSession.shared.data(from: statusURL)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw BookshelfAIError.invalidResponse
                }

                // Handle 404 gracefully (job expired)
                if httpResponse.statusCode == 404 {
                    throw BookshelfAIError.serverError(404, "Scan job expired")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw BookshelfAIError.serverError(httpResponse.statusCode, "Status check failed")
                }

                return try JSONDecoder().decode(JobStatusResponse.self, from: data)

            } catch {
                retries -= 1
                if retries == 0 { throw error }
                try await Task.sleep(for: .seconds(2))
            }
        }

        throw BookshelfAIError.networkError(NSError(domain: "MaxRetries", code: -1))
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    /// Resize image for AI processing without upscaling
    func resizeForAI(maxDimension: CGFloat) -> UIImage {
        let scale = maxDimension / max(size.width, size.height)
        if scale >= 1 { return self } // Don't upscale

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

#endif  // canImport(UIKit)
