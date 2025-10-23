//
//  WorkTests.swift
//  BooksTrackerFeatureTests
//
//  Tests for Work model including ReviewStatus functionality
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Work Model Tests")
@MainActor
struct WorkTests {

    @Test func workCanHaveReviewStatus() {
        let work = Work(title: "Test Book")
        #expect(work.reviewStatus == .verified)  // Default status

        work.reviewStatus = .needsReview
        #expect(work.reviewStatus == .needsReview)

        work.reviewStatus = .userEdited
        #expect(work.reviewStatus == .userEdited)
    }

    @Test func reviewStatusFilteringWorks() throws {
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let work1 = Work(title: "Verified Book")
        work1.reviewStatus = .verified

        let work2 = Work(title: "Needs Review Book")
        work2.reviewStatus = .needsReview

        context.insert(work1)
        context.insert(work2)
        try context.save()

        let descriptor = FetchDescriptor<Work>()
        let allWorks = try context.fetch(descriptor)
        let needsReview = allWorks.filter { $0.reviewStatus == .needsReview }

        #expect(needsReview.count == 1)
        #expect(needsReview.first?.title == "Needs Review Book")
    }

    @Test func workCanStoreOriginalImagePath() {
        let work = Work(title: "Test Book")
        work.originalImagePath = "/tmp/bookshelf_scan_123.jpg"

        #expect(work.originalImagePath == "/tmp/bookshelf_scan_123.jpg")
    }

    @Test func workCanStoreBoundingBox() {
        let work = Work(title: "Test Book")
        work.boundingBox = CGRect(x: 10, y: 20, width: 100, height: 200)

        #expect(work.boundingBox?.minX == 10)
        #expect(work.boundingBox?.minY == 20)
        #expect(work.boundingBox?.width == 100)
        #expect(work.boundingBox?.height == 200)
    }
}
