import Foundation
import SwiftUI

/// A robust WebSocket client that handles automatic reconnection, heartbeat, and app lifecycle events.
@MainActor
final class RobustWebSocketClient {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    private var webSocket: URLSessionWebSocketTask?
    private var connectionState: ConnectionState = .disconnected
    private var reconnectTimer: Timer?
    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0

    private let url: URL
    private let onMessage: (String) -> Void
    private let onError: (Error) -> Void
    private let onConnectionStateChange: (ConnectionState) -> Void

    init(
        url: URL,
        onMessage: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        onConnectionStateChange: @escaping (ConnectionState) -> Void
    ) {
        self.url = url
        self.onMessage = onMessage
        self.onError = onError
        self.onConnectionStateChange = onConnectionStateChange

        observeAppLifecycle()
    }

    // MARK: - Public API

    func connect() {
        guard connectionState == .disconnected else { return }
        connectionState = .connecting
        onConnectionStateChange(connectionState)

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        Task {
            do {
                if let webSocket = webSocket {
                    try await WebSocketHelpers.waitForConnection(webSocket, timeout: 10.0)
                    connectionState = .connected
                    onConnectionStateChange(connectionState)
                    reconnectAttempts = 0
                    startHeartbeat()
                    listenForMessages()
                }
            } catch {
                handleConnectionError(error)
            }
        }
    }

    func disconnect() {
        connectionState = .disconnected
        onConnectionStateChange(connectionState)

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        stopHeartbeat()
        stopReconnectTimer()
    }

    func sendMessage(_ message: String) {
        guard connectionState == .connected else { return }
        webSocket?.send(.string(message)) { [weak self] error in
            if let error = error {
                self?.onError(error)
            }
        }
    }

    // MARK: - Private Methods

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.listenForMessages()
                case .failure(let error):
                    self.handleConnectionError(error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            onMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                onMessage(text)
            }
        case .pong:
            // Heartbeat pong received
            break
        @unknown default:
            break
        }
    }

    private func handleConnectionError(_ error: Error) {
        onError(error)
        disconnect()
        scheduleReconnect()
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendPing() {
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                self?.handleConnectionError(error)
            }
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        let backoff = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        reconnectAttempts += 1

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: backoff, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIScene.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIScene.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appWillEnterForeground() {
        connect()
    }

    @objc private func appDidEnterBackground() {
        disconnect()
    }
}
