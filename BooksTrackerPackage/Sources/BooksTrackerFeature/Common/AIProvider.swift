import Foundation

/// Image preprocessing configuration for Gemini AI
public struct ImagePreprocessingConfig: Sendable {
    public let maxDimension: CGFloat
    public let jpegQuality: CGFloat
    public let targetFileSizeKB: ClosedRange<Int>

    public init(maxDimension: CGFloat, jpegQuality: CGFloat, targetFileSizeKB: ClosedRange<Int>) {
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
        self.targetFileSizeKB = targetFileSizeKB
    }
}

/// AI provider for bookshelf scanning (Gemini 2.0 Flash only)
public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case geminiFlash = "gemini-flash"

    public var id: String { rawValue }

    /// User-facing display name
    public var displayName: String {
        "Gemini Flash (Google)"
    }

    /// Detailed description for Settings UI
    public var description: String {
        "Fast and accurate model from Google with 2M token context window. Best for ISBNs and small text. Processing: 25-40s."
    }

    /// SF Symbol icon name
    public var icon: String {
        "sparkles"
    }

    /// Image preprocessing configuration (optimized for Gemini's 2M token context)
    public var preprocessingConfig: ImagePreprocessingConfig {
        ImagePreprocessingConfig(
            maxDimension: 3072,
            jpegQuality: 0.90,
            targetFileSizeKB: 400...600
        )
    }
}
