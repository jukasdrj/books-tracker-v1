import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("String Title Normalization Tests")
struct StringTitleNormalizationTests {

    @Test("Remove subtitle after colon")
    func testRemoveSubtitle() async throws {
        let input = "The da Vinci Code: The Young Adult Adaptation"
        let expected = "The da Vinci Code"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Remove series marker in parentheses")
    func testRemoveSeriesMarker() async throws {
        let input = "Devil's Knot: The True Story of the West Memphis Three (Justice Knot, #1)"
        let expected = "Devil's Knot"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Remove edition marker in square brackets")
    func testRemoveEditionMarker() async throws {
        let input = "1984 [Special Edition]"
        let expected = "1984"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Clean up period in abbreviation")
    func testCleanPeriodAbbreviation() async throws {
        let input = "Dept. of Speculation"
        let expected = "Dept of Speculation"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Keep short title with colon intact")
    func testKeepShortTitleWithColon() async throws {
        let input = "It: A Novel"
        let expected = "It: A Novel" // Title too short (< 10 chars), keep colon
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Remove subtitle after dash")
    func testRemoveSubtitleDash() async throws {
        let input = "The Girl with the Dragon Tattoo - A Thriller"
        let expected = "The Girl with the Dragon Tattoo"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Handle multiple parentheses")
    func testMultipleParentheses() async throws {
        let input = "The Hobbit (The Lord of the Rings #0) (Collector's Edition)"
        let expected = "The Hobbit"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Trim whitespace")
    func testTrimWhitespace() async throws {
        let input = "  The Great Gatsby  "
        let expected = "The Great Gatsby"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Normalize multiple spaces")
    func testMultipleSpaces() async throws {
        let input = "The    Great    Gatsby"
        let expected = "The Great Gatsby"
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Handle empty string")
    func testEmptyString() async throws {
        let input = ""
        let expected = ""
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Handle title with only parentheses")
    func testOnlyParentheses() async throws {
        let input = "(Book One)"
        let expected = ""
        #expect(input.normalizedTitleForSearch == expected)
    }

    @Test("Real-world Goodreads export examples")
    func testRealWorldExamples() async throws {
        // Test actual problematic titles from CSV imports
        let examples: [(input: String, expected: String)] = [
            ("Harry Potter and the Sorcerer's Stone (Harry Potter, #1)", "Harry Potter and the Sorcerer's Stone"),
            ("The Fellowship of the Ring (The Lord of the Rings, #1)", "The Fellowship of the Ring"),
            ("A Game of Thrones (A Song of Ice and Fire, #1)", "A Game of Thrones"),
            ("The Handmaid's Tale: Special Illustrated Edition", "The Handmaid's Tale"),
            ("Educated: A Memoir", "Educated")
        ]

        for (input, expected) in examples {
            #expect(input.normalizedTitleForSearch == expected, "Failed for: \(input)")
        }
    }
}
