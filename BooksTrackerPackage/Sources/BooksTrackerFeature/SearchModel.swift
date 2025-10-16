import Foundation
import SwiftUI
import SwiftData

// MARK: - Search Scope Enum

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case title = "Title"
    case author = "Author"
    case isbn = "ISBN"

    public var id: String { rawValue }

    /// HIG: Provide clear, concise scope labels
    public var displayName: String { rawValue }

    /// HIG: Accessibility - descriptive labels for VoiceOver
    public var accessibilityLabel: String {
        switch self {
        case .all: return "Search all fields"
        case .title: return "Search by book title"
        case .author: return "Search by author name"
        case .isbn: return "Search by ISBN number"
        }
    }
}

// MARK: - Search State Management

@Observable
@MainActor
public final class SearchModel {
    // Search state
    var searchText: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var searchState: SearchState = .initial
    var errorMessage: String?

    // Trending/featured books for initial state
    var trendingBooks: [SearchResult] = []
    var searchSuggestions: [String] = []
    var recentSearches: [String] = []
    private var popularSearches: [String] = [
        "Andy Weir", "Stephen King", "Agatha Christie", "J.K. Rowling",
        "The Martian", "Dune", "1984", "Pride and Prejudice",
        "science fiction", "mystery", "romance", "fantasy"
    ]

    // Performance tracking
    var lastSearchTime: TimeInterval = 0
    var cacheHitRate: Double = 0.0

    // Dependencies
    private let apiService: BookSearchAPIService
    private var searchTask: Task<Void, Never>?

    public init(apiService: BookSearchAPIService = BookSearchAPIService()) {
        self.apiService = apiService

        // Load recent searches from UserDefaults
        if let savedSearches = UserDefaults.standard.array(forKey: "RecentBookSearches") as? [String] {
            self.recentSearches = savedSearches
        }

        Task {
            await loadTrendingBooks()
            generateSearchSuggestions(for: "")
        }
    }

    // MARK: - Search State Enum

    enum SearchState {
        case initial        // Show trending books grid
        case searching      // Loading state with glass spinner
        case results        // Show search results list
        case noResults      // ContentUnavailableView with search icon
        case error(String)  // Error state with retry option
    }

    // MARK: - Pagination Support

    var hasMoreResults: Bool = false
    private var currentPage: Int = 1
    private var currentQuery: String = ""
    private var currentScope: SearchScope?

    // MARK: - Public Methods

    // MARK: - Advanced Search

    func advancedSearch(criteria: AdvancedSearchCriteria) {
        // Cancel previous search
        searchTask?.cancel()

        searchTask = Task {
            await performAdvancedSearch(criteria: criteria)
        }
    }

    private func performAdvancedSearch(criteria: AdvancedSearchCriteria) async {
        searchState = .searching
        isSearching = true

        let startTime = Date()

        do {
            let response = try await apiService.advancedSearch(
                author: criteria.authorName.isEmpty ? nil : criteria.authorName,
                title: criteria.bookTitle.isEmpty ? nil : criteria.bookTitle,
                isbn: criteria.isbn.isEmpty ? nil : criteria.isbn
            )

            // Backend returns filtered SearchResults directly
            searchResults = response.results
            searchState = response.results.isEmpty ? .noResults : .results
            lastSearchTime = Date().timeIntervalSince(startTime) * 1000 // milliseconds

            // Update search text for display (combined query)
            if let query = criteria.buildSearchQuery() {
                searchText = query
            }

        } catch {
            searchState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    func search(query: String, scope: SearchScope = .all) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            resetToInitialState()
            return
        }

        // Cancel previous search
        searchTask?.cancel()

        // DO NOT update searchText here. The view's @State is the source of truth.
        // This was causing a feedback loop that broke the spacebar.
        currentScope = scope

        // Determine debounce delay based on query length and type
        let debounceDelay = calculateDebounceDelay(for: trimmedQuery)

        // Update suggestions immediately
        generateSearchSuggestions(for: trimmedQuery)

        // Start search with intelligent debouncing
        searchTask = Task {
            // Intelligent debounce delay
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            await performSearch(query: trimmedQuery, scope: scope)
        }
    }

