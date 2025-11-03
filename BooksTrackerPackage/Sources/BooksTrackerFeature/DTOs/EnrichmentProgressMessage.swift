import Foundation

/// Namespace for enrichment WebSocket messages
enum EnrichmentProgressMessage {

    /// A generic message for decoding the `type` field to determine the specific message type.
    struct GenericMessage: Codable {
        let type: String
    }

    /// A message indicating the progress of the enrichment job.
    struct Progress: Codable {
        let type: String
        let processedCount: Int
        let totalCount: Int
        let currentTitle: String
    }

    /// A message indicating the completion of the enrichment job.
    struct Complete: Codable {
        let type: String
        let message: String
    }
}
