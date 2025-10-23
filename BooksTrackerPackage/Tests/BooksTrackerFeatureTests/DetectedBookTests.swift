import Testing
import Foundation
import CoreGraphics
@testable import BooksTrackerFeature

@Test func detectedBookCalculatesNeedsReview() {
    let highConfidence = DetectedBook(
        title: "High Confidence Book",
        author: "Author",
        confidence: 0.95,
        boundingBox: CGRect.zero,
        rawText: "High Confidence Book by Author"
    )
    #expect(highConfidence.needsReview == false)

    let lowConfidence = DetectedBook(
        title: "Low Confidence Book",
        author: "Author",
        confidence: 0.40,
        boundingBox: CGRect.zero,
        rawText: "Low Confidence Book by Author"
    )
    #expect(lowConfidence.needsReview == true)

    let thresholdConfidence = DetectedBook(
        title: "Threshold Book",
        author: "Author",
        confidence: 0.60,  // Exactly at threshold
        boundingBox: CGRect.zero,
        rawText: "Threshold Book by Author"
    )
    #expect(thresholdConfidence.needsReview == false)
}