    /// Load more results for pagination
    func loadMoreResults() async {
        guard hasMoreResults, !isSearching else { return }

        currentPage += 1
        await performSearch(
            query: currentQuery,
            scope: currentScope ?? .all,
            page: currentPage,
            appendResults: true
        )
    }

    // MARK: - Smart Debouncing Logic

    private func calculateDebounceDelay(for query: String) -> Double {
        // ISBN patterns get immediate search (no debounce)
        if isISBNPattern(query) {
            return 0.1
        }

        // Short queries (1-3 chars) get longer debounce to reduce API calls
        if query.count <= 3 {
            return 0.8
        }

        // Medium queries (4-6 chars) get standard debounce
        if query.count <= 6 {
            return 0.5
        }

        // Longer queries get shorter debounce (user is more specific)
        return 0.3
    }

    private func isISBNPattern(_ query: String) -> Bool {
        let cleanQuery = query.replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
        return cleanQuery.count == 10 || cleanQuery.count == 13
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        errorMessage = nil
        resetToInitialState()
    }

    func retryLastSearch() {
        guard !searchText.isEmpty else { return }
        search(query: searchText)
    }

    /// Search for a specific ISBN from barcode scanning
    func searchByISBN(_ isbn: String) {
        // Set search text and immediately perform search without debouncing
        searchText = isbn
        
        // Cancel any previous search
        searchTask?.cancel()
        
        // Start immediate search for ISBN
        searchTask = Task {
            await performSearch(query: isbn)
        }
    }

    // MARK: - Search Suggestions & History

    func generateSearchSuggestions(for query: String) {
        let lowercaseQuery = query.lowercased()

        if query.isEmpty {
            // Show recent searches and popular searches when empty
            searchSuggestions = Array(recentSearches.prefix(3)) + Array(popularSearches.prefix(5))
            return
        }

        var suggestions: [String] = []

        // Add matching recent searches
        let matchingRecent = recentSearches.filter {
            $0.lowercased().contains(lowercaseQuery)
        }.prefix(2)
        suggestions.append(contentsOf: matchingRecent)

        // Add matching popular searches
        let matchingPopular = popularSearches.filter {
            $0.lowercased().contains(lowercaseQuery) && !suggestions.contains($0)
        }.prefix(3)
        suggestions.append(contentsOf: matchingPopular)

        // Add query completion suggestions
        let completions = generateQueryCompletions(for: query)
        suggestions.append(contentsOf: completions.filter { !suggestions.contains($0) })

        searchSuggestions = Array(suggestions.prefix(6)) // Limit to 6 suggestions
    }

    func addToRecentSearches(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        // Remove if already exists
        recentSearches.removeAll { $0.lowercased() == trimmedQuery.lowercased() }

        // Add to beginning
        recentSearches.insert(trimmedQuery, at: 0)

        // Keep only last 10 searches
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }

