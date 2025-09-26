import Foundation
import SwiftUI
import SwiftData

// MARK: - Search State Management

@Observable
public final class SearchModel: @unchecked Sendable {
    // Search state
    var searchText: String = ""
    var searchResults: [SearchResult] = []
    var isSearching: Bool = false
    var searchState: SearchState = .initial
    var errorMessage: String?

    // Trending/featured books for initial state
    var trendingBooks: [SearchResult] = []
    var searchSuggestions: [String] = []

    // Performance tracking
    var lastSearchTime: TimeInterval = 0
    var cacheHitRate: Double = 0.0

    // Dependencies
    private let apiService: BookSearchAPIService
    private var searchTask: Task<Void, Never>?

    public init(apiService: BookSearchAPIService = BookSearchAPIService()) {
        self.apiService = apiService
        Task { @MainActor in
            loadTrendingBooks()
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

    // MARK: - Public Methods

    @MainActor
    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resetToInitialState()
            return
        }

        // Cancel previous search
        searchTask?.cancel()

        // Update search text immediately for UI responsiveness
        searchText = query

        // Start search with debouncing
        searchTask = Task {
            // 500ms debounce delay
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            await performSearch(query: query)
        }
    }

    @MainActor
    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        errorMessage = nil
        resetToInitialState()
    }

    @MainActor
    func retryLastSearch() {
        guard !searchText.isEmpty else { return }
        search(query: searchText)
    }

    // MARK: - Private Methods

    @MainActor
    private func performSearch(query: String) async {
        isSearching = true
        searchState = .searching
        errorMessage = nil

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let response = try await apiService.search(query: query, maxResults: 20)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            // Update performance metrics
            lastSearchTime = CFAbsoluteTimeGetCurrent() - startTime
            cacheHitRate = response.cacheHitRate

            // Process results
            searchResults = response.results

            // Update UI state based on results
            if searchResults.isEmpty {
                searchState = .noResults
            } else {
                searchState = .results
            }

        } catch {
            guard !Task.isCancelled else { return }

            errorMessage = error.localizedDescription
            searchState = .error(error.localizedDescription)
        }

        isSearching = false
    }

    @MainActor
    private func resetToInitialState() {
        searchState = .initial
        searchResults = []
        errorMessage = nil
        isSearching = false
    }

    @MainActor
    private func loadTrendingBooks() {
        // Load trending books for initial state
        Task {
            do {
                let response = try await apiService.getTrendingBooks()
                trendingBooks = response.results
            } catch {
                // Silently fail for trending books - not critical
                print("Failed to load trending books: \(error)")
            }
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
        work.authorNames
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

    func search(query: String, maxResults: Int = 20) async throws -> SearchResponse {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SearchError.invalidQuery
        }

        let urlString = "\(baseURL)/search/auto?q=\(encodedQuery)&maxResults=\(maxResults)"
        guard let url = URL(string: urlString) else {
            throw SearchError.invalidURL
        }

        let (data, response) = try await urlSession.data(from: url)

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

        // Parse response
        let apiResponse = try JSONDecoder().decode(APISearchResponse.self, from: data)

        // Convert to SearchResult objects
        let results = apiResponse.items.map { bookItem in
            let work = convertToWork(from: bookItem)
            let edition = convertToEdition(from: bookItem, work: work)
            let authors = (bookItem.volumeInfo.authors ?? []).map { authorName in
                Author(name: authorName, gender: .unknown, culturalRegion: .international)
            }

            return SearchResult(
                work: work,
                editions: [edition],
                authors: authors,
                relevanceScore: 1.0,
                provider: provider
            )
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

}

// MARK: - API Response Models

private struct APISearchResponse: Codable {
    let kind: String?
    let totalItems: Int?
    let items: [APIBookItem]
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