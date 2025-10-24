import Foundation

/// Connection token proving WebSocket is ready for job binding
/// Issued after initial handshake, before jobId configuration
public struct ConnectionToken: Sendable {
    let connectionId: String
    let createdAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 30  // 30 second validity window
    }
}

/// Manages WebSocket connections for real-time progress updates
/// Replaces polling-based progress tracking with server push notifications
///
/// CRITICAL: Uses WebSocket-first protocol to prevent race conditions
/// - Step 1: establishConnection() - Connect BEFORE job starts
/// - Step 2: configureForJob(jobId:) - Bind to specific job after connection ready
/// - Result: Server processes ONLY after WebSocket is listening
@MainActor
public final class WebSocketProgressManager: ObservableObject {

    // MARK: - Properties

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var progressHandler: ((JobProgress) -> Void)?
    private var boundJobId: String?

    // Backend configuration
    // UNIFIED: All bookshelf AI traffic goes to bookshelf-ai-worker (no split-brain routing)
    private let baseURL = "wss://bookshelf-ai-worker.jukasdrj.workers.dev"
    private let connectionTimeout: TimeInterval = 10.0  // 10 seconds for initial handshake
    private let readySignalEndpoint = "https://bookshelf-ai-worker.jukasdrj.workers.dev"

    // MARK: - Public Methods

    public init() {}

    /// STEP 1: Establish WebSocket connection BEFORE job starts
    /// This prevents race condition where server processes before client listens
    ///
    /// - Parameter jobId: Client-generated job identifier for WebSocket binding
    /// - Returns: ConnectionToken proving connection is ready
    /// - Throws: URLError if connection fails or times out
    public func establishConnection(jobId: String) async throws -> ConnectionToken {
        guard webSocketTask == nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket already connected"])
        }

        // Create connection endpoint with client-provided jobId
        guard let url = URL(string: "\(baseURL)/ws/progress?jobId=\(jobId)") else {
            throw URLError(.badURL)
        }

        // Create URLSession with WebSocket configuration
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Start connection
        task.resume()

        // Wait for successful connection (by sending/receiving ping)
        try await waitForConnection(task, timeout: connectionTimeout)

        self.webSocketTask = task
        self.isConnected = true

        print("🔌 WebSocket established (ready for job configuration)")

        // Start receiving messages in background
        await startReceiving()

        // Return token proving connection is ready
        let token = ConnectionToken(
            connectionId: UUID().uuidString,
            createdAt: Date()
        )

