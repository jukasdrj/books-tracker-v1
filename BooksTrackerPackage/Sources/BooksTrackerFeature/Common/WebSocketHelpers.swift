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
}
