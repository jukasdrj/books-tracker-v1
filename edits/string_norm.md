import Foundation

public extension String {
    /// Normalizes a book title string by removing extraneous details like series names,
    /// subtitles, and edition markers, making it cleaner for external API searching.
    ///
    /// Examples:
    /// - "The Da Vinci Code: The Young Adult Adaptation" -> "The Da Vinci Code"
    /// - "Devil's Knot: The True Story of the West Memphis Three (Justice Knot, #1)" -> "Devil's Knot"
    /// - "Dept. of Speculation" -> "Dept of Speculation" (Removes extra punctuation)
    var normalizedTitleForSearch: String {
        var cleanTitle = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Remove series and edition details in parentheses: (Series Name, #1)
        // Regex pattern: \(.*\)
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)

        // 2. Remove series and edition details in square brackets: [Special Edition]
        // Regex pattern: \[.*\]
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s*\\[[^\\]]*\\]", with: "", options: .regularExpression)

        // 3. Strip everything after a colon or dash that suggests a subtitle or adaptation,
        // unless the title is extremely short (e.g., "It: A Novel" should keep "It")
        if cleanTitle.count > 10 {
            // Find the first colon or dash that separates the main title from the subtitle
            if let colonRange = cleanTitle.range(of: ":") {
                cleanTitle = String(cleanTitle[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else if let dashRange = cleanTitle.range(of: " - ") {
                cleanTitle = String(cleanTitle[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // 4. Clean up extra periods and spaces that don't belong
        cleanTitle = cleanTitle.replacingOccurrences(of: "Dept.", with: "Dept")
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        return cleanTitle
    }
}
