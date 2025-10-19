// BooksTrackerPackage/Tests/BooksTrackerFeatureTests/SearchViewStateTests.swift
import Testing
@testable import BooksTrackerFeature

@Suite("SearchViewState Tests")
struct SearchViewStateTests {

    @Test("State is Equatable")
    @MainActor
    func testEquatable() {
        let state1 = SearchViewState.initial(trending: [], recentSearches: [])
        let state2 = SearchViewState.initial(trending: [], recentSearches: [])

        #expect(state1 == state2)
    }

    @Test("Can extract current results from different states")
    @MainActor
    func testCurrentResults() {
        let mockResults = [
            SearchResult(
                work: Work(title: "Test Book"),
                editions: [],
                authors: [],
                relevanceScore: 1.0,
                provider: "test"
            )
        ]

        let resultsState = SearchViewState.results(
            query: "test",
            scope: .all,
            items: mockResults,
            hasMorePages: false,
            cacheHitRate: 0.0
        )

        #expect(resultsState.currentResults.count == 1)

        let searchingState = SearchViewState.searching(
            query: "test",
            scope: .all,
            previousResults: mockResults
        )

        #expect(searchingState.currentResults.count == 1)
    }
}
