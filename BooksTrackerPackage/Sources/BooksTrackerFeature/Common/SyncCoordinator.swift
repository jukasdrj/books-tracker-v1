import Foundation
import SwiftData
import SwiftUI

/// Orchestrates multi-step background jobs (CSV import, enrichment)
/// Uses PollingUtility for backend polling and JobModels for type-safe tracking
@MainActor
public final class SyncCoordinator: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var activeJobId: JobIdentifier?
    @Published public private(set) var jobStatus: [JobIdentifier: JobStatus] = [:]

    // MARK: - Singleton

    public static let shared = SyncCoordinator()

    // MARK: - Initialization

    private init() {
        // Private initializer for singleton pattern
    }

    // MARK: - Public Methods

    /// Get current status for a job
    public func getJobStatus(for jobId: JobIdentifier) -> JobStatus? {
        return jobStatus[jobId]
    }

    /// Cancel an active job
    public func cancelJob(_ jobId: JobIdentifier) {
        jobStatus[jobId] = .cancelled
        if activeJobId == jobId {
            activeJobId = nil
        }
    }
}
