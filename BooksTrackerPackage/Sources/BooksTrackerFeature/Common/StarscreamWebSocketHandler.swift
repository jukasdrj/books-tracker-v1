import Foundation
import Starscream
import os.log

// MARK: - WebSocket Error Types

public enum WebSocketError: Error, LocalizedError {
    case invalidURL(String)
    case invalidToken
    case malformedToken
    case connectionFailed(Error)
    case connectionError(Error)
    case authenticationFailed(code: UInt16)
    case messageDecodingFailed(Error)
    case pipelineMismatch(expected: PipelineType, received: PipelineType)
    case unexpectedDisconnection(reason: String, code: UInt16)
    case unknownError

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid WebSocket URL: \(url)"
        case .invalidToken:
            return "Authentication token is empty or missing"
        case .malformedToken:
            return "Authentication token format is invalid"
        case .connectionFailed(let error):
            return "WebSocket connection failed: \(error.localizedDescription)"
        case .connectionError(let error):
            return "WebSocket error: \(error.localizedDescription)"
        case .authenticationFailed(let code):
            return "WebSocket authentication failed (code: \(code))"
        case .messageDecodingFailed(let error):
            return "Failed to decode WebSocket message: \(error.localizedDescription)"
        case .pipelineMismatch(let expected, let received):
            return "Pipeline mismatch: expected \(expected.rawValue), received \(received.rawValue)"
        case .unexpectedDisconnection(let reason, let code):
            return "WebSocket disconnected unexpectedly: \(reason) (code: \(code))"
        case .unknownError:
            return "An unknown WebSocket error occurred"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .connectionFailed, .connectionError, .unexpectedDisconnection:
            return true
        case .invalidURL, .invalidToken, .malformedToken, .authenticationFailed:
            return false
        default:
            return false
        }
    }
}

