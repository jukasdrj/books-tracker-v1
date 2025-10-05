import Foundation
import SwiftData

// MARK: - CSV Parsing Actor
/// Background actor for efficient CSV parsing and import
/// Handles large files (1500+ books) with batching and memory management
@globalActor
public actor CSVParsingActor: GlobalActor {
    public static let shared = CSVParsingActor()

    // Batch size optimized for SwiftData performance
    private let batchSize = 50

    // MARK: - CSV Column Detection

    public struct ColumnMapping: Sendable {
        let csvColumn: String
        var mappedField: BookField?
        let sampleValues: [String]
        let confidence: Double

        public enum BookField: String, CaseIterable, Sendable {
            case isbn = "ISBN"
            case isbn10 = "ISBN-10"
            case isbn13 = "ISBN-13"
            case title = "Title"
            case author = "Author(s)"
            case publicationYear = "Year"
            case publisher = "Publisher"
            case rating = "Rating"
            case myRating = "My Rating"
            case readStatus = "Status"
            case dateRead = "Date Read"
            case dateStarted = "Date Started"
            case dateFinished = "Date Finished"
            case notes = "Notes"
            case tags = "Tags"
            case bookshelves = "Bookshelves"

            var isRequired: Bool {
                switch self {
                case .title, .author: return true
                default: return false
                }
            }
        }
    }

    public struct ParsedRow: Sendable {
        let title: String
        let author: String
        let isbn: String?
        let isbn10: String?
        let isbn13: String?
        let publicationYear: Int?
        let publisher: String?
        let rating: Double?
        let readStatus: String?
        let dateRead: Date?
        let dateStarted: Date?
        let dateFinished: Date?
        let notes: String?
        let tags: [String]?
    }

    // MARK: - Smart Column Detection

    public func detectColumns(
        headers: [String],
        sampleRows: [[String]]
    ) async -> [ColumnMapping] {

        return headers.enumerated().map { index, header in
            let samples = Array(sampleRows.compactMap { row in
                index < row.count ? row[index] : nil
            }.prefix(10))

            let (field, confidence) = detectFieldType(
                columnName: header,
                sampleValues: Array(samples)
            )

            return ColumnMapping(
                csvColumn: header,
                mappedField: field,
                sampleValues: Array(samples),
                confidence: confidence
            )
        }
    }

    private func detectFieldType(
        columnName: String,
        sampleValues: [String]
    ) -> (field: ColumnMapping.BookField?, confidence: Double) {

        let normalized = columnName
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        // High confidence matches (exact or very close)
        let exactMatches: [(pattern: String, field: ColumnMapping.BookField, confidence: Double)] = [
            ("isbn13", .isbn13, 0.95),
            ("isbn10", .isbn10, 0.95),
            ("isbn", .isbn, 0.9),
            ("title", .title, 0.95),
            ("booktitle", .title, 0.9),
            ("author", .author, 0.95),
            ("authors", .author, 0.95),
            ("primaryauthor", .author, 0.9),
            ("authorname", .author, 0.9),
            ("year", .publicationYear, 0.85),
            ("publicationyear", .publicationYear, 0.95),
            ("yearpublished", .publicationYear, 0.9),
            ("publisher", .publisher, 0.9),
            ("myrating", .myRating, 0.95),
            ("rating", .rating, 0.85),
            ("starrating", .rating, 0.9),
            ("stars", .rating, 0.85),
            ("status", .readStatus, 0.85),
            ("readstatus", .readStatus, 0.95),
            ("shelf", .bookshelves, 0.85),
            ("bookshelves", .bookshelves, 0.95),
            ("exclusiveshelf", .readStatus, 0.8),
            ("dateread", .dateRead, 0.95),
            ("datefinished", .dateFinished, 0.95),
            ("datestarted", .dateStarted, 0.95),
            ("readdate", .dateRead, 0.9),
            ("finisheddate", .dateFinished, 0.9),
            ("starteddate", .dateStarted, 0.9),
            ("notes", .notes, 0.9),
            ("mynotes", .notes, 0.95),
            ("review", .notes, 0.85),
            ("myreview", .notes, 0.9),
            ("tags", .tags, 0.95),
            ("shelves", .bookshelves, 0.9)
        ]

        // Check exact matches first
        for (pattern, field, confidence) in exactMatches {
            if normalized == pattern {
                return (field, confidence)
            }
        }

        // Check partial matches
        for (pattern, field, confidence) in exactMatches {
            if normalized.contains(pattern) {
                return (field, confidence * 0.8) // Lower confidence for partial matches
            }
        }

        // Sample-based detection
        if !sampleValues.isEmpty {
            // Check if all samples are valid ISBNs
            let isbnPattern = #"^(?:\d{9}[\dXx]|\d{13})$"#
            if sampleValues.allSatisfy({ $0.range(of: isbnPattern, options: .regularExpression) != nil }) {
                if sampleValues.first?.count == 13 {
                    return (.isbn13, 0.8)
                } else if sampleValues.first?.count == 10 {
                    return (.isbn10, 0.8)
                } else {
                    return (.isbn, 0.7)
                }
            }

            // Check for year patterns (4-digit years)
            let yearPattern = #"^(19|20)\d{2}$"#
            if sampleValues.allSatisfy({ $0.range(of: yearPattern, options: .regularExpression) != nil }) {
                return (.publicationYear, 0.75)
            }

            // Check for rating patterns (1-5 numbers)
            let ratingPattern = #"^[1-5](?:\.\d)?$"#
            if sampleValues.allSatisfy({ $0.range(of: ratingPattern, options: .regularExpression) != nil }) {
                return (.rating, 0.7)
            }

            // Check for date patterns
            let datePatterns = [
                #"^\d{4}-\d{2}-\d{2}"#,
                #"^\d{1,2}/\d{1,2}/\d{2,4}"#,
                #"^\d{1,2}-\d{1,2}-\d{2,4}"#
            ]
            if sampleValues.allSatisfy({ value in
                datePatterns.contains { pattern in
                    value.range(of: pattern, options: .regularExpression) != nil
                }
            }) {
                if normalized.contains("start") {
                    return (.dateStarted, 0.7)
                } else if normalized.contains("finish") || normalized.contains("end") {
                    return (.dateFinished, 0.7)
                } else {
                    return (.dateRead, 0.6)
                }
            }
        }

        return (nil, 0.0)
    }

    // MARK: - CSV Parsing

    public func parseCSV(_ content: String) async throws -> (headers: [String], rows: [[String]]) {
        let parser = RobustCSVParser()
        return try parser.parse(content)
    }

    // MARK: - Row Processing

    public func processRow(
        values: [String],
        mappings: [ColumnMapping]
    ) async -> ParsedRow? {

        // Extract values based on mappings
        var title: String?
        var author: String?
        var isbn: String?
        var isbn10: String?
        var isbn13: String?
        var publicationYear: Int?
        var publisher: String?
        var rating: Double?
        var readStatus: String?
        var dateRead: Date?
        var dateStarted: Date?
        var dateFinished: Date?
        var notes: String?
        var tags: [String]?

        let dateFormatter = ISO8601DateFormatter()
        let alternativeDateFormatter = DateFormatter()
        alternativeDateFormatter.dateFormat = "MM/dd/yyyy"

        for (index, mapping) in mappings.enumerated() {
            guard index < values.count,
                  let field = mapping.mappedField else { continue }

            let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            switch field {
            case .title:
                title = value
            case .author:
                author = value
            case .isbn:
                isbn = normalizeISBN(value)
            case .isbn10:
                isbn10 = normalizeISBN(value)
            case .isbn13:
                isbn13 = normalizeISBN(value)
            case .publicationYear:
                publicationYear = Int(value)
            case .publisher:
                publisher = value
            case .rating, .myRating:
                rating = Double(value)
            case .readStatus, .bookshelves:
                readStatus = value
            case .dateRead:
                dateRead = parseDate(value, dateFormatter, alternativeDateFormatter)
            case .dateStarted:
                dateStarted = parseDate(value, dateFormatter, alternativeDateFormatter)
            case .dateFinished:
                dateFinished = parseDate(value, dateFormatter, alternativeDateFormatter)
            case .notes:
                notes = value
            case .tags:
                tags = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        // Required fields check
        guard let title = title, !title.isEmpty,
              let author = author, !author.isEmpty else {
            return nil
        }

        // Consolidate ISBN fields
        let finalISBN = isbn13 ?? isbn ?? isbn10

        return ParsedRow(
            title: title,
            author: author,
            isbn: finalISBN,
            isbn10: isbn10,
            isbn13: isbn13,
            publicationYear: publicationYear,
            publisher: publisher,
            rating: rating,
            readStatus: readStatus,
            dateRead: dateRead ?? dateFinished,
            dateStarted: dateStarted,
            dateFinished: dateFinished,
            notes: notes,
            tags: tags
        )
    }

    private func normalizeISBN(_ isbn: String) -> String? {
        let cleaned = isbn.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        // Validate ISBN format
        if cleaned.count == 10 || cleaned.count == 13 {
            return cleaned
        }

        return nil
    }

    private func parseDate(
        _ value: String,
        _ isoFormatter: ISO8601DateFormatter,
        _ alternativeFormatter: DateFormatter
    ) -> Date? {
        // Try ISO format first
        if let date = isoFormatter.date(from: value) {
            return date
        }

        // Try alternative format
        if let date = alternativeFormatter.date(from: value) {
            return date
        }

        // Try other common formats
        let formats = [
            "yyyy-MM-dd",
            "MM-dd-yyyy",
            "dd/MM/yyyy",
            "yyyy/MM/dd",
            "MMM dd, yyyy",
            "dd MMM yyyy"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Robust CSV Parser

private struct RobustCSVParser {
    func parse(_ content: String) throws -> (headers: [String], rows: [[String]]) {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw CSVParseError.emptyFile
        }

        let headers = parseRow(lines[0])
        guard !headers.isEmpty else {
            throw CSVParseError.invalidHeaders
        }

        let rows = lines.dropFirst().compactMap { line in
            let row = parseRow(line)
            return row.isEmpty ? nil : row
        }

        return (headers, rows)
    }

    private func parseRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var previousChar: Character?

        for char in line {
            switch char {
            case "\"":
                if inQuotes && previousChar == "\"" {
                    // Escaped quote
                    current.append(char)
                    previousChar = nil // Reset to handle successive quotes
                } else if !inQuotes {
                    inQuotes = true
                } else {
                    inQuotes = false
                }

            case ",":
                if inQuotes {
                    current.append(char)
                } else {
                    result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                }

            default:
                current.append(char)
            }

            previousChar = char
        }

        // Add the last field
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))

        return result
    }
}

// MARK: - Errors

enum CSVParseError: LocalizedError {
    case emptyFile
    case invalidHeaders
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file is empty"
        case .invalidHeaders:
            return "Invalid CSV headers"
        case .invalidFormat:
            return "Invalid CSV format"
        }
    }
}