import Foundation

/// Manages WebSocket connections for real-time progress updates
/// Replaces polling-based progress tracking with server push notifications
@MainActor
public final class WebSocketProgressManager: ObservableObject {

    // MARK: - Properties

    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastError: Error?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var progressHandler: ((JobProgress) -> Void)?

    // Backend configuration
    private let baseURL = "wss://books-api-proxy.jukasdrj.workers.dev"

    // MARK: - Public Methods

    public init() {}

    /// Connect to WebSocket for a specific job
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - progressHandler: Callback for progress updates (called on MainActor)
    public func connect(
        jobId: String,
        progressHandler: @escaping (JobProgress) -> Void
    ) async {
        guard webSocketTask == nil else {
            print("⚠️ WebSocket already connected")
            return
        }

        // Validate jobId
        guard !jobId.isEmpty else {
            self.lastError = URLError(.badURL)
            return
        }

        self.progressHandler = progressHandler

        // Construct WebSocket URL
        guard let url = URL(string: "\(baseURL)/ws/progress?jobId=\(jobId)") else {
            self.lastError = URLError(.badURL)
            return
        }

        // Create URLSession with WebSocket configuration
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)

        // Start connection
        webSocketTask?.resume()
        isConnected = true

        print("🔌 WebSocket connected for job: \(jobId)")

        // Start receiving messages
        await startReceiving()
    }

    /// Disconnect WebSocket
    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        isConnected = false
        progressHandler = nil

        print("🔌 WebSocket disconnected")
    }

    // MARK: - Private Methods

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
            await parseProgressUpdate(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
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

            // Convert to JobProgress
            let progress = JobProgress(
                totalItems: message.data.totalItems,
                processedItems: message.data.processedItems,
                currentStatus: message.data.currentStatus
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
}