        // Persist to UserDefaults (simple persistence)
        UserDefaults.standard.set(recentSearches, forKey: "RecentBookSearches")
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: "RecentBookSearches")
    }

    private func generateQueryCompletions(for query: String) -> [String] {
        let lowercaseQuery = query.lowercased()

        // Smart completions based on query patterns
        var completions: [String] = []

        // Author name patterns
        if lowercaseQuery.contains("king") {
            completions.append("Stephen King")
        }
        if lowercaseQuery.contains("weir") {
            completions.append("Andy Weir")
        }
        if lowercaseQuery.contains("christie") {
            completions.append("Agatha Christie")
        }

        // Book title patterns
        if lowercaseQuery.contains("martian") {
            completions.append("The Martian")
        }
        if lowercaseQuery.contains("dune") {
            completions.append("Dune")
        }

        // Genre patterns
        if lowercaseQuery.contains("sci") {
            completions.append("science fiction")
        }
        if lowercaseQuery.contains("fant") {
            completions.append("fantasy")
        }
        if lowercaseQuery.contains("myst") {
            completions.append("mystery")
        }

        return completions
    }

    // MARK: - Private Methods

    private func performSearch(
        query: String,
        scope: SearchScope = .all,
        page: Int = 1,
        appendResults: Bool = false,
        retryCount: Int = 0
    ) async {
        isSearching = true
        searchState = .searching
        errorMessage = nil

        // Store query for pagination
        if !appendResults {
            currentQuery = query
            currentPage = 1
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Pass scope directly to API service (no need for prefix approach)
            let response = try await apiService.search(query: query, maxResults: 20, scope: scope)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Update performance metrics
            lastSearchTime = CFAbsoluteTimeGetCurrent() - startTime
            cacheHitRate = response.cacheHitRate

            // Process results with scope filtering
            let filteredResults = filterResultsByScope(response.results, scope: scope, query: query)

            // Append or replace results based on pagination
            if appendResults {
                searchResults.append(contentsOf: filteredResults)
            } else {
                searchResults = filteredResults
            }

            // Update pagination state
            hasMoreResults = filteredResults.count >= 20

            // Update UI state based on results
            if searchResults.isEmpty {
                searchState = .noResults
                hasMoreResults = false
            } else {
                searchState = .results
                // Add successful search to recent searches
                if !appendResults {
                    addToRecentSearches(query)
                }
            }

        } catch {
            guard !Task.isCancelled else { return }

            // Implement intelligent retry logic
            if shouldRetry(error: error, attempt: retryCount) {
                let retryDelay = calculateRetryDelay(attempt: retryCount)
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

                guard !Task.isCancelled else { return }

                await performSearch(query: query, scope: scope, page: page, appendResults: appendResults, retryCount: retryCount + 1)
                return
            }

            // Handle final error state
            errorMessage = formatUserFriendlyError(error)
            searchState = .error(formatUserFriendlyError(error))
            hasMoreResults = false
        }

        isSearching = false
    }

    /// Filter results by scope (additional client-side filtering for quality)
    private func filterResultsByScope(_ results: [SearchResult], scope: SearchScope, query: String) -> [SearchResult] {
        switch scope {
        case .all:
            return results

        case .title:
            return results.filter { result in
                result.displayTitle.localizedCaseInsensitiveContains(query)
            }

        case .author:
            return results.filter { result in
                result.displayAuthors.localizedCaseInsensitiveContains(query)
            }

        case .isbn:
            // ISBN scope - no additional filtering needed (API handles this)
            return results
        }
    }

    // MARK: - Retry Logic

    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < 2 else { return false } // Max 2 retries

        // Retry on network errors but not on client errors
        if let searchError = error as? SearchError {
            switch searchError {
            case .httpError(let code):
                return code >= 500 // Retry on server errors
            case .networkError, .invalidResponse:
                return true
            case .invalidQuery, .invalidURL, .decodingError:
                return false // Don't retry client errors
            }
        }

        return false // Don't retry unknown errors
    }

    private func calculateRetryDelay(attempt: Int) -> Double {
        // Exponential backoff: 1s, 2s, 4s
        return pow(2.0, Double(attempt))
    }

    private func formatUserFriendlyError(_ error: Error) -> String {
        if let searchError = error as? SearchError {
            switch searchError {
            case .httpError(let code) where code >= 500:
                return "Server temporarily unavailable. Please try again."
            case .networkError, .invalidResponse:
                return "Network connection issue. Check your internet connection."
            case .invalidQuery:
                return "Please enter a valid search term."
            default:
                return searchError.localizedDescription
            }
        }

        return "Search failed. Please try again."
    }

    private func resetToInitialState() {
        searchState = .initial
        searchResults = []
        errorMessage = nil
        isSearching = false
        hasMoreResults = false
        currentPage = 1
        currentQuery = ""
        currentScope = nil
    }

    private func loadTrendingBooks() async {
        // Load trending books for initial state
        do {
            let response = try await apiService.getTrendingBooks()
            self.trendingBooks = response.results
        } catch {
            // Silently fail for trending books - not critical
            print("Failed to load trending books: \(error)")
        }
    }
}

// MARK: - Search Result Model

public struct SearchResult: Identifiable, Hashable, @unchecked Sendable {
    public let id = UUID()
    public let work: Work
    public let editions: [Edition]
    public let authors: [Author]
    public let relevanceScore: Double
    public let provider: String // "isbndb", "cache", etc.

    // Computed properties for display
    public var primaryEdition: Edition? {
        editions.first
    }

    public var displayTitle: String {
        work.title
    }

