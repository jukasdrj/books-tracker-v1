import Foundation

/// API client for triggering backend enrichment jobs
actor EnrichmentAPIClient {

    private let baseURL = "https://api-worker.jukasdrj.workers.dev"

    struct EnrichmentResult: Codable, Sendable {
        let success: Bool
        let processedCount: Int
        let totalCount: Int
    }

    /// Start enrichment job on backend
    /// Backend will push progress updates via WebSocket
    /// - Parameter jobId: Unique job identifier for WebSocket tracking
    /// - Returns: Enrichment result with final counts
    func startEnrichment(jobId: String, workIds: [String]) async throws -> EnrichmentResult {
        let url = URL(string: "\(baseURL)/api/enrichment/start")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "jobId": jobId,
            "workIds": workIds
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(EnrichmentResult.self, from: data)
    }
}
