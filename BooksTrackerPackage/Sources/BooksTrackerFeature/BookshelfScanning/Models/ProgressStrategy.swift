import Foundation

/// Strategy for tracking background job progress
public enum ProgressStrategy: Sendable, CustomStringConvertible {
    /// Real-time WebSocket updates (8ms latency, preferred)
    case webSocket

    /// HTTP polling fallback (2s interval, reliable)
    case polling

    public var description: String {
        switch self {
        case .webSocket:
            return "WebSocket (real-time)"
        case .polling:
            return "HTTP Polling (fallback)"
        }
    }
}
