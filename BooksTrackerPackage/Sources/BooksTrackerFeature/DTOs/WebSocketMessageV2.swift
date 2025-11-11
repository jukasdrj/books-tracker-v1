import Foundation

/// The unified WebSocket message schema for all WebSocket communications.
struct WebSocketMessageV2<T: Decodable>: Decodable {
    let type: MessageType
    let payload: Payload

    enum MessageType: String, Decodable {
        case heartbeat
        case progress
        case complete
        case error
    }

    struct Payload: Decodable {
        // Progress Payload
        let progress: Double?
        let statusMessage: String?

        // Completion Payload
        let data: T?

        // Error Payload
        let errorCode: String?
        let errorMessage: String?
    }
}
