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
public final class StarscreamWebSocketHandler: NSObject, WebSocketDelegate {

    // MARK: - Properties

    private var socket: WebSocket?
    private var jobId: String?
    private var isConnected = false

    /// Batch progress handler (for shelf scanning)
    public var onBatchProgress: ((BatchProgress) -> Void)?

    /// Generic progress handler (for enrichment)
    public var onProgress: ((Double, String) -> Void)?

    /// Disconnection handler called when connection drops
    public var onDisconnect: (() -> Void)?

    // Track batch progress state for updates
    private var batchProgress: BatchProgress?

    public override init() {
        super.init()
    }

    // MARK: - Connection Management

    /// Connect to WebSocket endpoint with authentication
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - token: Authentication token from POST response
    ///   - batchProgress: Optional BatchProgress for shelf scanning (will be updated via onBatchProgress)
    public func connect(jobId: String, token: String, batchProgress: BatchProgress? = nil) {
        self.jobId = jobId
        self.batchProgress = batchProgress

        // ✅ SECURITY: Token NOT in URL (Issue #163)
        let urlString = "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)"
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("[Starscream] ❌ Invalid WebSocket URL")
            #endif
            onDisconnect?()
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

    /// Send ready signal to backend to start processing (optional - some flows don't need this)
    public func sendReadySignal() {
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
    public func disconnect() {
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
                onDisconnect?()

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
                onDisconnect?()

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
            print("[Starscream] ✅ Decoded message type: \(message.type), pipeline: \(message.pipeline)")
            #endif

            // Handle based on pipeline type
            switch message.pipeline {
            case .aiScan:
                handleBatchMessage(message)
            case .batchEnrichment:
                handleEnrichmentMessage(message)
            case .csvImport:
                handleEnrichmentMessage(message)  // CSV uses same progress format as enrichment
            }

        } catch {
            #if DEBUG
            print("[Starscream] ❌ Decode error: \(error)")
            print("[Starscream] Raw message: \(text)")
            #endif
        }
    }

    /// Handle batch scanning messages (shelf scan)
    private func handleBatchMessage(_ message: TypedWebSocketMessage) {
        guard let batchProgress = batchProgress else {
            #if DEBUG
            print("[Starscream] ⚠️ Received batch message but no BatchProgress instance")
            #endif
            return
        }

        switch message.payload {
        case .batchProgress(let progressPayload):
            #if DEBUG
            print("[Starscream] Batch progress: photo \(progressPayload.currentPhoto)/\(progressPayload.totalPhotos)")
            #endif

            // Update batch progress state
            let photoIndex = progressPayload.currentPhoto - 1
            if photoIndex >= 0 && photoIndex < batchProgress.photos.count {
                let status: PhotoStatus
                switch progressPayload.photoStatus.lowercased() {
                case "processing": status = .processing
                case "complete": status = .complete
                case "error": status = .error
                default: status = .queued
                }

                batchProgress.updatePhoto(index: photoIndex, status: status)
                batchProgress.overallStatus = progressPayload.photoStatus
                batchProgress.totalBooksFound = progressPayload.totalBooksFound
            }

            onBatchProgress?(batchProgress)

        case .batchComplete(let completePayload):
            #if DEBUG
            print("[Starscream] Batch complete: \(completePayload.summary.totalDetected) books found")
            #endif

            batchProgress.complete(totalBooks: completePayload.summary.totalDetected)
            onBatchProgress?(batchProgress)

        case .error(let errorPayload):
            #if DEBUG
            print("[Starscream] Batch error: \(errorPayload.message)")
            #endif
            batchProgress.overallStatus = "error"
            onBatchProgress?(batchProgress)

        default:
            break
        }
    }

    /// Handle enrichment/CSV import messages (generic progress)
    private func handleEnrichmentMessage(_ message: TypedWebSocketMessage) {
        switch message.payload {
        case .jobProgress(let progressPayload):
            #if DEBUG
            print("[Starscream] Progress: \(Int(progressPayload.progress * 100))%")
            #endif
            onProgress?(progressPayload.progress, progressPayload.status)

        case .jobComplete:
            #if DEBUG
            print("[Starscream] Job complete")
            #endif
            onProgress?(1.0, "Complete")

        case .error(let errorPayload):
            #if DEBUG
            print("[Starscream] Error: \(errorPayload.message)")
            #endif
            onProgress?(0.0, "Error: \(errorPayload.message)")

        default:
            break
        }
    }

}
