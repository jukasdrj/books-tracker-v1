import Foundation
import Network
import os.log

/// WebSocket handler using NWConnection from Apple's Network framework
/// Fixes HTTP/2 protocol negotiation issues with URLSessionWebSocketTask
///
/// **Issue #513**: URLSessionWebSocketTask forces HTTP/2 via ALPN, breaking WebSocket upgrades.
/// NWConnection provides smart protocol negotiation that properly handles HTTP/1.1 for WebSockets.
///
/// **Benefits over URLSessionWebSocketTask:**
/// - ✅ Correct HTTP/1.1 negotiation for WebSocket Upgrade header
/// - ✅ Better performance (user-space networking stack)
/// - ✅ Automatic reconnection on network changes (Wi-Fi ↔ cellular)
/// - ✅ Built-in proxy support
/// - ✅ Native iOS 13+ solution (no third-party dependencies)
///
/// **Usage:**
/// ```swift
/// let handler = NWWebSocketHandler(
///     url: webSocketURL,
///     token: authToken,
///     pipeline: .batchEnrichment,
///     progressHandler: { progress in /* ... */ },
///     completionHandler: { complete in /* ... */ },
///     errorHandler: { error in /* ... */ }
/// )
/// await handler.connect()
/// ```
@MainActor
public final class NWWebSocketHandler {
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "NWWebSocket")

    // MARK: - Properties

    private var connection: NWConnection?
    private let url: URL
    private let token: String?
    private let pipeline: PipelineType
    private var isConnected = false
    private var shouldContinueListening = true

    // Handlers
    private let progressHandler: @MainActor (JobProgressPayload) -> Void
    private let completionHandler: @MainActor (JobCompletePayload) -> Void
    private let errorHandler: @MainActor (ErrorPayload) -> Void

    // MARK: - Initialization

    /// Initialize NWConnection-based WebSocket handler
    ///
    /// - Parameters:
    ///   - url: WebSocket URL (wss:// for secure, ws:// for insecure)
    ///   - token: Optional authentication token (sent via Sec-WebSocket-Protocol header)
    ///   - pipeline: Pipeline type for message routing validation
    ///   - progressHandler: Callback for job progress updates
    ///   - completionHandler: Callback for job completion
    ///   - errorHandler: Callback for errors
    public init(
        url: URL,
        token: String? = nil,
        pipeline: PipelineType,
        progressHandler: @escaping @MainActor (JobProgressPayload) -> Void,
        completionHandler: @escaping @MainActor (JobCompletePayload) -> Void,
        errorHandler: @escaping @MainActor (ErrorPayload) -> Void
    ) {
        self.url = url
        self.token = token
        self.pipeline = pipeline
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
        self.errorHandler = errorHandler
    }

    // MARK: - Public Methods

    /// Establish WebSocket connection using NWConnection
    /// This properly negotiates HTTP/1.1 for WebSocket Upgrade compatibility
    public func connect() async {
        logger.info("🔌 [NW] Connecting to \(self.url.absoluteString)")
        logger.debug("🔌 [NW] Pipeline: \(self.pipeline.rawValue)")

        // Configure WebSocket options
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true  // Automatically respond to server pings

        // ⚠️ SECURITY (Issue #163): Pass authentication token via Sec-WebSocket-Protocol header
        // Prevents token leakage in server logs (vs. query parameters)
        // CRITICAL: Use setSubprotocols() instead of setAdditionalHeaders() for Sec-WebSocket-Protocol
        if let token = token {
            options.setSubprotocols(["bookstrack-auth.\(token)"])
            logger.debug("🔑 [NW] Authentication token added via subprotocol")
        }

        // Create parameters based on URL scheme
        // wss:// uses TLS, ws:// uses plain TCP
        let parameters: NWParameters
        if url.scheme == "wss" {
            parameters = NWParameters.tls
            logger.debug("🔒 [NW] Using TLS parameters for wss://")
        } else {
            parameters = NWParameters.tcp
            logger.debug("📡 [NW] Using TCP parameters for ws://")
        }

        // CRITICAL: Insert WebSocket protocol at index 0 of application protocol stack
        // This ensures proper HTTP/1.1 → WebSocket upgrade negotiation
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        // Create NWConnection
        connection = NWConnection(to: .url(url), using: parameters)

        // Set up state change handler
        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStateChange(state)
            }
        }

        // Start receiving messages (recursive listener)
        receiveMessage()

        // Start the connection
        connection?.start(queue: .main)

        logger.info("✅ [NW] Connection initiated")
    }

    /// Disconnect from WebSocket
    public func disconnect() {
        guard isConnected else { return }

        shouldContinueListening = false
        isConnected = false
        connection?.cancel()
        connection = nil

        logger.info("🔌 [NW] Disconnected")
    }

    // MARK: - Private Methods - Connection State

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .setup:
            logger.debug("🔧 [NW] State: setup")

        case .preparing:
            logger.debug("⏳ [NW] State: preparing (negotiating protocols)")

        case .ready:
            logger.info("✅ [NW] State: ready (connection established)")
            isConnected = true

            // CRITICAL (Issue #378): Send ready signal to backend
            // Backend waits for this before processing to prevent race condition
            sendReadySignal()

        case .waiting(let error):
            logger.warning("⚠️ [NW] State: waiting - \(error.localizedDescription)")
            // Connection is waiting for network resources (e.g., no internet)
            // NWConnection will automatically retry

        case .failed(let error):
            logger.error("❌ [NW] State: failed - \(error.localizedDescription)")
            isConnected = false
            shouldContinueListening = false

            errorHandler(ErrorPayload(
                code: "NWCONNECTION_FAILED",
                message: "WebSocket connection failed: \(error.localizedDescription)",
                details: nil,
                retryable: true
            ))

        case .cancelled:
            logger.debug("🔌 [NW] State: cancelled")
            isConnected = false
            shouldContinueListening = false

        @unknown default:
            logger.warning("⚠️ [NW] Unknown state received")
        }
    }

    // MARK: - Private Methods - Message Handling

    /// Recursively listen for incoming WebSocket messages
    private func receiveMessage() {
        guard shouldContinueListening, isConnected || connection?.state == .preparing else {
            logger.debug("🛑 [NW] Stopped listening (shouldContinue=\(self.shouldContinueListening), connected=\(self.isConnected))")
            return
        }

        connection?.receiveMessage { [weak self] (data, context, isComplete, error) in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Double-check we should still be listening
                guard self.shouldContinueListening, self.isConnected else { return }

                if let error = error {
                    self.logger.error("❌ [NW] Receive error: \(error.localizedDescription)")
                    self.shouldContinueListening = false
                    return
                }

                if let data = data, let context = context {
                    self.handleReceivedMessage(data: data, context: context)
                }

                // Continue listening for more messages
                if self.shouldContinueListening && self.isConnected {
                    self.receiveMessage()
                }
            }
        }
    }

    /// Handle a received WebSocket message
    private func handleReceivedMessage(data: Data, context: NWConnection.ContentContext) {
        guard !data.isEmpty else {
            logger.debug("⚠️ [NW] Received empty message")
            return
        }

        guard let metadata = context.protocolMetadata.first as? NWProtocolWebSocket.Metadata else {
            logger.warning("⚠️ [NW] Missing WebSocket metadata")
            return
        }

        // Handle different WebSocket opcodes
        switch metadata.opcode {
        case .text:
            guard let text = String(data: data, encoding: .utf8) else {
                logger.error("❌ [NW] Failed to decode text message")
                return
            }
            logger.debug("📨 [NW] Received text message (\(data.count) bytes)")
            parseWebSocketMessage(text)

        case .binary:
            logger.debug("📨 [NW] Received binary message (\(data.count) bytes)")
            parseWebSocketMessage(data)

        case .ping:
            // autoReplyPing handles this automatically
            logger.debug("💓 [NW] Received ping (auto-replying)")

        case .pong:
            logger.debug("💓 [NW] Received pong")

        case .cont:
            logger.debug("📨 [NW] Received continuation frame")

        case .close:
            logger.debug("🔌 [NW] Received close frame")
            shouldContinueListening = false

        @unknown default:
            logger.warning("⚠️ [NW] Unknown opcode received")
        }
    }

    /// Parse WebSocket message from text
    private func parseWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            logger.error("❌ [NW] Failed to convert text to data")
            return
        }
        parseWebSocketMessage(data)
    }

    /// Parse WebSocket message from data
    private func parseWebSocketMessage(_ data: Data) {
        let decoder = JSONDecoder()

        do {
            let typedMessage = try decoder.decode(TypedWebSocketMessage.self, from: data)

            logger.debug("✅ [NW] Decoded message type: \(typedMessage.type.rawValue), pipeline: \(typedMessage.pipeline.rawValue)")

            // Verify pipeline matches (safety check)
            guard typedMessage.pipeline == pipeline else {
                logger.warning("⚠️ [NW] Pipeline mismatch: expected \(self.pipeline.rawValue), got \(typedMessage.pipeline.rawValue)")
                return
            }

            // Route message to appropriate handler
            switch typedMessage.payload {
            case .jobProgress(let payload):
                logger.debug("📊 [NW] Progress update: \(payload.progress * 100)%, status: \(payload.status)")
                progressHandler(payload)

            case .reconnected(let payload):
                logger.debug("🔄 [NW] Reconnected payload received")
                progressHandler(payload.toJobProgressPayload())

            case .jobComplete(let payload):
                // CRITICAL: Stop listening BEFORE calling handler
                // Prevents "connection not ready" errors
                shouldContinueListening = false
                logger.info("✅ [NW] Job complete, stopping message loop")
                completionHandler(payload)
                disconnect()

            case .error(let payload):
                // Stop listening before handling error
                shouldContinueListening = false
                logger.warning("⚠️ [NW] Error message: \(payload.code) - \(payload.message)")
                errorHandler(payload)
                disconnect()

            case .readyAck:
                logger.debug("✅ [NW] Ready acknowledgment received from backend")

            case .jobStarted:
                logger.debug("🚀 [NW] Job started notification received")

            case .ping, .pong:
                logger.debug("💓 [NW] Keep-alive ping/pong received")

            case .batchInit, .batchProgress, .batchComplete, .batchCanceling:
                // Batch scanning messages - ignore in this handler
                // These should never reach here due to pipeline filtering
                break
            }

        } catch {
            logger.error("❌ [NW] Failed to decode message: \(error.localizedDescription)")
            if let jsonString = String(data: data, encoding: .utf8) {
                logger.debug("Raw JSON: \(jsonString.prefix(200))")
            }

            // Stop listening before handling decoding error
            shouldContinueListening = false
            errorHandler(ErrorPayload(
                code: "CLIENT_DECODING_ERROR",
                message: "Failed to decode WebSocket message: \(error.localizedDescription)",
                details: String(data: data, encoding: .utf8).map { AnyCodable($0) },
                retryable: false
            ))
            disconnect()
        }
    }

    /// Send ready signal to backend after connection established
    /// Prevents race condition where server processes before client is listening
    private func sendReadySignal() {
        let readyMessage = ["type": "ready"]

        guard let jsonData = try? JSONEncoder().encode(readyMessage),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("❌ [NW] Failed to encode ready signal")
            return
        }

        send(jsonString)
        logger.debug("📤 [NW] Sent ready signal to backend")
    }

    /// Send a text message over the WebSocket connection
    private func send(_ message: String) {
        guard let data = message.data(using: .utf8) else {
            logger.error("❌ [NW] Failed to convert message to data")
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "textMessage",
            metadata: [metadata]
        )

        connection?.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed({ [weak self] error in
                if let error = error {
                    self?.logger.error("❌ [NW] Send error: \(error.localizedDescription)")
                } else {
                    self?.logger.debug("✅ [NW] Message sent successfully")
                }
            })
        )
    }
}