    public var displayAuthors: String {
        // Use the authors array from SearchResult instead of work.authorNames
        // because SwiftData relationships don't work for non-persisted objects
        let names = authors.map { $0.name }
        switch names.count {
        case 0: return "Unknown Author"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }

    public var coverImageURL: URL? {
        // Try to get cover from primary edition
        primaryEdition?.coverURL
    }

    public var isInLibrary: Bool {
        work.isInLibrary
    }

    public var culturalRegion: CulturalRegion? {
        work.culturalRegion
    }
}

// MARK: - API Service

public actor BookSearchAPIService {
    private let baseURL = "https://books-api-proxy.jukasdrj.workers.dev"
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Search Methods

    func search(query: String, maxResults: Int = 20, scope: SearchScope = .all) async throws -> SearchResponse {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SearchError.invalidQuery
        }

        // iOS 26 HIG: Intelligent routing based on query context
        let endpoint: String
        switch scope {
        case .all:
            // Smart detection: ISBN → Title search, otherwise use title search
            // Title search handles ISBNs intelligently + provides best coverage
            endpoint = "/search/title"
        case .title:
            endpoint = "/search/title"
        case .author:
            endpoint = "/search/author"
        case .isbn:
            // Dedicated ISBN endpoint for ISBNdb lookups (7-day cache, most accurate)
            endpoint = "/search/isbn"
        }

        let urlString = "\(baseURL)\(endpoint)?q=\(encodedQuery)&maxResults=\(maxResults)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw SearchError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        // Extract performance headers
        let cacheStatus = httpResponse.allHeaderFields["X-Cache"] as? String ?? "MISS"
        let provider = httpResponse.allHeaderFields["X-Provider"] as? String ?? "unknown"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)