private let logger = Logger(
    subsystem: "com.oooefam.booksV3",
    category: "StarscreamWebSocket"
)

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

    /// Enrichment progress handler (processedCount, totalCount, currentTitle)
    public var onEnrichmentProgress: ((JobProgressPayload) -> Void)?

    /// Enrichment completion handler
    public var onEnrichmentComplete: ((JobCompletePayload) -> Void)?

    /// Disconnection handler called when connection drops
    public var onDisconnect: (() -> Void)?

    /// Error handler called when an error occurs
    public var onError: ((WebSocketError) -> Void)?

    // Track batch progress state for updates
    private var batchProgress: BatchProgress?

    // Track pipeline type for proper message routing
    private var pipeline: PipelineType?

    public override init() {
        super.init()
    }

    // MARK: - Connection Management

    /// Connect to WebSocket endpoint with authentication
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - token: Authentication token from POST response
    ///   - pipeline: WebSocket pipeline type (aiScan, batchEnrichment, csvImport)
    ///   - batchProgress: Optional BatchProgress for shelf scanning (will be updated via onBatchProgress)
    public func connect(jobId: String, token: String, pipeline: PipelineType, batchProgress: BatchProgress? = nil) {
        self.jobId = jobId
        self.batchProgress = batchProgress
        self.pipeline = pipeline

        // Validate token is not empty
        guard !token.isEmpty else {
            let error = WebSocketError.invalidToken
            logger.error("[Starscream] ❌ Empty authentication token")
            onError?(error)
            return
        }

        // ✅ SECURITY: Token NOT in URL (Issue #163)
        let urlString = "\(EnrichmentConfig.webSocketBaseURL)/ws/progress?jobId=\(jobId)"
        guard let url = URL(string: urlString) else {
            let error = WebSocketError.invalidURL(urlString)
            logger.error("[Starscream] ❌ Invalid WebSocket URL: \(urlString)")
            onError?(error)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        // WebSocket upgrade headers per RFC 6455
        // HTTP/1.1 enforcement is handled by Starscream's use of NWProtocolWebSocket
        // which does not support HTTP/2 ALPN (this is the actual fix for Issue #227)
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        // ✅ SECURITY: Pass token via Sec-WebSocket-Protocol header (Issue #163)
        // This prevents token leakage in server logs, browser history, network logs
        request.setValue("bookstrack-auth.\(token)", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        logger.debug("[Starscream] 🔌 Connecting to: \(urlString)")
        logger.info("[Starscream] 🔐 Auth via Sec-WebSocket-Protocol header")

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
            logger.debug("[Starscream] ✅ Sent ready signal")
        }
    }

    /// Disconnect WebSocket connection
    nonisolated public func disconnect() {
        Task { @MainActor in
            logger.debug("[Starscream] 🔌 Disconnecting...")
            socket?.disconnect()
            socket = nil
            isConnected = false
        }
    }

    // MARK: - WebSocketDelegate

    nonisolated public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        Task { @MainActor in
            switch event {
            case .connected(let headers):
                logger.info("[Starscream] ✅ WebSocket connected")
                logger.debug("[Starscream] Response headers: \(headers)")
                isConnected = true

            case .disconnected(let reason, let code):
                logger.warning("[Starscream] ❌ Disconnected: \(reason) (code: \(code))")
                isConnected = false

                // Notify error if unexpected disconnection (not 1000 normal closure)
                if code != 1000 {
                    onError?(WebSocketError.unexpectedDisconnection(reason: reason, code: code))
                }

                onDisconnect?()

            case .text(let string):
                logger.debug("[Starscream] 📨 Received text: \(string.prefix(200))")
                handleMessage(string)

            case .binary(let data):
                logger.debug("[Starscream] 📨 Received binary: \(data.count) bytes")
                if let text = String(data: data, encoding: .utf8) {
                    handleMessage(text)
                }

            case .error(let error):
                logger.error("[Starscream] ❌ Error: \(error?.localizedDescription ?? "Unknown")")

                // Propagate error with context
                if let error = error {
                    onError?(WebSocketError.connectionError(error))
                } else {
                    onError?(WebSocketError.unknownError)
                }

                // Still call disconnect for cleanup
                onDisconnect?()

            case .cancelled:
                logger.warning("[Starscream] ⚠️ Connection cancelled")
                isConnected = false

            case .reconnectSuggested(let shouldReconnect):
                logger.info("[Starscream] 🔄 Reconnect suggested: \(shouldReconnect)")
                // TODO: Implement reconnection logic with exponential backoff

            case .viabilityChanged(let isViable):
                logger.debug("[Starscream] 📶 Viability changed: \(isViable)")

            case .peerClosed:
                logger.info("[Starscream] 🔌 Peer closed connection")
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
            logger.error("[Starscream] ❌ Failed to convert text to data")
            return
        }

        do {
            // Try to decode as TypedWebSocketMessage (unified schema)
            let message = try JSONDecoder().decode(TypedWebSocketMessage.self, from: data)

            logger.debug("[Starscream] ✅ Decoded message type: \(message.type), pipeline: \(message.pipeline)")

            // Validate pipeline matches expected
            if let expectedPipeline = pipeline, message.pipeline != expectedPipeline {
                logger.warning("⚠️ Pipeline mismatch: received \(message.pipeline.rawValue), expected \(expectedPipeline.rawValue)")
                onError?(WebSocketError.pipelineMismatch(expected: expectedPipeline, received: message.pipeline))
                return
            }

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
            logger.error("[Starscream] ❌ Decode error: \(error.localizedDescription)")
            logger.debug("[Starscream] Raw message: \(text)")
            onError?(WebSocketError.messageDecodingFailed(error))
        }
    }

    /// Handle batch scanning messages (shelf scan)
    private func handleBatchMessage(_ message: TypedWebSocketMessage) {
        guard let batchProgress = batchProgress else {
            logger.warning("[Starscream] ⚠️ Received batch message but no BatchProgress instance")
            return
        }

        switch message.payload {
        case .batchProgress(let progressPayload):
            logger.debug("[Starscream] Batch progress: photo \(progressPayload.currentPhoto)/\(progressPayload.totalPhotos)")

            // Update batch progress state with edge case validation
            let photoIndex = progressPayload.currentPhoto - 1
            guard photoIndex >= 0 && photoIndex < batchProgress.photos.count else {
                logger.warning("⚠️ Invalid photo index: \(photoIndex) (total: \(batchProgress.photos.count))")
                logger.debug("Payload: currentPhoto=\(progressPayload.currentPhoto), totalPhotos=\(progressPayload.totalPhotos)")
                // Still update overall progress even if specific photo fails
                batchProgress.overallStatus = progressPayload.photoStatus
                batchProgress.totalBooksFound = progressPayload.totalBooksFound
                onBatchProgress?(batchProgress)
                return
            }

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

            onBatchProgress?(batchProgress)

        case .batchComplete(let completePayload):
            logger.info("[Starscream] Batch complete: \(completePayload.totalBooks) books found")

            batchProgress.complete(totalBooks: completePayload.totalBooks)
            onBatchProgress?(batchProgress)

        case .error(let errorPayload):
            logger.error("[Starscream] Batch error: \(errorPayload.message)")
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
            logger.debug("[Starscream] Progress: \(Int(progressPayload.progress * 100))%")
            onEnrichmentProgress?(progressPayload)

        case .jobComplete(let completePayload):
            logger.info("[Starscream] Job complete")
            onEnrichmentComplete?(completePayload)

        case .error(let errorPayload):
            logger.error("[Starscream] Error: \(errorPayload.message)")
            // Create error progress payload
            let errorProgress = JobProgressPayload(
                type: "error",
                progress: 0.0,
                processedCount: 0,
                totalCount: 0,
                status: "Error: \(errorPayload.message)",
                currentItem: nil
            )
            onEnrichmentProgress?(errorProgress)

        default:
            break
        }
    }

}
