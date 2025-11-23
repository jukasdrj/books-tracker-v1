import Foundation
import Network

/// NWConnection-based WebSocket implementation with HTTP/1.1 enforcement
/// Replaces URLSession WebSocket to fix ALPN HTTP/2 negotiation issues
///
/// WHY: URLSession WebSockets negotiate HTTP/2 via ALPN, breaking RFC 6455 upgrade.
/// SOLUTION: Network.framework's NWConnection allows explicit HTTP/1.1 enforcement.
@available(iOS 13.0, *)
@MainActor
final class NWConnectionWebSocket {

    // MARK: - Properties

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var isConnected: Bool = false

    private let queue = DispatchQueue(label: "com.bookstrack.websocket", qos: .userInitiated)

    /// Message handler called when WebSocket receives a message
    var onMessage: ((String) -> Void)?

    /// Disconnection handler called when connection drops
    var onDisconnect: ((Error?) -> Void)?

    // MARK: - Connection Management

    /// Connect to WebSocket endpoint with explicit HTTP/1.1 enforcement
    /// - Parameters:
    ///   - url: WebSocket URL (wss://)
    ///   - timeout: Connection timeout in seconds
    /// - Throws: NWError if connection fails
    func connect(to url: URL, timeout: TimeInterval = 10.0) async throws {
        guard connection == nil else {
            throw NWError.posix(.EISCONN) // Already connected
        }

        // Extract host and port from URL
        guard let host = url.host else {
            throw NWError.posix(.EINVAL)
        }
        let port = url.port ?? 443 // Default to 443 for wss://

        // Create TLS options with HTTP/1.1 enforcement
        let tlsOptions = NWProtocolTLS.Options()

        // CRITICAL: Set ALPN protocols to ["http/1.1"] to prevent HTTP/2 negotiation
        // This forces the TLS handshake to negotiate HTTP/1.1 only
        sec_protocol_options_set_tls_application_protocol_negotiation_block(
            tlsOptions.securityProtocolOptions,
            { (metadata, protocols) in
                // Only allow HTTP/1.1
                protocols([Data("http/1.1".utf8)])
            },
            queue
        )

        // Create WebSocket options
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        // Set custom HTTP headers for WebSocket upgrade
        wsOptions.setAdditionalHeaders([
            (":path", url.path + (url.query.map { "?\($0)" } ?? "")),
            ("host", host),
            ("upgrade", "websocket"),
            ("connection", "Upgrade"),
            ("sec-websocket-version", "13")
        ])

        // Build protocol stack: TLS (with HTTP/1.1) → WebSocket
        let parameters = NWParameters(tls: tlsOptions)
        let wsProtocol = NWProtocolWebSocket.Options.Definition.createOptions(wsOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsProtocol, at: 0)

        // Create connection
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection

        // Start connection on dedicated queue
        connection.start(queue: queue)

        // Wait for connection to be ready
        return try await withCheckedThrowingContinuation { continuation in
            var continuationResumed = false

            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        guard !continuationResumed else { return }
                        continuationResumed = true
                        self?.isConnected = true
                        #if DEBUG
                        print("[NWWebSocket] ✅ Connection established (HTTP/1.1)")
                        #endif
                        continuation.resume()

                        // Start receiving messages
                        self?.startReceiving()

                    case .failed(let error):
                        guard !continuationResumed else { return }
                        continuationResumed = true
                        #if DEBUG
                        print("[NWWebSocket] ❌ Connection failed: \(error)")
                        #endif
                        continuation.resume(throwing: error)

                    case .cancelled:
                        guard !continuationResumed else { return }
                        continuationResumed = true
                        #if DEBUG
                        print("[NWWebSocket] Connection cancelled")
                        #endif
                        continuation.resume(throwing: NWError.posix(.ECANCELED))

                    case .waiting(let error):
                        #if DEBUG
                        print("[NWWebSocket] ⏳ Waiting: \(error)")
                        #endif

                    case .preparing:
                        #if DEBUG
                        print("[NWWebSocket] 🔄 Preparing connection...")
                        #endif

                    default:
                        break
                    }
                }
            }

            // Timeout handling
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !continuationResumed else { return }
                continuationResumed = true
                #if DEBUG
                print("[NWWebSocket] ❌ Connection timeout")
                #endif
                connection.cancel()
                continuation.resume(throwing: NWError.posix(.ETIMEDOUT))
            }
        }
    }

    /// Send a text message over WebSocket
    /// - Parameter text: Message string to send
    /// - Throws: NWError if send fails
    func send(_ text: String) async throws {
        guard let connection = connection, isConnected else {
            throw NWError.posix(.ENOTCONN)
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textMessage", metadata: [metadata])

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error = error {
                    #if DEBUG
                    print("[NWWebSocket] ❌ Send failed: \(error)")
                    #endif
                    continuation.resume(throwing: error)
                } else {
                    #if DEBUG
                    print("[NWWebSocket] ✅ Message sent: \(text.prefix(100))")
                    #endif
                    continuation.resume()
                }
            })
        }
    }

    /// Disconnect WebSocket connection
    func disconnect() {
        #if DEBUG
        print("[NWWebSocket] 🔌 Disconnecting...")
        #endif

        receiveTask?.cancel()
        receiveTask = nil

        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Private Methods

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled, let connection = await self.connection, await self.isConnected {
                do {
                    let message = try await self.receiveMessage(from: connection)

                    await MainActor.run {
                        self.onMessage?(message)
                    }
                } catch {
                    #if DEBUG
                    await MainActor.run {
                        print("[NWWebSocket] ❌ Receive error: \(error)")
                    }
                    #endif

                    await MainActor.run {
                        self.isConnected = false
                        self.onDisconnect?(error)
                    }
                    break
                }
            }
        }
    }

    private func receiveMessage(from connection: NWConnection) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data, !data.isEmpty else {
                    continuation.resume(throwing: NWError.posix(.ENODATA))
                    return
                }

                if let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: NWError.posix(.EBADMSG))
                }
            }
        }
    }
}
