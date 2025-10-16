//
//  JobModels.swift
//  BooksTracker
//
//  Created by Jules on 10/16/25.
//

import Foundation

// MARK: - Job Identifier
public struct JobIdentifier: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let jobType: String
    public let createdDate: Date

    public init(jobType: String) {
        self.id = UUID()
        self.jobType = jobType
        self.createdDate = Date()
    }
}

// MARK: - Job Status
public enum JobStatus: Codable, Sendable, Equatable {
    case queued
    case active(progress: JobProgress)
    case completed(log: [String])
    case failed(error: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .active:
            return false
        }
    }
}

// MARK: - Job Progress
public struct JobProgress: Codable, Sendable, Equatable {
    public var totalItems: Int
    public var processedItems: Int
    public var currentStatus: String
    public var estimatedTimeRemaining: TimeInterval?

    public var fractionCompleted: Double {
        guard totalItems > 0 else { return 0 }
        return Double(processedItems) / Double(totalItems)
    }

    public static var zero: JobProgress {
        JobProgress(totalItems: 0, processedItems: 0, currentStatus: "Starting...")
    }
}