        // Parse response based on format
        let apiResponse: APISearchResponse
        do {
            apiResponse = try JSONDecoder().decode(APISearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }

        // Check if this is an enhanced format response or legacy format
        let isEnhancedFormat = apiResponse.format == "enhanced_work_edition_v1"

        let results: [SearchResult]

        if isEnhancedFormat {
            // Handle enhanced Work/Edition format
            results = apiResponse.items.compactMap { bookItem in
                return convertEnhancedItemToSearchResult(bookItem, provider: provider)
            }
        } else {
            // Handle legacy Google Books format for backward compatibility
            results = apiResponse.items.map { bookItem in
                // Create authors first
                let authors = (bookItem.volumeInfo.authors ?? []).map { authorName in
                    Author(name: authorName, gender: .unknown, culturalRegion: .international)
                }

                // Create work with authors properly set
                let work = Work(
                    title: bookItem.volumeInfo.title,
                    authors: authors.isEmpty ? [] : authors, // Pass authors in constructor
                    originalLanguage: bookItem.volumeInfo.language,
                    firstPublicationYear: extractYear(from: bookItem.volumeInfo.publishedDate),
                    subjectTags: bookItem.volumeInfo.categories ?? []
                )
                
                // Set external identifiers
                work.googleBooksVolumeID = bookItem.id
                work.isbndbQuality = 75 // Default quality for Google Books data
                
                let edition = convertToEdition(from: bookItem, work: work)

                return SearchResult(
                    work: work,
                    editions: [edition],
                    authors: authors,
                    relevanceScore: 1.0,
                    provider: provider
                )
            }
        }

        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0 // Will be calculated by caller
        )
    }

    func getTrendingBooks() async throws -> SearchResponse {
        // For now, return a curated list of trending books
        // In the future, this could be a separate API endpoint
        return try await search(query: "bestseller 2024", maxResults: 12)
    }

    /// Advanced search with multiple criteria (author, title, ISBN)
    /// Backend performs filtering to return clean results
    func advancedSearch(
        author: String?,
        title: String?,
        isbn: String?
    ) async throws -> SearchResponse {
        // Build query parameters
        var urlComponents = URLComponents(string: "\(baseURL)/search/advanced")!
        var queryItems: [URLQueryItem] = []
        
        if let author = author, !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        if let title = title, !title.isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let isbn = isbn, !isbn.isEmpty {
            queryItems.append(URLQueryItem(name: "isbn", value: isbn))
        }
        
        queryItems.append(URLQueryItem(name: "maxResults", value: "20"))
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw SearchError.invalidURL
        }
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(from: url)
        } catch {
            throw SearchError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }
        
        // Extract performance headers
        let cacheStatus = httpResponse.allHeaderFields["X-Cache"] as? String ?? "MISS"
        let provider = httpResponse.allHeaderFields["X-Provider"] as? String ?? "advanced-search"
        let cacheHitRate = calculateCacheHitRate(from: cacheStatus)
        
        // Parse response
        let apiResponse: APISearchResponse
        do {
            apiResponse = try JSONDecoder().decode(APISearchResponse.self, from: data)
        } catch {
            throw SearchError.decodingError(error)
        }
        
        // Check format and convert
        let isEnhancedFormat = apiResponse.format == "enhanced_work_edition_v1"
        
        let results: [SearchResult]
        if isEnhancedFormat {
            results = apiResponse.items.compactMap { bookItem in
                return convertEnhancedItemToSearchResult(bookItem, provider: provider)
            }
        } else {
            // Legacy format conversion
            results = apiResponse.items.map { bookItem in
                let authors = (bookItem.volumeInfo.authors ?? []).map { authorName in
                    Author(name: authorName, gender: .unknown, culturalRegion: .international)
                }
                
                let work = Work(
                    title: bookItem.volumeInfo.title,
                    authors: authors.isEmpty ? [] : authors,
                    originalLanguage: bookItem.volumeInfo.language,
                    firstPublicationYear: extractYear(from: bookItem.volumeInfo.publishedDate),
                    subjectTags: bookItem.volumeInfo.categories ?? []
                )
                
                work.googleBooksVolumeID = bookItem.id
                work.isbndbQuality = 75
                
                let edition = convertToEdition(from: bookItem, work: work)
                
                return SearchResult(
                    work: work,
                    editions: [edition],
                    authors: authors,
                    relevanceScore: 1.0,
                    provider: provider
                )
            }
        }
        
        return SearchResponse(
            results: results,
            cacheHitRate: cacheHitRate,
            provider: provider,
            responseTime: 0
        )
    }

    // MARK: - Helper Methods

    private func calculateCacheHitRate(from cacheStatus: String) -> Double {
        if cacheStatus.contains("HIT") {
            return 1.0
        } else {
            return 0.0
        }
    }

    private func convertToWork(from bookItem: APIBookItem) -> Work {
        let volumeInfo = bookItem.volumeInfo
        let work = Work(
            title: volumeInfo.title,
            originalLanguage: volumeInfo.language,
            firstPublicationYear: extractYear(from: volumeInfo.publishedDate),
            subjectTags: volumeInfo.categories ?? []
        )

        // Set external identifiers
        work.googleBooksVolumeID = bookItem.id
        work.isbndbQuality = 75 // Default quality for Google Books data

        return work
    }

    private func convertToEdition(from bookItem: APIBookItem, work: Work) -> Edition {
        let volumeInfo = bookItem.volumeInfo
        let isbn = volumeInfo.industryIdentifiers?.first { $0.type.contains("ISBN") }?.identifier

        return Edition(
            isbn: isbn,
            publisher: volumeInfo.publisher,
            publicationDate: volumeInfo.publishedDate,
            pageCount: volumeInfo.pageCount,
            format: .paperback, // Default format since not specified in Google Books API
            coverImageURL: volumeInfo.imageLinks?.thumbnail,
            work: work
        )
    }

    private func extractYear(from dateString: String?) -> Int? {
        guard let dateString = dateString else { return nil }
        let yearString = String(dateString.prefix(4))
        return Int(yearString)
    }

    // MARK: - Enhanced Format Conversion

    private func convertEnhancedItemToSearchResult(_ bookItem: APIBookItem, provider: String) -> SearchResult? {
        let volumeInfo = bookItem.volumeInfo

        // Create Author objects first
        let authors = (volumeInfo.authors ?? []).map { authorName in
            Author(name: authorName, gender: .unknown, culturalRegion: .international)
        }

        // Create Work object with authors properly set
        let work = Work(
            title: volumeInfo.title,
            authors: authors.isEmpty ? [] : authors, // Pass authors in constructor
            originalLanguage: volumeInfo.language,
            firstPublicationYear: extractYear(from: volumeInfo.publishedDate),
            subjectTags: volumeInfo.categories ?? []
        )

        // Set external identifiers from enhanced API response
        work.isbndbID = volumeInfo.isbndbID
        work.openLibraryID = volumeInfo.openLibraryID
        work.googleBooksVolumeID = volumeInfo.googleBooksVolumeID
        work.isbndbQuality = 85 // Higher quality for enhanced format

        // Create Edition object
        let isbn = volumeInfo.industryIdentifiers?.first { $0.type.contains("ISBN") }?.identifier
        let edition = Edition(
            isbn: isbn,
            publisher: volumeInfo.publisher,
            publicationDate: volumeInfo.publishedDate,
            pageCount: volumeInfo.pageCount,
            format: EditionFormat.from(string: nil), // Default format
            coverImageURL: volumeInfo.imageLinks?.thumbnail,
            work: work
        )

        // Set external identifiers for edition
        edition.isbndbID = volumeInfo.isbndbID
        edition.openLibraryID = volumeInfo.openLibraryID
        edition.googleBooksVolumeID = volumeInfo.googleBooksVolumeID
        edition.isbndbQuality = 85

        // Add edition to work (handle optional editions array)
        if work.editions == nil {
            work.editions = []
        }
        work.editions?.append(edition)

        return SearchResult(
            work: work,
            editions: [edition],
            authors: authors,
            relevanceScore: 1.0,
            provider: provider
        )
    }

}

