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

    @Test("Initial state returns empty results")
    @MainActor
    func testInitialStateResults() {
        let state = SearchViewState.initial(trending: [], recentSearches: [])
        #expect(state.currentResults.isEmpty)
        #expect(state.currentQuery == nil)
        #expect(state.currentScope == nil)
        #expect(!state.isSearching)
    }

    @Test("No results state preserves query context")
    @MainActor
    func testNoResultsState() {
        let state = SearchViewState.noResults(query: "unicorn book", scope: .title)
        #expect(state.currentQuery == "unicorn book")
        #expect(state.currentScope == .title)
        #expect(state.currentResults.isEmpty)
        #expect(!state.isSearching)
    }

    @Test("Error state preserves recovery context")
    @MainActor
    func testErrorState() {
        let state = SearchViewState.error(
            message: "Network timeout",
            query: "Swift programming",
            scope: .author,
            previousResults: []
        )
        #expect(state.currentQuery == "Swift programming")
        #expect(state.currentScope == .author)
        #expect(state.currentResults.isEmpty)
        #expect(!state.isSearching)
    }

    @Test("isSearching flag works correctly")
    @MainActor
    func testIsSearchingFlag() {
        let searchingState = SearchViewState.searching(
            query: "test",
            scope: .all,
            previousResults: []
        )
        #expect(searchingState.isSearching)

        let resultsState = SearchViewState.results(
            query: "test",
            scope: .all,
            items: [],
            hasMorePages: false,
            cacheHitRate: 0.0
        )
        #expect(!resultsState.isSearching)

        let initialState = SearchViewState.initial(trending: [], recentSearches: [])
        #expect(!initialState.isSearching)

        let noResultsState = SearchViewState.noResults(query: "test", scope: .all)
        #expect(!noResultsState.isSearching)

        let errorState = SearchViewState.error(
            message: "Error",
            query: "test",
            scope: .all,
            previousResults: []
        )
        #expect(!errorState.isSearching)
    }

    @Test("Current query extraction works for all cases")
    @MainActor
    func testCurrentQueryExtraction() {
        let initial = SearchViewState.initial(trending: [], recentSearches: [])
        #expect(initial.currentQuery == nil)

        let searching = SearchViewState.searching(query: "query1", scope: .all, previousResults: [])
        #expect(searching.currentQuery == "query1")

        let results = SearchViewState.results(
            query: "query2",
            scope: .all,
            items: [],
            hasMorePages: false,
            cacheHitRate: 0.0
        )
        #expect(results.currentQuery == "query2")

        let noResults = SearchViewState.noResults(query: "query3", scope: .all)
        #expect(noResults.currentQuery == "query3")

        let error = SearchViewState.error(
            message: "Error",
            query: "query4",
            scope: .all,
            previousResults: []
        )
        #expect(error.currentQuery == "query4")
    }

    @Test("Current scope extraction works for all cases")
    @MainActor
    func testCurrentScopeExtraction() {
        let initial = SearchViewState.initial(trending: [], recentSearches: [])
        #expect(initial.currentScope == nil)

        let searching = SearchViewState.searching(query: "test", scope: .title, previousResults: [])
        #expect(searching.currentScope == .title)

        let results = SearchViewState.results(
            query: "test",
            scope: .author,
            items: [],
            hasMorePages: false,
            cacheHitRate: 0.0
        )
        #expect(results.currentScope == .author)

        let noResults = SearchViewState.noResults(query: "test", scope: .isbn)
        #expect(noResults.currentScope == .isbn)

        let error = SearchViewState.error(
            message: "Error",
            query: "test",
            scope: .all,
            previousResults: []
        )
        #expect(error.currentScope == .all)
    }

    @Test("Searching state preserves previous results")
    @MainActor
    func testPreviousResultsPreservation() {
        let mockResults = [
            SearchResult(
                work: Work(title: "Previous Book"),
                editions: [],
                authors: [],
                relevanceScore: 1.0,
                provider: "test"
            )
        ]

        let searchingState = SearchViewState.searching(
            query: "new query",
            scope: .all,
            previousResults: mockResults
        )

        #expect(searchingState.currentResults.count == 1)
        #expect(searchingState.currentResults.first?.work.title == "Previous Book")
        #expect(searchingState.isSearching)
    }

    @Test("State equality works with different data")
    @MainActor
    func testStateEquality() {
        let state1 = SearchViewState.initial(trending: [], recentSearches: [])
        let state2 = SearchViewState.initial(trending: [], recentSearches: [])
        #expect(state1 == state2)

        let mockResult = SearchResult(
            work: Work(title: "Test"),
            editions: [],
            authors: [],
            relevanceScore: 1.0,
            provider: "test"
        )

        let results1 = SearchViewState.results(
            query: "test",
            scope: .all,
            items: [mockResult],
            hasMorePages: false,
            cacheHitRate: 0.5
        )
        let results2 = SearchViewState.results(
            query: "test",
            scope: .all,
            items: [mockResult],
            hasMorePages: false,
            cacheHitRate: 0.5
        )
        #expect(results1 == results2)

        let results3 = SearchViewState.results(
            query: "different",
            scope: .all,
            items: [mockResult],
            hasMorePages: false,
            cacheHitRate: 0.5
        )
        #expect(results1 != results3)
    }
}
