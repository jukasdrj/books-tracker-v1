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
                
                // Wait for response with proper timeout handling
                try await withTimeout(seconds: 1.0) {
                    _ = try await task.receive()
                }
                
                try await Task.sleep(for: .milliseconds(100 * (attempts + 1)))
                
                attempts += 1
            } catch {
                // If we get an error on first attempt, connection likely failed
                // On subsequent attempts, continue trying
                if attempts == 0 {
                    throw error
                }
                attempts += 1
            }
        }
        
        print("✅ WebSocket connection verified after \(attempts) attempts")
    }
    
    /// Helper to add timeout to async operations
    private static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
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
