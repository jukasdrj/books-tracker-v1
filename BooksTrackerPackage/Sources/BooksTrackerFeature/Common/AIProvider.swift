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
    case geminiFlash = "gemini-flash"
    case llava = "cf-llava-1.5-7b"
    case qwen = "cf-uform-gen2-qwen-500m"
    case llamaVision = "cf-llama-3.2-11b-vision"

    public var id: String { rawValue }

    /// User-facing display name
    public var displayName: String {
        switch self {
        case .geminiFlash:
            return "Gemini Flash (Google)"
        case .llava:
            return "LLaVA 1.5 (Cloudflare)"
        case .qwen:
            return "Qwen/UForm (Cloudflare - Fast)"
        case .llamaVision:
            return "Llama 3.2 Vision (Cloudflare - Accurate)"
        }
    }

    /// Detailed description for Settings UI
    public var description: String {
        switch self {
        case .geminiFlash:
            return "Fast and capable model from Google. Best for ISBNs and small text. Processing: 25-40s."
        case .llava:
            return "Good balance of speed and accuracy. Processing: 5-12s."
        case .qwen:
            return "Very fast smaller model. Processing: 3-8s. May miss some books."
        case .llamaVision:
            return "Larger, more accurate model from Meta. Processing: 8-15s."
        }
    }

    /// SF Symbol icon name
    public var icon: String {
        switch self {
        case .geminiFlash:
            return "sparkles"
        case .llava:
            return "eye"
        case .qwen:
            return "hare"
        case .llamaVision:
            return "brain.head.profile"
        }
    }

    /// Helper to know if it's a Cloudflare model
    public var isCloudflare: Bool {
        switch self {
        case .geminiFlash:
            return false
        default:
            return true
        }
    }

    /// Map to the actual Cloudflare model ID string
    public var cloudflareModelId: String? {
        switch self {
        case .llava:
            return "@cf/llava-hf/llava-1.5-7b-hf"
        case .qwen:
            return "@cf/unum/uform-gen2-qwen-500m"
        case .llamaVision:
            return "@cf/meta/llama-3.2-11b-vision-instruct"
        case .geminiFlash:
            return nil
        }
    }

    /// Image preprocessing configuration
    public var preprocessingConfig: ImagePreprocessingConfig {
        switch self {
        case .geminiFlash:
            return ImagePreprocessingConfig(
                maxDimension: 3072,
                jpegQuality: 0.90,
                targetFileSizeKB: 400...600
            )
        case .llava:
            return ImagePreprocessingConfig(
                maxDimension: 2048,
                jpegQuality: 0.87,
                targetFileSizeKB: 250...400
            )
        case .qwen:
            return ImagePreprocessingConfig(
                maxDimension: 1536,
                jpegQuality: 0.85,
                targetFileSizeKB: 150...300
            )
        case .llamaVision:
            return ImagePreprocessingConfig(
                maxDimension: 2560,
                jpegQuality: 0.88,
                targetFileSizeKB: 300...500
            )
        }
    }
}
