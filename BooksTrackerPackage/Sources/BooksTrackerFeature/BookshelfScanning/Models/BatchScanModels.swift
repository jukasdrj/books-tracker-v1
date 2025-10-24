import Foundation
import SwiftUI

// MARK: - Captured Photo

/// Represents a captured photo in a batch scan session
public struct CapturedPhoto: Identifiable, Sendable {
    public let id: UUID
    public let image: UIImage
    public let timestamp: Date

    /// Maximum photos allowed per batch
    public static let maxPhotosPerBatch = 5

    public init(image: UIImage) {
        self.id = UUID()
        self.image = image
        self.timestamp = Date()
    }
}

// MARK: - Photo Status

/// Status of an individual photo in batch processing
public enum PhotoStatus: String, Codable, Sendable {
    case queued
    case processing
    case complete
    case error
}

// MARK: - Photo Progress

/// Progress information for a single photo in a batch
public struct PhotoProgress: Identifiable, Sendable {
    public let index: Int
    public var status: PhotoStatus
    public var progress: Double?
    public var booksFound: [DetectedBook]?
    public var error: String?

    public var id: Int { index }

    public init(index: Int) {
        self.index = index
        self.status = .queued
    }
}

// MARK: - Batch Progress

/// Overall progress for a batch scan job
@Observable
@MainActor
public final class BatchProgress: Sendable {
    public let jobId: String
    public let totalPhotos: Int
    public var photos: [PhotoProgress]
    public var overallStatus: String
    public var totalBooksFound: Int
    public var currentPhotoIndex: Int?

    public init(jobId: String, totalPhotos: Int) {
        self.jobId = jobId
        self.totalPhotos = totalPhotos
        self.photos = (0..<totalPhotos).map { PhotoProgress(index: $0) }
        self.overallStatus = "queued"
        self.totalBooksFound = 0
    }

    /// Update status for a specific photo
    public func updatePhoto(
        index: Int,
        status: PhotoStatus,
        booksFound: [DetectedBook]? = nil,
        error: String? = nil
    ) {
        guard index < photos.count else { return }

        photos[index].status = status

        if let booksFound {
            photos[index].booksFound = booksFound
            recalculateTotalBooks()
        }

        if let error {
            photos[index].error = error
        }

        if status == .processing {
            currentPhotoIndex = index
        }
    }

    /// Mark batch as complete
    public func complete(totalBooks: Int) {
        self.overallStatus = "complete"
        self.totalBooksFound = totalBooks
        self.currentPhotoIndex = nil
    }

    /// Check if all photos are complete
    public var isComplete: Bool {
        photos.allSatisfy { $0.status == .complete || $0.status == .error }
    }

    /// Count successful photos
    public var successCount: Int {
        photos.filter { $0.status == .complete }.count
    }

    /// Count failed photos
    public var errorCount: Int {
        photos.filter { $0.status == .error }.count
    }

    private func recalculateTotalBooks() {
        totalBooksFound = photos.compactMap { $0.booksFound?.count }.reduce(0, +)
    }
}

// MARK: - Batch Request

/// Request payload for batch scan endpoint
struct BatchScanRequest: Codable {
    let jobId: String
    let images: [ImageData]

    struct ImageData: Codable {
        let index: Int
        let data: String // Base64 encoded
    }
}

// MARK: - Batch WebSocket Messages

/// WebSocket message types for batch scanning
enum BatchWebSocketMessage: Codable {
    case batchInit(BatchInitMessage)
    case batchProgress(BatchProgressMessage)
    case batchComplete(BatchCompleteMessage)

    struct BatchInitMessage: Codable {
        let type: String
        let jobId: String
        let totalPhotos: Int
        let status: String
    }

    struct BatchProgressMessage: Codable {
        let type: String
        let jobId: String
        let currentPhoto: Int
        let totalPhotos: Int
        let photoStatus: String
        let booksFound: Int
        let totalBooksFound: Int
        let photos: [PhotoProgressData]

        struct PhotoProgressData: Codable {
            let index: Int
            let status: String
            let booksFound: Int?
            let error: String?
        }
    }

    struct BatchCompleteMessage: Codable {
        let type: String
        let jobId: String
        let totalBooks: Int
        let photoResults: [PhotoResult]
        let books: [AIDetectedBook]

        struct PhotoResult: Codable {
            let index: Int
            let status: String
            let booksFound: Int?
            let error: String?
        }
    }
}

// MARK: - AIDetectedBook

/// AI-detected book from backend (for batch complete message)
struct AIDetectedBook: Codable {
    let title: String
    let author: String?
    let isbn: String?
    let confidence: Double
}
