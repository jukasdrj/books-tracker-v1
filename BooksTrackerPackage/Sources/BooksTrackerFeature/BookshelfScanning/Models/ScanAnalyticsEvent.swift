import Foundation

/// Analytics event for bookshelf scan completion
public struct ScanAnalyticsEvent: Sendable {
    public let scanId: String
    public let provider: AIProvider
    public let booksDetected: Int
    public let strategy: ProgressStrategy
    public let success: Bool
    public let durationSeconds: Double
    public let errorMessage: String?

    public init(
        scanId: String,
        provider: AIProvider,
        booksDetected: Int,
        strategy: ProgressStrategy,
        success: Bool,
        durationSeconds: Double,
        errorMessage: String? = nil
    ) {
        self.scanId = scanId
        self.provider = provider
        self.booksDetected = booksDetected
        self.strategy = strategy
        self.success = success
        self.durationSeconds = durationSeconds
        self.errorMessage = errorMessage
    }

    /// Convert to dictionary for Firebase Analytics
    public var asDictionary: [String: Any] {
        var dict: [String: Any] = [
            "scan_id": scanId,
            "provider": provider.rawValue,
            "books_detected": booksDetected,
            "strategy": strategy.description,
            "success": success,
            "duration_seconds": durationSeconds
        ]

        if let errorMessage = errorMessage {
            dict["error_message"] = errorMessage
        }

        return dict
    }
}
