import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("SyncCoordinator Tests")
@MainActor
struct SyncCoordinatorTests {

    // MARK: - Initialization Tests

    @Test("SyncCoordinator is a singleton")
    func coordinatorSingleton() {
        let instance1 = SyncCoordinator.shared
        let instance2 = SyncCoordinator.shared

        #expect(instance1 === instance2)
    }

    @Test("SyncCoordinator starts with no active jobs")
    func initialState() {
        let coordinator = SyncCoordinator.shared
        #expect(coordinator.activeJobId == nil)
        #expect(coordinator.jobStatus.isEmpty)
    }

    // MARK: - Job Status Tests

    @Test("Can retrieve job status by identifier")
    func getJobStatus() {
        let coordinator = SyncCoordinator.shared
        let jobId = JobIdentifier(jobType: "test_job")

        // Initially nil
        #expect(coordinator.getJobStatus(for: jobId) == nil)

        // Set status
        coordinator.jobStatus[jobId] = .queued

        // Retrieve status
        let status = coordinator.getJobStatus(for: jobId)
        #expect(status == .queued)
    }

    @Test("Can cancel an active job")
    func cancelJob() {
        let coordinator = SyncCoordinator.shared
        let jobId = JobIdentifier(jobType: "test_job")

        // Set as active with progress
        coordinator.activeJobId = jobId
        coordinator.jobStatus[jobId] = .active(progress: .zero)

        // Cancel
        coordinator.cancelJob(jobId)

        // Verify cancelled
        #expect(coordinator.jobStatus[jobId] == .cancelled)
        #expect(coordinator.activeJobId == nil)
    }

    @Test("Cancelling non-active job doesn't clear activeJobId")
    func cancelNonActiveJob() {
        let coordinator = SyncCoordinator.shared
        let activeJobId = JobIdentifier(jobType: "active_job")
        let otherJobId = JobIdentifier(jobType: "other_job")

        // Set active job
        coordinator.activeJobId = activeJobId
        coordinator.jobStatus[activeJobId] = .active(progress: .zero)
        coordinator.jobStatus[otherJobId] = .active(progress: .zero)

        // Cancel the non-active job
        coordinator.cancelJob(otherJobId)

        // Verify active job still active
        #expect(coordinator.activeJobId == activeJobId)
        #expect(coordinator.jobStatus[otherJobId] == .cancelled)
    }

    // MARK: - JobProgress Tests

    @Test("JobProgress calculates fraction completed correctly")
    func progressFraction() {
        var progress = JobProgress(
            totalItems: 100,
            processedItems: 25,
            currentStatus: "Processing..."
        )

        #expect(progress.fractionCompleted == 0.25)

        progress.processedItems = 50
        #expect(progress.fractionCompleted == 0.50)

        progress.processedItems = 100
        #expect(progress.fractionCompleted == 1.0)
    }

    @Test("JobProgress handles zero total items")
    func progressFractionZeroItems() {
        let progress = JobProgress(
            totalItems: 0,
            processedItems: 0,
            currentStatus: "Starting..."
        )

        #expect(progress.fractionCompleted == 0.0)
    }

    @Test("JobProgress.zero factory method")
    func progressZeroFactory() {
        let progress = JobProgress.zero

        #expect(progress.totalItems == 0)
        #expect(progress.processedItems == 0)
        #expect(progress.currentStatus == "Starting...")
        #expect(progress.estimatedTimeRemaining == nil)
    }

    // MARK: - JobStatus Tests

    @Test("JobStatus terminal state detection")
    func terminalStates() {
        #expect(JobStatus.completed(log: []).isTerminal == true)
        #expect(JobStatus.failed(error: "test").isTerminal == true)
        #expect(JobStatus.cancelled.isTerminal == true)

        #expect(JobStatus.queued.isTerminal == false)
        #expect(JobStatus.active(progress: .zero).isTerminal == false)
    }

    // MARK: - JobIdentifier Tests

    @Test("JobIdentifier has unique IDs")
    func jobIdentifierUniqueness() {
        let job1 = JobIdentifier(jobType: "import")
        let job2 = JobIdentifier(jobType: "import")

        #expect(job1.id != job2.id)
        #expect(job1.jobType == job2.jobType)
    }

    @Test("JobIdentifier conforms to Identifiable")
    func jobIdentifierIdentifiable() {
        let jobId = JobIdentifier(jobType: "test")

        // Verify Identifiable.id matches the id property
        #expect(jobId.id == jobId.id)
    }

    @Test("JobIdentifier is Hashable")
    func jobIdentifierHashable() {
        let job1 = JobIdentifier(jobType: "import")
        let job2 = JobIdentifier(jobType: "import")

        var set = Set<JobIdentifier>()
        set.insert(job1)
        set.insert(job2)

        // Different IDs = both in set
        #expect(set.count == 2)
    }
}
