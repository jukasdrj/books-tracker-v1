# Swift Concurrency Guide

This document outlines best practices for using Swift's modern concurrency features, particularly `AsyncStream`, within the BooksTracker codebase. Following these patterns ensures our app is robust, efficient, and compliant with Swift 6's strict concurrency checks.

## `AsyncStream` Usage

`AsyncStream` is a powerful tool for bridging non-async code into the async world. There are two primary patterns for its use in this project.

### 1. Polling with `Task` and `Task.sleep`

When you need to create a stream from a process that requires periodic checking (polling), the standard is to use a detached `Task` that loops and sleeps. This is more efficient and safer than using older patterns like `Timer.publish`.

**✅ Correct Pattern:**

```swift
func createPollingStream() -> AsyncStream<MyType> {
    AsyncStream { continuation in
        Task {
            while !Task.isCancelled {
                // 1. Fetch the data
                let result = await fetchData()
                continuation.yield(result)

                // 2. Wait before the next poll
                try await Task.sleep(for: .seconds(1))
            }
        }

        continuation.onTermination = { @Sendable _ in
            // Clean up resources here
        }
    }
}
```

**Canonical Example:** `BookshelfAIService.swift`

The `animateProgressWithPolling` function in `BookshelfAIService` is the project's reference implementation for this pattern. It demonstrates how to create a cancellable, polling async task that drives progress updates.

### 2. Bridging Delegate-Based APIs

When wrapping an API that uses the delegate pattern (like `AVFoundation`), `AsyncStream` provides a clean way to convert delegate callbacks into a stream.

**✅ Correct Pattern:**

```swift
@SomeActor
class DelegateBasedService {
    private var streamContinuation: AsyncStream<DataType>.Continuation?

    func startStreaming() -> AsyncStream<DataType> {
        AsyncStream { continuation in
            self.streamContinuation = continuation

            // Setup the underlying delegate-based API here
            // e.g., cameraManager.setDelegate(self)

            continuation.onTermination = { @Sendable _ in
                // Stop the underlying API and clean up
            }
        }
    }

    // This is the delegate callback method
    func underlyingApi(_ api: SomeApi, didProduceData data: DataType) {
        // Yield the new data to the stream
        streamContinuation?.yield(data)
    }
}
```

**Canonical Example:** `BarcodeDetectionService.swift`

This service correctly uses an `AsyncStream` to provide a stream of barcodes detected by `AVFoundation` and `Vision`, which are delegate-driven frameworks. The service acts as the delegate and yields results to the stream's continuation.

**❌ Anti-Patterns to Avoid:**

*   **`Timer.publish`:** Do not use `Timer.publish` with `TaskGroup` or other async contexts. It can lead to unexpected behavior and subtle bugs, especially with actor isolation. Always prefer the `Task` + `Task.sleep` pattern.
*   **Blocking Calls in Streams:** Never block inside an `AsyncStream`'s continuation. All work should be non-blocking or performed in a separate `Task`.