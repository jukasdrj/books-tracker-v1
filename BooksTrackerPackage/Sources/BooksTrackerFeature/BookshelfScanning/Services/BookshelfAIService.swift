import Foundation
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

struct BookshelfAIResponse: Codable, Sendable {
    let books: [AIDetectedBook]
    let suggestions: [Suggestion]? // Optional for backward compatibility
    let metadata: ImageMetadata?

    struct AIDetectedBook: Codable, Sendable {
        let title: String?
        let author: String?
        let boundingBox: BoundingBox
        let confidence: Double?
        let enrichmentStatus: String? // New field for enrichment status
        let isbn: String?
        let coverUrl: String?
        let publisher: String?
        let publicationYear: Int?

        struct BoundingBox: Codable, Sendable {
            let x1: Double
            let y1: Double
            let x2: Double
            let y2: Double
        }
    }

    struct Suggestion: Codable, Sendable, Identifiable {
        let type: String
        let severity: String
        let message: String
        let affectedCount: Int?

        var id: String { type } // Identifiable for ForEach
    }

    struct ImageMetadata: Codable, Sendable {
        let imageQuality: String?
        let lighting: String?
        let sharpness: String?
        let readableCount: Int?
    }
}

// MARK: - Bookshelf AI Service

/// Service for communicating with Cloudflare bookshelf-ai-worker.
/// Actor-isolated for thread-safe network operations.
actor BookshelfAIService {
    // MARK: - Configuration

    private let endpoint = URL(string: "https://bookshelf-ai-worker.jukasdrj.workers.dev")!
    private let timeout: TimeInterval = 70.0 // 70 seconds for AI processing + enrichment (Gemini: 25-40s, enrichment: 5-10s)
    private let maxImageSize: Int = 10_000_000 // 10MB max (matches worker limit)

    // MARK: - Singleton

    static let shared = BookshelfAIService()

    private init() {}

    // MARK: - Public API

    /// Process bookshelf image and return detected books.
    /// - Parameter image: UIImage to process (will be compressed)
    /// - Returns: Array of detected books with metadata
    func processBookshelfImage(_ image: UIImage) async throws -> [DetectedBook] {
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
        return response.books.compactMap { aiBook in
            convertToDetectedBook(aiBook)
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

    /// Compress UIImage to JPEG with target size constraint.
    nonisolated private func compressImage(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        // Target resolution: 1920x1080 for 4K-ish quality
        let targetWidth: CGFloat = 1920

        // Resize image if needed
        let resizedImage: UIImage
        if image.size.width > targetWidth {
            let scale = targetWidth / image.size.width
            let targetHeight = image.size.height * scale
            let targetSize = CGSize(width: targetWidth, height: targetHeight)

            UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
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
}
