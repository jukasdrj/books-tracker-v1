import Foundation

/// Client-side fallback logic for generating suggestions when AI doesn't provide them
public struct SuggestionGenerator {

    /// Generate suggestions from AI response with client-side fallback
    public static func generateSuggestions(from response: BookshelfAIResponse) -> [SuggestionViewModel] {
        // Step 1: Use AI suggestions if available
        if let aiSuggestions = response.suggestions, !aiSuggestions.isEmpty {
            return aiSuggestions.map { SuggestionViewModel(from: $0) }
        }

        // Step 2: Client-side fallback analysis
        return analyzeAndGenerateFallbacks(from: response.books)
    }

    /// Analyze detected books and generate fallback suggestions
    private static func analyzeAndGenerateFallbacks(from books: [BookshelfAIResponse.AIDetectedBook]) -> [SuggestionViewModel] {
        var suggestions: [SuggestionViewModel] = []

        let totalBooks = books.count
        guard totalBooks > 0 else { return suggestions }

        let unreadableBooks = books.filter { $0.title == nil || $0.author == nil }
        let lowConfidenceBooks = books.filter { ($0.confidence ?? 0.0) < 0.7 }

        // Check 1: Unreadable books
        if unreadableBooks.count >= 2 {
            suggestions.append(
                SuggestionViewModel(
                    type: "unreadable_books",
                    severity: unreadableBooks.count > totalBooks / 2 ? "high" : "medium",
                    affectedCount: unreadableBooks.count
                )
            )
        }

        // Check 2: Low confidence (excluding already unreadable)
        let lowConfNotUnreadable = lowConfidenceBooks.filter { $0.title != nil && $0.author != nil }
        if lowConfNotUnreadable.count >= 3 {
            suggestions.append(
                SuggestionViewModel(
                    type: "low_confidence",
                    severity: "medium",
                    affectedCount: lowConfNotUnreadable.count
                )
            )
        }

        // Check 3: Overall quality indicator
        let avgConfidence = books.compactMap { $0.confidence }.reduce(0.0, +) / Double(totalBooks)
        if avgConfidence < 0.6 && suggestions.isEmpty {
            suggestions.append(
                SuggestionViewModel(
                    type: "lighting_issues",
                    severity: "medium",
                    affectedCount: nil
                )
            )
        }

        return suggestions
    }
}

/// View model for suggestions with display logic
public struct SuggestionViewModel: Identifiable {
    public let type: String
    public let severity: String
    public let affectedCount: Int?

    public var id: String { type }

    public var message: String {
        switch type {
        case "unreadable_books":
            return "Some books detected but text is unreadable. Try capturing from a more direct angle or with better lighting."
        case "low_confidence":
            return "Several books have low detection confidence. Improve focus or lighting for clearer spines."
        case "edge_cutoff":
            return "Books at the edges appear cut off. Recenter the shot to capture full spines."
        case "blurry_image":
            return "Image appears blurry. Hold the camera steady and ensure it's focused."
        case "glare_detected":
            return "Glare or reflections detected on book covers. Adjust angle or lighting to reduce shine."
        case "distance_too_far":
            return "Camera may be too far from the bookshelf. Move closer for better resolution."
        case "multiple_shelves":
            return "Multiple shelves detected. Try capturing one shelf at a time for better results."
        case "lighting_issues":
            return "Lighting appears insufficient. Try better lighting or use your device's flash."
        case "angle_issues":
            return "Camera angle makes spines hard to read. Hold the camera more directly facing the shelf."
        default:
            return "Image quality could be improved. Try better lighting, focus, or angle."
        }
    }

    public var iconName: String {
        switch severity {
        case "high": return "exclamationmark.triangle.fill"
        case "medium": return "info.circle.fill"
        default: return "lightbulb.fill"
        }
    }

    public init(type: String, severity: String, affectedCount: Int?) {
        self.type = type
        self.severity = severity
        self.affectedCount = affectedCount
    }

    public init(from aiSuggestion: BookshelfAIResponse.Suggestion) {
        self.type = aiSuggestion.type
        self.severity = aiSuggestion.severity
        self.affectedCount = aiSuggestion.affectedCount
        // Note: We ignore AI message and use our templated message
    }
}
