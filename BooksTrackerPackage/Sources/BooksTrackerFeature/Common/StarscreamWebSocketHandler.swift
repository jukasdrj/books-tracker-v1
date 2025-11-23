import Foundation
import Starscream

/// Starscream-based WebSocket handler with HTTP/1.1 enforcement
/// Solves ALPN HTTP/2 negotiation issues that plague URLSessionWebSocketTask
///
/// **Why Starscream:**
/// - Explicit control over HTTP headers and protocol negotiation
/// - Can force HTTP/1.1 (URLSession cannot)
/// - Proven solution used by many production iOS apps
/// - Works reliably with Cloudflare Workers WebSocket endpoints
@available(iOS 13.0, *)
@MainActor
final class StarscreamWebSocketHandler: NSObject, WebSocketDelegate {

    // MARK: - Properties

    private var socket: WebSocket?
    private var jobId: String?
    private var isConnected = false

    /// Progress handler called when job progress updates are received
    var onProgress: ((JobProgress) -> Void)?

    /// Disconnection handler called when connection drops
    var onDisconnect: ((Error?) -> Void)?

    // MARK: - Connection Management

    /// Connect to WebSocket endpoint with authentication
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - token: Authentication token from POST response
    /// - Throws: Never (errors handled via delegate)
    func connect(jobId: String, token: String) async {
        self.jobId = jobId

        // ✅ SECURITY: Token NOT in URL (Issue #163)
        let urlString = "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)"
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("[Starscream] ❌ Invalid WebSocket URL")
            #endif
            onDisconnect?(URLError(.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        // ✅ FORCE HTTP/1.1 - This is the key fix for ALPN HTTP/2 negotiation
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        // ✅ SECURITY: Pass token via Sec-WebSocket-Protocol header (Issue #163)
        // This prevents token leakage in server logs, browser history, network logs
        request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        #if DEBUG
        print("[Starscream] 🔌 Connecting to: \(urlString)")
        print("[Starscream] 🔐 Auth via Sec-WebSocket-Protocol header")
        #endif

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }

    /// Send ready signal to backend to start processing
    func sendReadySignal() {
        let readyMessage: [String: Any] = [
            "type": "ready",
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        if let messageData = try? JSONSerialization.data(withJSONObject: readyMessage),
           let messageString = String(data: messageData, encoding: .utf8) {
            socket?.write(string: messageString)
            #if DEBUG
            print("[Starscream] ✅ Sent ready signal")
            #endif
        }
    }

    /// Disconnect WebSocket connection
    func disconnect() {
        #if DEBUG
        print("[Starscream] 🔌 Disconnecting...")
        #endif
        socket?.disconnect()
        socket = nil
        isConnected = false
    }

    // MARK: - WebSocketDelegate

    nonisolated func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        Task { @MainActor in
            switch event {
            case .connected(let headers):
                #if DEBUG
                print("[Starscream] ✅ WebSocket connected")
                print("[Starscream] Response headers: \(headers)")
                #endif
                isConnected = true

            case .disconnected(let reason, let code):
                #if DEBUG
                print("[Starscream] ❌ Disconnected: \(reason) (code: \(code))")
                #endif
                isConnected = false

                // Create error from disconnect reason
                let error = NSError(
                    domain: "WebSocket",
                    code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: reason]
                )
                onDisconnect?(error)

            case .text(let string):
                #if DEBUG
                print("[Starscream] 📨 Received text: \(string.prefix(200))")
                #endif
                handleMessage(string)

            case .binary(let data):
                #if DEBUG
                print("[Starscream] 📨 Received binary: \(data.count) bytes")
                #endif
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }

            case .error(let error):
                #if DEBUG
                print("[Starscream] ❌ Error: \(error?.localizedDescription ?? "Unknown")")
                #endif
                onDisconnect?(error)

            case .cancelled:
                #if DEBUG
                print("[Starscream] ⚠️ Connection cancelled")
                #endif
                isConnected = false

            case .reconnectSuggested(let shouldReconnect):
                #if DEBUG
                print("[Starscream] 🔄 Reconnect suggested: \(shouldReconnect)")
                #endif

            case .viabilityChanged(let isViable):
                #if DEBUG
                print("[Starscream] 📶 Viability changed: \(isViable)")
                #endif

            case .peerClosed:
                #if DEBUG
                print("[Starscream] 🔌 Peer closed connection")
                #endif
                isConnected = false

            case .ping, .pong:
                // Heartbeat messages - no logging needed
                break
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            #if DEBUG
            print("[Starscream] ❌ Failed to convert text to data")
            #endif
            return
        }

        do {
            // Try to decode as TypedWebSocketMessage (unified schema)
            let message = try JSONDecoder().decode(TypedWebSocketMessage.self, from: data)

            #if DEBUG
            print("[Starscream] ✅ Decoded message type: \(message.type)")
            #endif

            // Convert to JobProgress and notify handler
            let jobProgress = convertToJobProgress(message)
            onProgress?(jobProgress)

        } catch {
            #if DEBUG
            print("[Starscream] ❌ Decode error: \(error)")
            print("[Starscream] Raw message: \(text)")
            #endif
        }
    }

    /// Convert TypedWebSocketMessage to JobProgress
    private func convertToJobProgress(_ message: TypedWebSocketMessage) -> JobProgress {
        switch message.payload {
        case .jobProgress(let progressPayload):
            return JobProgress(
                fractionCompleted: progressPayload.progress,
                processedCount: progressPayload.processedCount,
                totalCount: progressPayload.totalCount,
                currentStatus: progressPayload.status,
                currentWorkId: nil,
                keepAlive: nil,
                scanResult: nil
            )

        case .jobComplete(let completePayload):
            // Extract scan result if available
            var scanResult: ScanResult?
            if case .aiScan(let scanPayload) = completePayload {
                scanResult = ScanResult(
                    totalDetected: scanPayload.summary.totalDetected,
                    approved: scanPayload.summary.approved,
                    needsReview: scanPayload.summary.needsReview,
                    books: [], // Would need to fetch from resourceId
                    metadata: ScanResult.ScanMetadata(
                        processingTime: 0,
                        enrichedCount: 0,
                        timestamp: "",
                        modelUsed: ""
                    )
                )
            }

            return JobProgress(
                fractionCompleted: 1.0,
                processedCount: 0,
                totalCount: 0,
                currentStatus: "Complete",
                currentWorkId: nil,
                keepAlive: nil,
                scanResult: scanResult
            )

        case .error(let errorPayload):
            return JobProgress(
                fractionCompleted: 0.0,
                processedCount: 0,
                totalCount: 0,
                currentStatus: "Error: \(errorPayload.message)",
                currentWorkId: nil,
                keepAlive: nil,
                scanResult: nil
            )

        case .readyAck:
            return JobProgress(
                fractionCompleted: 0.0,
                processedCount: 0,
                totalCount: 0,
                currentStatus: "Ready",
                currentWorkId: nil,
                keepAlive: nil,
                scanResult: nil
            )

        default:
            return JobProgress(
                fractionCompleted: 0.0,
                processedCount: 0,
                totalCount: 0,
                currentStatus: "Processing",
                currentWorkId: nil,
                keepAlive: nil,
                scanResult: nil
            )
        }
    }
}

/// Job progress model (compatible with existing WebSocketProgressManager)
struct JobProgress {
    let fractionCompleted: Double
    let processedCount: Int
    let totalCount: Int
    let currentStatus: String
    let currentWorkId: String?
    let keepAlive: Bool?
    let scanResult: ScanResult?
}

/// Scan result model (compatible with existing types)
struct ScanResult {
    let totalDetected: Int
    let approved: Int
    let needsReview: Int
    let books: [BookData]
    let metadata: ScanMetadata

    struct BookData: Codable {
        // Placeholder - matches existing structure
    }

    struct ScanMetadata {
        let processingTime: Int
        let enrichedCount: Int
        let timestamp: String
        let modelUsed: String
    }
}
