import Foundation
#if canImport(UIKit)
import UIKit
#endif

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

    /// Process bookshelf image with progress tracking.
    /// - Parameter image: UIImage to process
    /// - Parameter progressHandler: A closure to handle progress updates.
    /// - Returns: Tuple of detected books and suggestions
    @available(*, deprecated, message: "Use processBookshelfImageWithWebSocket for real-time progress updates. Polling method will be removed in Q1 2026.")
    func processBookshelfImageWithProgress(
        _ image: UIImage,
        progressHandler: @MainActor @escaping (Double, String) -> Void
    ) async throws -> ([DetectedBook], [SuggestionViewModel]) {
        // Step 1: Compress image to acceptable size
        guard let imageData = compressImage(image, maxSizeBytes: maxImageSize) else {
            throw BookshelfAIError.imageCompressionFailed
        }

        // Step 2: Start async scan job
        let jobResponse = try await startScanJob(imageData)
        let stages = jobResponse.stages

        // Step 3: Poll for completion using the enhanced generic utility
        let response = try await Utility.pollForCompletion(
            check: {
                let status = try await self.pollJobStatus(jobId: jobResponse.jobId)

                if status.stage == "complete", let result = status.result {
                    return .complete(result)
                }

                if status.stage == "error" {
                    let error = BookshelfAIError.serverError(500, status.error ?? "Unknown error during scan")
                    return .error(error)
                }

                let progress = self.calculateExpectedProgress(elapsed: status.elapsedTime, stages: stages)
                return .inProgress(progress: progress, metadata: status.stage)
            },
            progressHandler: { progress, stage in
                progressHandler(progress, stage)
            },
            interval: .seconds(2),
            timeout: .seconds(90)
        )

        // Step 4: Convert to detected books and suggestions
        let detectedBooks = response.books.compactMap { aiBook in
            convertToDetectedBook(aiBook)
        }

        let suggestions = SuggestionGenerator.generateSuggestions(from: response)

        return (detectedBooks, suggestions)
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

    /// Compress UIImage to JPEG with target size constraint.
    nonisolated private func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        // Target resolution: 1920x1080 for 4K-ish quality
        let targetWidth: CGFloat = 1920

        // Resize image if needed
        let resizedImage: UIImage
        if image.size.width > targetWidth {
            let scale = targetWidth / image.size.width
            let targetHeight = image.size.height * scale
            let targetSize = CGSize(width: max(1, targetWidth), height: max(1, targetHeight))

            // Use UIGraphicsImageRenderer instead of deprecated UIGraphicsBeginImageContext
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            resizedImage = image
        }

        // Try different compression qualities until we meet size constraint
        let compressionQualities: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5]

        for quality in compressionQualities {
            if let data = resizedImage.jpegData(compressionQuality: quality),
               data.count <= maxSizeBytes {
                return data
            }
        }

        // Fallback: use lowest quality
        return resizedImage.jpegData(compressionQuality: 0.5)
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

    private func startScanJob(_ imageData: Data) async throws -> ScanJobResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
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
