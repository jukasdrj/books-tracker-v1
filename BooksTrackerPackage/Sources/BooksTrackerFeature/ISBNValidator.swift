import Foundation

public struct ISBNValidator {

    public struct ISBN: Equatable, Hashable, Sendable {
        public let normalizedValue: String
        public let displayValue: String
        public let type: ISBNType

        public enum ISBNType: String, Sendable {
            case isbn10 = "ISBN-10"
            case isbn13 = "ISBN-13"
        }
    }

    public enum ValidationResult: Equatable {
        case valid(ISBN)
        case invalid(String)
    }

    /// Cleans and validates an ISBN-10 or ISBN-13 string.
    public static func validate(_ rawValue: String) -> ValidationResult {
        // 1. Clean the input
        let cleanValue = rawValue.filter { $0.isNumber || $0.uppercased() == "X" }

        switch cleanValue.count {
        case 10:
            return validateISBN10(cleanValue)
        case 13:
            return validateISBN13(cleanValue)
        default:
            return .invalid("Invalid length: \(cleanValue.count)")
        }
    }

    private static func validateISBN10(_ isbn: String) -> ValidationResult {
        guard isbn.count == 10 else { return .invalid("Length not 10") }

        let chars = Array(isbn.uppercased())
        var sum = 0

        for i in 0..<9 {
            guard let digit = Int(String(chars[i])) else { return .invalid("Invalid character in ISBN-10") }
            sum += (i + 1) * digit
        }

        let lastChar = chars[9]
        let lastDigit: Int
        if lastChar == "X" {
            lastDigit = 10
        } else if let digit = Int(String(lastChar)) {
            lastDigit = digit
        } else {
            return .invalid("Invalid check digit in ISBN-10")
        }

        sum += 10 * lastDigit

        if sum % 11 == 0 {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN10(isbn),
                type: .isbn10
            ))
        } else {
            return .invalid("Checksum failed for ISBN-10")
        }
    }

    private static func validateISBN13(_ isbn: String) -> ValidationResult {
        guard isbn.count == 13 else { return .invalid("Length not 13") }
        guard isbn.prefix(3) == "978" || isbn.prefix(3) == "979" else { return .invalid("Not a recognized prefix") }

        let digits = isbn.compactMap { Int(String($0)) }
        guard digits.count == 13 else { return .invalid("Invalid character in ISBN-13") }

        var sum = 0
        for i in 0..<12 {
            sum += digits[i] * (i % 2 == 0 ? 1 : 3)
        }

        let checksum = (10 - (sum % 10)) % 10

        if checksum == digits[12] {
            return .valid(ISBN(
                normalizedValue: isbn,
                displayValue: formatISBN13(isbn),
                type: .isbn13
            ))
        } else {
            return .invalid("Checksum failed for ISBN-13")
        }
    }

    private static func formatISBN10(_ isbn: String) -> String {
        return "\(isbn.prefix(1))-\(isbn.prefix(5).suffix(4))-\(isbn.prefix(9).suffix(4))-\(isbn.suffix(1))"
    }

    private static func formatISBN13(_ isbn: String) -> String {
        return "\(isbn.prefix(3))-\(isbn.prefix(4).suffix(1))-\(isbn.prefix(9).suffix(5))-\(isbn.prefix(12).suffix(3))-\(isbn.suffix(1))"
    }
}