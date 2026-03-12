//
//  DataManagerActor.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import SwiftData

// MARK: - DataManagerActor

// Single gateway for all SwiftData reads and writes. Declared with @ModelActor so
// it runs on its own serial executor, not @MainActor. All results are returned as
// Sendable DTOs — no @Model objects cross the actor boundary.
// This prevents SwiftData's model-context-ownership rules from being violated.
//
// All methods are implicitly isolated to the actor's executor; callers await each
// call. No additional locking needed.
@ModelActor
actor DataManagerActor {

    // MARK: - Session Operations

    func createRecordingSession(
        id: UUID,
        name: String,
        createdDate: Date = Date()
    ) throws {
        if try sessionExists(id: id) {
            throw PersistenceError.duplicateID(id)
        }
        let session = RecordingSession(
            id: id,
            createdDate: createdDate,
            sessionName: name
        )
        modelContext.insert(session)
        try modelContext.save()
    }

    func updateSessionDuration(_ sessionID: UUID, duration: TimeInterval) throws {
        let session = try requireSession(id: sessionID)
        session.totalDuration = duration
        try modelContext.save()
    }

    func fetchSessions(limit: Int = 50, offset: Int = 0) throws -> [RecordingSessionDTO] {
        var descriptor = FetchDescriptor<RecordingSession>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        descriptor.fetchLimit  = limit
        descriptor.fetchOffset = offset
        descriptor.includePendingChanges = false

        return try modelContext.fetch(descriptor).map(\.dto)
    }

    func fetchSession(id: UUID) throws -> RecordingSessionDTO? {
        try findSession(id: id).map(\.dto)
    }

    func deleteSession(id: UUID) throws {
        let session = try requireSession(id: id)
        modelContext.delete(session)
        try modelContext.save()
    }

    func sessionCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<RecordingSession>())
    }

    // MARK: - Segment Operations

    func saveSegment(_ request: SegmentSaveRequest) throws {
        let session = try requireSession(id: request.sessionID)

        let segment = Segment(
            id: request.id,
            startTime: request.startTime,
            duration: request.duration,
            audioFileURL: request.audioFileURL
        )
        session.segments.append(segment)
        try modelContext.save()
    }

    // Batch-inserts multiple segments in one save() for efficiency.
    func saveSegments(_ requests: [SegmentSaveRequest]) throws {
        guard !requests.isEmpty else { return }

        for request in requests {
            let session = try requireSession(id: request.sessionID)
            let segment = Segment(
                id: request.id,
                startTime: request.startTime,
                duration: request.duration,
                audioFileURL: request.audioFileURL
            )
            session.segments.append(segment)
        }
        try modelContext.save()
    }

    func updateSegmentStatus(
        _ segmentID: UUID,
        status: TranscriptionStatus,
        errorDescription: String? = nil
    ) throws {
        let segment = try requireSegment(id: segmentID)
        segment.transcriptionStatus = status
        segment.transcriptionErrorDescription = errorDescription
        try modelContext.save()
    }

    func fetchSegments(
        for sessionID: UUID,
        status: TranscriptionStatus? = nil
    ) throws -> [SegmentDTO] {
        let descriptor: FetchDescriptor<Segment>

        if let status {
            let rawStatus = status.rawValue
            descriptor = FetchDescriptor<Segment>(
                predicate: #Predicate {
                    $0.session?.id == sessionID
                    && $0.transcriptionStatusRaw == rawStatus
                },
                sortBy: [SortDescriptor(\.startTime)]
            )
        } else {
            descriptor = FetchDescriptor<Segment>(
                predicate: #Predicate { $0.session?.id == sessionID },
                sortBy: [SortDescriptor(\.startTime)]
            )
        }

        return try modelContext.fetch(descriptor).map(\.dto)
    }

    // Returns up to limit pending or failed segments (oldest first).
    // Used on app launch to rehydrate TranscriptionActor's offline queue.
    func fetchPendingSegments(limit: Int = 100) throws -> [SegmentDTO] {
        let pendingRaw  = TranscriptionStatus.pending.rawValue
        let failedRaw   = TranscriptionStatus.failed.rawValue

        var descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate {
                $0.transcriptionStatusRaw == pendingRaw
                || $0.transcriptionStatusRaw == failedRaw
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        descriptor.fetchLimit            = limit
        descriptor.includePendingChanges = false

        return try modelContext.fetch(descriptor).map(\.dto)
    }

    func segmentCount(for sessionID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.session?.id == sessionID }
        )
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: - Transcription Operations

    func saveTranscription(
        for segmentID: UUID,
        text: String,
        metadata: ProcessingMetadata
    ) throws {
        let segment = try requireSegment(id: segmentID)

        // Flatten ProcessingMetadata into scalar columns. SwiftData has trouble with
        // nested Codable structs containing String? — storing scalars avoids crashes.
        let transcription = Transcription(
            text: text,
            attemptNumber: metadata.attemptNumber,
            processingDuration: metadata.processingDuration,
            modelVersion: metadata.modelVersion,
            detectedLanguage: metadata.language
        )
        segment.transcription = transcription
        segment.transcriptionStatus = .completed
        segment.transcriptionErrorDescription = nil

        try modelContext.save()
    }

    func fetchTranscription(for segmentID: UUID) throws -> TranscriptionDTO? {
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.segment?.id == segmentID }
        )
        return try modelContext.fetch(descriptor).first.map(\.dto)
    }

    // MARK: - Private Helpers

    private func sessionExists(id: UUID) throws -> Bool {
        let descriptor = FetchDescriptor<RecordingSession>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    private func findSession(id: UUID) throws -> RecordingSession? {
        var descriptor = FetchDescriptor<RecordingSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func requireSession(id: UUID) throws -> RecordingSession {
        guard let session = try findSession(id: id) else {
            throw PersistenceError.sessionNotFound(id)
        }
        return session
    }

    private func findSegment(id: UUID) throws -> Segment? {
        var descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func requireSegment(id: UUID) throws -> Segment {
        guard let segment = try findSegment(id: id) else {
            throw PersistenceError.segmentNotFound(id)
        }
        return segment
    }
}

// MARK: - DTO Conversions

private extension RecordingSession {
    var dto: RecordingSessionDTO {
        RecordingSessionDTO(
            id: id,
            createdDate: createdDate,
            sessionName: sessionName,
            totalDuration: totalDuration,
            segmentCount: segments.count
        )
    }
}

private extension Segment {
    var dto: SegmentDTO {
        SegmentDTO(
            id: id,
            sessionID: session?.id ?? UUID(),
            startTime: startTime,
            duration: duration,
            audioFileURL: audioFileURL,
            transcriptionStatus: transcriptionStatus,
            transcriptionErrorDescription: transcriptionErrorDescription
        )
    }
}

private extension Transcription {
    var dto: TranscriptionDTO {
        let metadata = ProcessingMetadata(
            attemptNumber: attemptNumber,
            processingDuration: processingDuration,
            modelVersion: modelVersion,
            language: detectedLanguage
        )
        return TranscriptionDTO(
            id: id,
            segmentID: segment?.id ?? UUID(),
            text: text,
            processingMetadata: metadata,
            createdAt: createdAt
        )
    }
}
