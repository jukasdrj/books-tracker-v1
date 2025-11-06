import Foundation

/// Discriminated union for enrichment WebSocket messages
enum EnrichmentProgressMessage: Decodable {
    case progress(processedCount: Int, totalCount: Int, currentTitle: String)
    case complete(message: String, books: [EnrichedBook]?)
    case unknown
    
    /// Enriched book data from backend
    struct EnrichedBook: Decodable {
        let title: String
        let author: String?
        let isbn: String?
        let success: Bool
        let enriched: EnrichmentData?
        
        struct EnrichmentData: Decodable {
            let works: [WorkDTO]
            let editions: [EditionDTO]
            let authors: [AuthorDTO]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case processedCount
        case totalCount
        case currentTitle
        case message
        case data
    }
    
    private enum DataKeys: String, CodingKey {
        case books
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "progress":
            let processedCount = try container.decode(Int.self, forKey: .processedCount)
            let totalCount = try container.decode(Int.self, forKey: .totalCount)
            let currentTitle = try container.decode(String.self, forKey: .currentTitle)
            self = .progress(processedCount: processedCount, totalCount: totalCount, currentTitle: currentTitle)

        case "complete":
            let message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Enrichment complete"
            
            // Try to decode the nested data.books array
            var books: [EnrichedBook]? = nil
            if let dataContainer = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data) {
                books = try? dataContainer.decode([EnrichedBook].self, forKey: .books)
            }
            
            self = .complete(message: message, books: books)

        default:
            self = .unknown
        }
    }
}
