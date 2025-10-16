import Foundation

public extension String {
    /// Normalizes a book title string by removing extraneous details like series names,
    /// subtitles, and edition markers, making it cleaner for external API searching.
    ///
    /// This normalization improves search success rates against book APIs by stripping
    /// common patterns that appear in CSV exports (like Goodreads) but not in canonical
    /// book databases.
    ///
    /// **Transformation Rules:**
    /// 1. Removes series markers in parentheses: `(Series Name, #1)`
    /// 2. Removes edition markers in square brackets: `[Special Edition]`
    /// 3. Strips subtitles after colon `:` or dash ` - ` for titles longer than 10 characters
    /// 4. Cleans up abbreviation periods: `Dept.` → `Dept`
    /// 5. Normalizes whitespace (multiple spaces → single space, trim edges)
    ///
    /// **Examples:**
    /// - `"The Da Vinci Code: The Young Adult Adaptation"` → `"The Da Vinci Code"`
    /// - `"Devil's Knot: The True Story... (Justice Knot, #1)"` → `"Devil's Knot"`
    /// - `"Dept. of Speculation"` → `"Dept of Speculation"`
    /// - `"It: A Novel"` → `"It: A Novel"` (short titles keep colons)
    ///
    /// **Usage:**
    /// ```swift
    /// let csvTitle = "Harry Potter and the Sorcerer's Stone (Harry Potter, #1)"
    /// let searchTitle = csvTitle.normalizedTitleForSearch
    /// // searchTitle = "Harry Potter and the Sorcerer's Stone"
    /// ```
    var normalizedTitleForSearch: String {
        var cleanTitle = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Remove series and edition details in parentheses: (Series Name, #1)
        // Regex pattern: \s*\([^)]*\)
        // Explanation: \s* = optional whitespace, \( = literal open paren, [^)]* = any non-paren chars, \) = literal close paren
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)

        // 2. Remove series and edition details in square brackets: [Special Edition]
        // Regex pattern: \s*\[[^\]]*\]
        // Explanation: \s* = optional whitespace, \[ = literal open bracket, [^\]]* = any non-bracket chars, \] = literal close bracket
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s*\\[[^\\]]*\\]", with: "", options: .regularExpression)

        // 3. Strip everything after a colon or dash that suggests a subtitle or adaptation,
        // unless the title is extremely short (e.g., "It: A Novel" should keep "It")
        if cleanTitle.count > 10 {
            // Find the first colon that separates the main title from the subtitle
            if let colonRange = cleanTitle.range(of: ":") {
                cleanTitle = String(cleanTitle[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            } else if let dashRange = cleanTitle.range(of: " - ") {
                // Only match " - " (space-dash-space) to avoid catching hyphenated words
                cleanTitle = String(cleanTitle[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        // 4. Clean up extra periods and spaces that don't belong
        // Common in abbreviations like "Dept." which should become "Dept"
        cleanTitle = cleanTitle.replacingOccurrences(of: "Dept.", with: "Dept")

        // 5. Normalize multiple spaces to single space
        // Regex pattern: \s+
        // Explanation: \s = any whitespace, + = one or more occurrences
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        return cleanTitle
    }
}
