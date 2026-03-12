//
//  PersistenceTypes.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

enum TranscriptionStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case inProgress
    case completed
    case failed
}

struct ProcessingMetadata: Codable, Sendable {
    let attemptNumber: Int
    let processingDuration: TimeInterval
    let modelVersion: String?
    let language: String?

    init(
        attemptNumber: Int,
        processingDuration: TimeInterval,
        modelVersion: String? = nil,
        language: String? = nil
    ) {
        self.attemptNumber = attemptNumber
        self.processingDuration = processingDuration
        self.modelVersion = modelVersion
        self.language = language
    }
}

struct RecordingSessionDTO: Sendable {
    let id: UUID
    let createdDate: Date
    let sessionName: String
    let totalDuration: TimeInterval
    let segmentCount: Int
}

struct SegmentDTO: Sendable {
    let id: UUID
    let sessionID: UUID
    let startTime: Date
    let duration: TimeInterval
    let audioFileURL: URL
    let transcriptionStatus: TranscriptionStatus
    let transcriptionErrorDescription: String?
}

struct TranscriptionDTO: Sendable {
    let id: UUID
    let segmentID: UUID
    let text: String
    let processingMetadata: ProcessingMetadata
    let createdAt: Date
}

struct SegmentSaveRequest: Sendable {
    let id: UUID
    let sessionID: UUID
    let startTime: Date
    let duration: TimeInterval
    let audioFileURL: URL
}

enum PersistenceError: Error, Sendable {
    case sessionNotFound(UUID)
    case segmentNotFound(UUID)
    case duplicateID(UUID)
}