// MARK: - API Response Models

private struct APISearchResponse: Codable {
    let kind: String?
    let totalItems: Int?
    let items: [APIBookItem]
    let format: String?        // New field for enhanced format detection
    let provider: String?      // Provider information
    let cached: Bool?          // Cache status
}

private struct APIBookItem: Codable {
    let kind: String?
    let id: String?
    let volumeInfo: APIVolumeInfo
}

private struct APIVolumeInfo: Codable {
    let title: String
    let authors: [String]?
    let publishedDate: String?
    let publisher: String?
    let description: String?
    let industryIdentifiers: [APIIndustryIdentifier]?
    let pageCount: Int?
    let categories: [String]?
    let imageLinks: APIImageLinks?
    let language: String?

    // Enhanced format fields for external identifiers
    let isbndbID: String?
    let openLibraryID: String?
    let googleBooksVolumeID: String?
}

private struct APIIndustryIdentifier: Codable {
    let type: String
    let identifier: String
}

private struct APIImageLinks: Codable {
    let thumbnail: String?
    let smallThumbnail: String?
}


// MARK: - Response Models

public struct SearchResponse: Sendable {
    let results: [SearchResult]
    let cacheHitRate: Double
    let provider: String
    let responseTime: TimeInterval
}

// MARK: - Error Types

public enum SearchError: LocalizedError {
    case invalidQuery
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Extensions for Conversion

extension EditionFormat {
    static func from(string: String?) -> EditionFormat {
        guard let string = string?.lowercased() else { return .paperback }

        switch string {
        case "hardcover", "hardback": return .hardcover
        case "paperback", "softcover": return .paperback
        case "ebook", "digital": return .ebook
        case "audiobook", "audio": return .audiobook
        default: return .paperback
        }
    }
}

extension AuthorGender {
    static func from(string: String?) -> AuthorGender {
        guard let string = string?.lowercased() else { return .unknown }

        switch string {
        case "female", "f": return .female
        case "male", "m": return .male
        case "nonbinary", "non-binary", "nb": return .nonBinary
        case "other": return .other
        default: return .unknown
        }
    }
}

extension CulturalRegion {
    static func from(string: String?) -> CulturalRegion {
        guard let string = string?.lowercased() else { return .international }

        switch string {
        case "africa": return .africa
        case "asia": return .asia
        case "europe": return .europe
        case "north america", "northamerica": return .northAmerica
        case "south america", "southamerica": return .southAmerica
        case "oceania": return .oceania
        case "middle east", "middleeast": return .middleEast
        case "caribbean": return .caribbean
        case "central asia", "centralasia": return .centralAsia
        case "indigenous": return .indigenous
        default: return .international
        }
    }
}