        return token
    }

    /// STEP 2: Configure established WebSocket for specific job
    /// Called after receiving jobId from server
    ///
    /// - Parameter jobId: Job identifier from POST /scan response
    /// - Throws: URLError if jobId is invalid or connection was lost
    public func configureForJob(jobId: String) async throws {
        guard webSocketTask != nil else {
            throw URLError(.badURL, userInfo: ["reason": "WebSocket not connected. Call establishConnection() first"])
        }

        guard !jobId.isEmpty else {
            throw URLError(.badURL, userInfo: ["reason": "Invalid jobId"])
        }

        self.boundJobId = jobId

        print("🔌 WebSocket configured for job: \(jobId)")

        // Signal to server that WebSocket is ready
        // This tells server it's safe to start processing
        try await signalWebSocketReady(jobId: jobId)
    }

    /// Set progress handler for already-connected WebSocket
    /// Use this after calling establishConnection() + configureForJob()
    ///
    /// - Parameter handler: Callback for progress updates (called on MainActor)
    public func setProgressHandler(_ handler: @escaping (JobProgress) -> Void) {
        self.progressHandler = handler
    }

    /// Connect to WebSocket for a specific job (backward compatible)
    /// This is now equivalent to: establishConnection(jobId) + configureForJob(jobId)
    ///
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - progressHandler: Callback for progress updates (called on MainActor)
    public func connect(
        jobId: String,
        progressHandler: @escaping (JobProgress) -> Void
    ) async {
        do {
            // Use new two-step protocol with client-generated jobId
            _ = try await establishConnection(jobId: jobId)
            try await configureForJob(jobId: jobId)

            // Set progress handler after connection is fully configured
            self.progressHandler = progressHandler
        } catch {
            self.lastError = error
            print("❌ Failed to connect: \(error)")
        }
    }

    /// Disconnect WebSocket
    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        progressHandler = nil
        boundJobId = nil

        print("🔌 WebSocket disconnected")
    }

    // MARK: - Private Methods

    /// Wait for WebSocket connection to be established
    /// Uses exponential backoff to verify connection is working
    private func waitForConnection(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws {
        let startTime = Date()

        // Try a few ping/pong cycles to confirm connection
        var attempts = 0
        let maxAttempts = 5

        while attempts < maxAttempts {
            if Date().timeIntervalSince(startTime) > timeout {
                throw URLError(.timedOut)
            }

            do {
                // Send ping message to confirm connection is working
                try await task.send(.string("PING"))

                // Wait for any response (with timeout)
                _ = Task {
                    try await task.receive()
                }

                try await Task.sleep(for: .milliseconds(100 * (attempts + 1)))

                attempts += 1
            } catch {
                throw error
            }
        }

        print("✅ WebSocket connection verified after \(attempts) attempts")
    }

    /// Signal to server that WebSocket is ready
    /// Server uses this to know it's safe to start processing
    private func signalWebSocketReady(jobId: String) async throws {
        let readyURL = URL(string: "\(readySignalEndpoint)/scan/ready/\(jobId)")!

        var request = URLRequest(url: readyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5.0

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse, userInfo: ["statusCode": httpResponse.statusCode])
        }

        print("✅ Server notified WebSocket ready for job: \(jobId)")
    }

    /// Start receiving WebSocket messages
    private func startReceiving() async {
        receiveTask = Task { @MainActor in
            while !Task.isCancelled, let webSocketTask = webSocketTask {
                do {
                    let message = try await webSocketTask.receive()
                    await handleMessage(message)
                } catch {
                    print("⚠️ WebSocket receive error: \(error)")
                    self.lastError = error
                    self.disconnect()
                    break
                }
            }
        }
    }

    /// Handle incoming WebSocket message
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            // Skip PING/PONG messages used for connection verification
            if text != "PING" && text != "PONG" {
                await parseProgressUpdate(text)
            }

        case .data(let data):
            if let text = String(data: data, encoding: .utf8),
               text != "PING" && text != "PONG" {
                await parseProgressUpdate(text)
            }

        @unknown default:
            print("⚠️ Unknown WebSocket message type")
        }
    }

    /// Parse JSON progress update
    private func parseProgressUpdate(_ json: String) async {
        guard let data = json.data(using: .utf8) else { return }

        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(WebSocketMessage.self, from: data)

            // Convert to JobProgress, preserving keepAlive flag
            let progress = JobProgress(
                totalItems: message.data.totalItems,
                processedItems: message.data.processedItems,
                currentStatus: message.data.currentStatus,
                keepAlive: message.data.keepAlive  // Pass through keepAlive flag
            )

            // Call progress handler on MainActor
            await MainActor.run {
                progressHandler?(progress)
            }

        } catch {
            print("⚠️ Failed to parse progress update: \(error)")
        }
    }
}

// MARK: - Message Models

/// WebSocket message structure (matches backend)
struct WebSocketMessage: Codable, Sendable {
    let type: String
    let jobId: String
    let timestamp: Int64
    let data: ProgressData
}

struct ProgressData: Codable, Sendable {
    let progress: Double
    let processedItems: Int
    let totalItems: Int
    let currentStatus: String
    let currentWorkId: String?
    let error: String?
    let keepAlive: Bool?  // Optional: true for keep-alive pings, nil for normal updates
}
