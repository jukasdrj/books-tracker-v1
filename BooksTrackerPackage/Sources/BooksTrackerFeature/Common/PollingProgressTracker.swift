import Foundation
import SwiftUI
import UIKit

// MARK: - Error Types

/// Errors that can occur during polling operations
public enum PollingError: LocalizedError, Equatable {
    case cancelled
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return NSLocalizedString(
                "polling.error.cancelled",
                value: "Operation was cancelled",
                comment: "Shown when user cancels a polling operation"
            )
        case .timedOut:
            return NSLocalizedString(
                "polling.error.timeout",
                value: "Operation timed out",
                comment: "Shown when a polling operation exceeds timeout"
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cancelled:
            return nil
        case .timedOut:
            return NSLocalizedString(
                "polling.error.timeout.suggestion",
                value: "Check your internet connection and try again",
                comment: "Recovery suggestion for timeout"
            )
        }
    }
}

// MARK: - Core Protocols

/// Status of a pollable job at a specific moment
public enum PollStatus<Success: Sendable, Metadata: Sendable> {
    /// Job is still running with current progress
    case inProgress(stage: String, progress: Double, metadata: Metadata)
    /// Job completed successfully
    case complete(Success)
}

/// A job that can be polled for progress and completion status
public protocol PollableJob: Sendable {
    associatedtype Success: Sendable
    associatedtype Metadata: Sendable

    /// Poll the job for current status
    func poll() async throws -> PollStatus<Success, Metadata>

    /// Cancel the job (called when user cancels)
    func cancel() async
}

/// Strategy for determining when to poll a job
public protocol PollingStrategy: Sendable {
    /// Decide if polling should occur now
    func shouldPoll(elapsedTime: TimeInterval, lastPollTime: TimeInterval, currentStage: String) -> Bool
}

// MARK: - Adaptive Polling Strategy

/// Adaptive polling strategy that starts fast and slows down over time
/// iOS 26 best practice: prevents battery drain on long operations
public struct AdaptivePollingStrategy: PollingStrategy {
    private let initialInterval: TimeInterval
    private let maxInterval: TimeInterval

    /// Create adaptive strategy
    /// - Parameters:
    ///   - initialInterval: Starting poll interval (fast for responsiveness)
    ///   - maxInterval: Maximum poll interval (slow to save battery)
    public init(
        initialInterval: TimeInterval = 0.5,
        maxInterval: TimeInterval = 2.0
    ) {
        self.initialInterval = initialInterval
        self.maxInterval = maxInterval
    }

    public func shouldPoll(
        elapsedTime: TimeInterval,
        lastPollTime: TimeInterval,
        currentStage: String
    ) -> Bool {
        guard lastPollTime >= 0 else { return true } // First poll

        let timeSinceLastPoll = elapsedTime - lastPollTime

        // Adaptive: start fast, slow down over time
        // +0.1s interval per 1s elapsed
        let targetInterval = min(
            maxInterval,
            initialInterval + (elapsedTime / 10.0)
        )

        return timeSinceLastPoll >= targetInterval
    }
}

/// Stage-based polling strategy with custom intervals per stage
public struct StageBasedPollingStrategy: PollingStrategy {
    private let intervals: [String: TimeInterval]
    private let defaultInterval: TimeInterval

    /// Create stage-based strategy
    /// - Parameters:
    ///   - intervals: Dictionary mapping stage names to poll intervals
    ///   - defaultInterval: Fallback interval for unknown stages
    public init(
        intervals: [String: TimeInterval],
        defaultInterval: TimeInterval = 1.0
    ) {
        self.intervals = intervals
        self.defaultInterval = defaultInterval
    }

    public func shouldPoll(
        elapsedTime: TimeInterval,
        lastPollTime: TimeInterval,
        currentStage: String
    ) -> Bool {
        guard lastPollTime >= 0 else { return true }

        let interval = intervals[currentStage] ?? defaultInterval
        return (elapsedTime - lastPollTime) >= interval
    }
}

// MARK: - Polling Progress Tracker

/// Generic polling progress tracker for long-running async operations
///
/// **Swift 6.2 Pattern:**
/// - Uses Task.detached for background polling (not main thread!)
/// - MainActor isolation only for UI state updates
/// - Strategic polling via PollingStrategy protocol
/// - Proper cancellation with withTaskCancellationHandler
///
/// **iOS 26 HIG Compliance:**
/// - VoiceOver announcements for accessibility
/// - Haptic feedback for stage changes
/// - Progress clamping (always 0.0-1.0)
/// - LocalizedError for user-facing messages
///
/// **Example Usage:**
/// ```swift
/// @State private var tracker = PollingProgressTracker<BookshelfScanJob>()
///
/// let result = try await tracker.start(
///     job: BookshelfScanJob(jobId: "123"),
///     strategy: AdaptivePollingStrategy(),
///     timeout: 90
/// )
/// ```
@MainActor
@Observable
public final class PollingProgressTracker<Job: PollableJob> {

    // MARK: - Public State

    /// Current stage name (e.g., "Analyzing image")
    public private(set) var stage: String = "Starting..."

    /// Progress from 0.0 to 1.0 (always clamped)
    public private(set) var progress: Double = 0.0

    /// Elapsed time in seconds
    public private(set) var elapsedTime: Int = 0

    /// Job-specific metadata
    public private(set) var metadata: Job.Metadata?

    // MARK: - Configuration

    /// Enable VoiceOver announcements (default: true)
    public var shouldAnnounceProgress: Bool = true

