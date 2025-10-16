import Foundation

/// A generic polling status.
enum PollStatus<Success, Metadata> {
    case inProgress(progress: Double, metadata: Metadata)
    case complete(Success)
    case error(Error)
}

/// A collection of top-level utility functions.
enum Utility {

    /// Polls an async closure until it returns a `.complete` or `.error` status, or a timeout is reached.
    ///
    /// This function is useful for waiting on long-running, asynchronous operations
    /// that provide completion status via a separate check. It uses a `Task`-based
    /// loop with `Task.sleep` for efficient, cancellable waiting.
    ///
    /// The pattern is based on the successful implementation from `BookshelfAIService`
    /// and is designed to be a standardized polling mechanism across the app.
    ///
    /// - Parameters:
    ///   - check: An async closure that returns a `PollStatus` enum.
    ///   - progressHandler: A closure that is called on the main actor with the progress
    ///     and metadata from the `check` closure.
    ///   - interval: The `Duration` to wait between each poll. Defaults to 100ms.
    ///   - timeout: The maximum `Duration` to wait before throwing a `TimeoutError`.
    ///     Defaults to 90 seconds.
    /// - Returns: The success value from the `.complete` status.
    /// - Throws: A `TimeoutError` if the timeout is reached, or any error from the `.error` status.
    nonisolated static func pollForCompletion<Success, Metadata>(
        check: @escaping () async throws -> PollStatus<Success, Metadata>,
        progressHandler: @MainActor @escaping (Double, Metadata) -> Void,
        interval: Duration = .milliseconds(100),
        timeout: Duration = .seconds(90)
    ) async throws -> Success {
        let startTime = Date()
        let timeoutSeconds = timeout.inSeconds

        return try await withTaskCancellationHandler {
            try await Task<Success, Error> {
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(startTime)

                    // Check for timeout
                    if elapsed > timeoutSeconds {
                        throw TimeoutError()
                    }

                    // Perform the check
                    switch try await check() {
                    case .inProgress(let progress, let metadata):
                        await MainActor.run {
                            progressHandler(progress, metadata)
                        }
                    case .complete(let result):
                        return result
                    case .error(let error):
                        throw error
                    }

                    // Wait for the next interval
                    try await Task.sleep(for: interval)
                }

                throw CancellationError()
            }.value
        } onCancel: {
            // The task will check isCancelled and exit cleanly.
        }
    }
}

/// A simple error to indicate a timeout.
struct TimeoutError: Error, LocalizedError {
    var errorDescription: String? = "The operation timed out."
}

extension Duration {
    /// Converts a `Duration` to a `TimeInterval` in seconds.
    var inSeconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}