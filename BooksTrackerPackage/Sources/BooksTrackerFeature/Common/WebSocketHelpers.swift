import Foundation

/// Shared utilities for WebSocket connection management
/// Provides race-condition-free connection establishment patterns
enum WebSocketHelpers {
    
    /// Wait for WebSocket connection to be established before allowing send/receive operations
    /// Prevents POSIX error 57 "Socket is not connected" by verifying the handshake completed
    ///
    /// **Critical:** URLSessionWebSocketTask.resume() is non-blocking - it initiates the handshake
    /// asynchronously but returns immediately. This function ensures the connection is ready.
    ///
    /// - Parameters:
    ///   - task: The WebSocket task to verify (must have had resume() called)
    ///   - timeout: Maximum time to wait for connection (default: 10 seconds)
    /// - Throws: URLError.timedOut if connection not established within timeout
    ///
    /// - Note: Uses ping/receive cycles with exponential backoff to verify connection
    static func waitForConnection(
        _ task: URLSessionWebSocketTask,
        timeout: TimeInterval = 10.0
    ) async throws {
        let startTime = Date()

        // Try a few ping/pong cycles to confirm connection
        let maxAttempts = 5
        var attempts = 0
        var lastError: Error?

        #if DEBUG
        print("🔍 [WS_HELPERS] Starting connection verification (timeout: \(timeout)s, max attempts: \(maxAttempts))")
        #endif

        while attempts < maxAttempts {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeout {
                #if DEBUG
                print("❌ [WS_HELPERS] Timeout after \(elapsed)s (limit: \(timeout)s)")
                #endif
                throw URLError(.timedOut)
            }

            #if DEBUG
            print("📍 [WS_HELPERS] Ping attempt \(attempts + 1)/\(maxAttempts) (elapsed: \(String(format: "%.1f", elapsed))s)")
            #endif

            do {
                // Use URLSessionWebSocketTask's native ping mechanism
                // This sends a WebSocket PING frame (not a string message)
                // The server automatically responds with a PONG frame
                try await withTimeout(seconds: 2.0) {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        task.sendPing { error in
                            if let error = error {
                                #if DEBUG
                                print("❌ [WS_HELPERS] Ping failed: \(error.localizedDescription)")
                                #endif
                                continuation.resume(throwing: error)
                            } else {
                                #if DEBUG
                                print("✅ [WS_HELPERS] Ping successful (server responded)")
                                #endif
                                continuation.resume(returning: ())
                            }
                        }
                    }
                }

                // Success! Connection is established and server responded to ping
                #if DEBUG
                print("✅ [WS_HELPERS] Connection verified after \(attempts + 1) attempts in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
                #endif
                return

            } catch {
                lastError = error
                attempts += 1

                #if DEBUG
                print("⚠️ [WS_HELPERS] Ping attempt \(attempts) failed: \(error.localizedDescription)")
                #endif

                // If we've exhausted all attempts, throw the last error
                if attempts >= maxAttempts {
                    #if DEBUG
                    print("❌ [WS_HELPERS] All \(maxAttempts) ping attempts failed, giving up")
                    #endif
                    throw lastError ?? URLError(.cannotConnectToHost)
                }

                // Wait before retrying (exponential backoff)
                let backoffMs = 100 * attempts
                #if DEBUG
                print("⏳ [WS_HELPERS] Waiting \(backoffMs)ms before retry...")
                #endif
                try await Task.sleep(for: .milliseconds(backoffMs))
            }
        }
    }
    
    /// Helper to add timeout to async operations
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }

            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }

            group.cancelAll()
            return result
        }
    }
}