    /// Enable haptic feedback on stage changes (default: true)
    public var providesHapticFeedback: Bool = true

    // MARK: - Private State

    private var pollingTask: Task<Job.Success, Error>?
    private var lastAnnouncedProgress: Double = 0.0

    public init() {}

    // MARK: - Public API

    /// Start polling the job and return final result
    ///
    /// **Concurrency Model:**
    /// - Spawns detached Task for background polling loop
    /// - Only UI updates touch @MainActor
    /// - Allows job.poll() to run off main thread
    ///
    /// - Parameters:
    ///   - job: PollableJob instance to track
    ///   - strategy: PollingStrategy for timing (default: adaptive)
    ///   - timeout: Max wait time before throwing .timedOut
    ///   - pollInterval: Sleep duration between loop iterations
    /// - Returns: Successful result when job completes
    /// - Throws: PollingError.timedOut, .cancelled, or job-specific errors
    public func start(
        job: Job,
        strategy: PollingStrategy = AdaptivePollingStrategy(),
        timeout: TimeInterval,
        pollInterval: Duration = .milliseconds(100)
    ) async throws -> Job.Success {
        resetState()
        let startTime = Date()

        // ✅ Swift 6.2 Pattern: Task.detached for background work
        let task = Task.detached {
            var lastPollTime: TimeInterval = -1

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)

                // Update elapsed time on MainActor
                await MainActor.run {
                    self.elapsedTime = Int(elapsed)
                }

                // Check timeout
                if elapsed > timeout {
                    throw PollingError.timedOut
                }

                // Strategic polling via strategy protocol
                if strategy.shouldPoll(
                    elapsedTime: elapsed,
                    lastPollTime: lastPollTime,
                    currentStage: await MainActor.run { self.stage }
                ) {
                    lastPollTime = elapsed

                    // Poll runs in background context (not main thread!)
                    switch try await job.poll() {
                    case .inProgress(let newStage, let newProgress, let newMetadata):
                        // UI updates hop to MainActor
                        await MainActor.run {
                            self.updateStage(newStage)
                            self.updateProgress(newProgress)
                            self.metadata = newMetadata
                        }
                    case .complete(let success):
                        // Final haptic feedback
                        await MainActor.run {
                            if self.providesHapticFeedback {
                                UINotificationFeedbackGenerator()
                                    .notificationOccurred(.success)
                            }
                        }
                        return success
                    }
                }

                // Sleep to yield thread and control loop speed
                try await Task.sleep(for: pollInterval)
            }

            // Loop exited due to cancellation
            throw PollingError.cancelled
        }

        self.pollingTask = task

        // Structured concurrency with cancellation handling
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            // Ensure job cancellation completes
            Task { @MainActor in
                await job.cancel()
            }
        }
    }

    /// Cancel the polling operation
    public func cancel() {
        pollingTask?.cancel()
    }

    // MARK: - Private Methods

    private func resetState() {
        self.stage = "Starting..."
        self.progress = 0.0
        self.elapsedTime = 0
        self.metadata = nil
        self.pollingTask = nil
        self.lastAnnouncedProgress = 0.0
    }

    /// Update stage with VoiceOver and haptic feedback
    private func updateStage(_ newStage: String) {
        if self.stage != newStage {
            self.stage = newStage
            self.lastAnnouncedProgress = 0.0

            // iOS 26 HIG: Announce stage changes for accessibility
            if shouldAnnounceProgress {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: newStage
                )
            }

            // iOS 26 HIG: Haptic feedback for state changes
            if providesHapticFeedback {
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
            }
        }
    }

    /// Update progress with clamping and milestone announcements
    private func updateProgress(_ newProgress: Double) {
        // ✅ iOS 26 HIG: Always clamp progress to valid range
        let clampedProgress = min(1.0, max(0.0, newProgress))
        self.progress = clampedProgress

        // Announce every 25% milestone for accessibility
        if shouldAnnounceProgress {
            let milestone = floor(clampedProgress * 4) * 0.25
            if milestone > lastAnnouncedProgress {
                let percentage = Int(milestone * 100)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "\(stage): \(percentage)% complete"
                )
                lastAnnouncedProgress = milestone
            }
        }
    }
}

// MARK: - SwiftUI Integration

extension View {
    /// Display polling progress in iOS 26 Liquid Glass sheet
    ///
    /// **Usage:**
    /// ```swift
    /// .pollingProgressSheet(
    ///     isPresented: $isScanning,
    ///     tracker: scanTracker,
    ///     title: "Scanning Bookshelf"
    /// )
    /// ```
    public func pollingProgressSheet<Job: PollableJob>(
        isPresented: Binding<Bool>,
        tracker: PollingProgressTracker<Job>,
        title: String,
        cancelTitle: String = "Cancel"
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            PollingProgressView(
                tracker: tracker,
                title: title,
                cancelTitle: cancelTitle,
                onCancel: {
                    tracker.cancel()
                    isPresented.wrappedValue = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Reusable iOS 26 Liquid Glass progress view
private struct PollingProgressView<Job: PollableJob>: View {
    let tracker: PollingProgressTracker<Job>
    let title: String
    let cancelTitle: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.title2.bold())

            ProgressView(value: tracker.progress) {
                Text(tracker.stage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)

            // iOS 26 HIG: Use monospaced digits for timers
            Text("\(tracker.elapsedTime)s elapsed")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button(cancelTitle, role: .cancel) {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.regularMaterial)  // iOS 26 Liquid Glass
    }
}
