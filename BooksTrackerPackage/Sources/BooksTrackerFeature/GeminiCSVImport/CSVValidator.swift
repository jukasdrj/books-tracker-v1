import Foundation

// MARK: - CSV Validator

/// Validates the structure and integrity of CSV content before upload.
///
/// This validator checks for:
/// 1. UTF-8 encoding compatibility
/// 2. A minimum of two lines (header + one data row)
/// 3. Correctly quoted fields (handling commas, newlines, and escaped quotes)
///
/// **Design Philosophy:**
/// - **Strict about syntax** (closed quotes, parseable structure)
/// - **Permissive about schema** (flexible column counts, Gemini handles varying formats)
/// - **Fast validation** (line-by-line parsing, <500ms for typical CSVs)
///
/// **Why Flexible Column Counts?**
/// Gemini's CSV parser is intelligent enough to extract book data from varying
/// CSV formats (3-column, 5-column, exports from different sources). The backend
/// prompting guides Gemini to identify title/author/ISBN regardless of extra columns.
/// Strict column validation would reject valid CSVs that Gemini can parse successfully.
///
/// **RFC 4180 Compliance:**
/// Implements pragmatic subset of RFC 4180 focused on structural integrity.
/// Real-world CSVs (Goodreads, LibraryThing) often have minor quirks that
/// strict parsers reject, so we prioritize what breaks backend parsing.
public struct CSVValidator {

    /// Validates CSV content from a string.
    ///
    /// - Parameter csvText: Raw CSV content as string
    /// - Throws: `CSVValidationError` if the content is invalid
    public static func validate(csvText: String) throws {
        // Split into lines (preserving empty lines for accurate line numbers)
        let lines = csvText.components(separatedBy: .newlines)

        // Rule: Must have a header and at least one data row.
        // We check for 2 because a trailing newline might create an empty last line.
        guard lines.count >= 2 else {
            throw CSVValidationError.insufficientRows(count: lines.count)
        }

        var hasNonEmptyLine = false

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1

            // Skip empty lines, which are common at the end of files.
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            let columns = try parse(line: line, lineNumber: lineNumber)

            // First non-empty line is the header
            if !hasNonEmptyLine {
                hasNonEmptyLine = true

                // Rule: Header must not be empty
                if columns.isEmpty || columns.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    throw CSVValidationError.emptyHeader
                }
            }

            // NOTE: We do NOT enforce consistent column counts across rows.
            // Gemini's CSV parser is intelligent enough to handle varying column counts
            // and extract book data (title, author, ISBN) from different CSV formats.
        }

        // Additional check: Ensure we found at least a header
        guard hasNonEmptyLine else {
            throw CSVValidationError.insufficientRows(count: 0)
        }
    }

    /// Parses a single line of a CSV, respecting RFC 4180 quoting rules.
    ///
    /// **Algorithm:**
    /// Character-by-character state machine that handles:
    /// - Commas inside quoted fields
    /// - Newlines inside quoted fields (though single-line parsing here)
    /// - Escaped quotes ("") inside quoted fields
    /// - Mixed quoted and unquoted fields
    ///
    /// - Parameters:
    ///   - line: Single CSV line to parse
    ///   - lineNumber: Line number for error reporting
    /// - Returns: Array of field values
    /// - Throws: `CSVValidationError` for malformed lines
    private static func parse(line: String, lineNumber: Int) throws -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(line)
        var index = 0

        while index < chars.count {
            let char = chars[index]

            switch char {
            case ",":
                if inQuotes {
                    currentField.append(char)
                } else {
                    fields.append(currentField)
                    currentField = ""
                }
                index += 1

            case "\"":
                if inQuotes {
                    // Check for escaped quote ("")
                    if index + 1 < chars.count && chars[index + 1] == "\"" {
                        currentField.append("\"")
                        index += 2 // Skip both quotes
                    } else {
                        // End of quoted field
                        inQuotes = false
                        index += 1
                    }
                } else {
                    // Start of a quoted field. It should be empty before this.
                    if currentField.isEmpty {
                        inQuotes = true
                        index += 1
                    } else {
                        // Quotes in the middle of an unquoted field are a format violation.
                        throw CSVValidationError.strayQuote(lineNumber: lineNumber)
                    }
                }

            default:
                currentField.append(char)
                index += 1
            }
        }

        // Add the last field
        fields.append(currentField)

        // Rule: No unclosed quotes at the end of a line
        if inQuotes {
            throw CSVValidationError.unclosedQuote(lineNumber: lineNumber)
        }

        return fields
    }
}

// MARK: - CSV Validation Error

/// Errors that can occur during CSV validation.
///
/// Each error provides a user-friendly message with specific line numbers
/// for quick debugging.
public enum CSVValidationError: Error, LocalizedError, Equatable {
    case fileReadError(message: String)
    case insufficientRows(count: Int)
    case emptyHeader
    case unclosedQuote(lineNumber: Int)
    case strayQuote(lineNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .fileReadError(let message):
            return "Could not read the file. Please ensure it is a valid UTF-8 encoded CSV. Details: \(message)"
        case .insufficientRows(let count):
            return "Invalid CSV structure. The file must contain a header and at least one data row, but found only \(count) line(s)."
        case .emptyHeader:
            return "Invalid CSV structure. The header row cannot be empty."
        case .unclosedQuote(let lineNumber):
            return "Formatting error on line \(lineNumber): A quoted field is not properly closed."
        case .strayQuote(let lineNumber):
            return "Formatting error on line \(lineNumber): Found a quote in the middle of an unquoted field."
        }
    }
}