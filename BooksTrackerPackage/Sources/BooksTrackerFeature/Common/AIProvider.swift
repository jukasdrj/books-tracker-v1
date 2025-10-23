import Foundation

/// Image preprocessing configuration per provider
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

/// AI provider options for bookshelf scanning
public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case gemini = "gemini"
    case cloudflare = "cloudflare"

    public var id: String { rawValue }

    /// User-facing display name
    public var displayName: String {
        switch self {
        case .gemini:
            return "Gemini (Accurate)"
        case .cloudflare:
            return "Cloudflare (Fast)"
        }
    }

    /// Detailed description for Settings UI
    public var description: String {
        switch self {
        case .gemini:
            return "Google Gemini 2.5 Flash - Best accuracy, especially for ISBNs and small text. Processing time: 25-40 seconds."
        case .cloudflare:
            return "Cloudflare Workers AI (Llama 3.2) - Experimental fast mode. Processing time: 3-8 seconds. May miss some books."
        }
    }

    /// SF Symbol icon name
    public var icon: String {
        switch self {
        case .gemini:
            return "sparkles"
        case .cloudflare:
            return "bolt.fill"
        }
    }

    /// Image preprocessing configuration
    public var preprocessingConfig: ImagePreprocessingConfig {
        switch self {
        case .gemini:
            return ImagePreprocessingConfig(
                maxDimension: 3072,
                jpegQuality: 0.90,
                targetFileSizeKB: 400...600
            )
        case .cloudflare:
            return ImagePreprocessingConfig(
                maxDimension: 1536,
                jpegQuality: 0.85,
                targetFileSizeKB: 150...300
            )
        }
    }
}
