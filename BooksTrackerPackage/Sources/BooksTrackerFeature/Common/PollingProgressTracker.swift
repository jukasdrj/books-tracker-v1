//
//  PollingProgressTracker.swift
//  BooksTracker
//
//  Created by Jules on 10/16/25.
//

import Foundation
import SwiftUI

@MainActor
public class PollingProgressTracker: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var jobStatus: [JobIdentifier: JobStatus] = [:]

    // MARK: - Public Properties

    public static let shared = PollingProgressTracker()

    // MARK: - Private Properties

    private var timer: Timer?
    private let pollingInterval: TimeInterval

    // MARK: - Initialization

    private init(pollingInterval: TimeInterval = 1.0) {
        self.pollingInterval = pollingInterval
    }

    // MARK: - Public Methods

    public func startJob(jobId: JobIdentifier, totalItems: Int) {
        let progress = JobProgress(totalItems: totalItems, processedItems: 0, currentStatus: "Starting...")
        jobStatus[jobId] = .active(progress: progress)

        if timer == nil {
            startPolling()
        }
    }

    public func updateProgress(jobId: JobIdentifier, processedItems: Int, statusText: String) {
        guard case var .active(progress) = jobStatus[jobId] else { return }

        progress.processedItems = processedItems
        progress.currentStatus = statusText
        jobStatus[jobId] = .active(progress: progress)
    }

    public func completeJob(jobId: JobIdentifier, log: [String]) {
        jobStatus[jobId] = .completed(log: log)
    }

    public func failJob(jobId: JobIdentifier, error: String) {
        jobStatus[jobId] = .failed(error: error)
    }

    public func cancelJob(jobId: JobIdentifier) {
        jobStatus[jobId] = .cancelled
    }

    public func getStatus(for jobId: JobIdentifier) -> JobStatus? {
        return jobStatus[jobId]
    }

    // MARK: - Private Methods

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}