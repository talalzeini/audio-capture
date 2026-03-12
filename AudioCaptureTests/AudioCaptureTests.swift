//
//  AudioCaptureTests.swift
//  AudioCaptureTests
//
//  Unit tests + edge-case tests covering:
//    · RetryPolicy exponential-backoff calculations
//    · TranscriptionResult convenience helpers
//    · RecordingState equality, helpers, and descriptions
//    · AudioCaptureError localised descriptions
//    · PersistenceTypes (DTOs, enums, errors)
//    · DataManagerActor CRUD via an in-memory SwiftData container
//    · TranscriptionActor retry / concurrency / queuing behaviour
//    · Edge cases: duplicate IDs, unknown IDs, zero-attempt retry,
//      batch inserts, status filtering, empty audio path
//

import XCTest
import SwiftData
@testable import AudioCapture

// MARK: - RetryPolicy Tests

final class RetryPolicyTests: XCTestCase {

    func test_defaultPolicy_hasExpectedValues() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 1.0)
        XCTAssertEqual(policy.multiplier, 2.0)
        XCTAssertEqual(policy.maxDelay, 30.0)
    }

    func test_noRetryPolicy_singleAttempt() {
        XCTAssertEqual(RetryPolicy.noRetry.maxAttempts, 1)
    }

    func test_aggressivePolicy_hasMoreAttemptsThanDefault() {
        XCTAssertGreaterThan(RetryPolicy.aggressive.maxAttempts, RetryPolicy.default.maxAttempts)
    }

    func test_delay_firstAttempt_returnsBaseDelay() {
        XCTAssertEqual(RetryPolicy.default.delay(for: 1), 1.0, accuracy: 0.001)
    }

    func test_delay_secondAttempt_doublesBase() {
        XCTAssertEqual(RetryPolicy.default.delay(for: 2), 2.0, accuracy: 0.001)
    }

    func test_delay_thirdAttempt_quadruplesBase() {
        // The implementation returns 0 when attempt == maxAttempts (last attempt,
        // no delay needed before giving up). Use a policy with extra headroom so
        // attempt 3 is not the final one, letting the formula actually run.
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, multiplier: 2.0, maxDelay: 30.0)
        XCTAssertEqual(policy.delay(for: 3), 4.0, accuracy: 0.001)
    }

    func test_delay_neverExceedsMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 20, baseDelay: 1.0, multiplier: 2.0, maxDelay: 5.0)
        for attempt in 1..<20 {
            XCTAssertLessThanOrEqual(
                policy.delay(for: attempt), 5.0,
                "Delay exceeded maxDelay at attempt \(attempt)"
            )
        }
    }

    func test_delay_atMaxAttempts_returnsZero() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.delay(for: policy.maxAttempts), 0.0)
    }

    func test_delay_withMultiplierOne_isConstant() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 2.0, multiplier: 1.0, maxDelay: 10.0)
        for attempt in 1..<5 {
            XCTAssertEqual(policy.delay(for: attempt), 2.0, accuracy: 0.001,
                           "Expected constant delay at attempt \(attempt)")
        }
    }

    func test_delay_withZeroBase_isAlwaysZero() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: 0, multiplier: 2.0, maxDelay: 30.0)
        for attempt in 1..<4 {
            XCTAssertEqual(policy.delay(for: attempt), 0.0, accuracy: 0.001)
        }
    }
}

// MARK: - TranscriptionResult Tests

final class TranscriptionResultTests: XCTestCase {

    private func makeSegment(index: Int = 0) -> TranscriptionSegment {
        TranscriptionSegment(
            id: UUID(),
            audioURL: URL(fileURLWithPath: "/tmp/seg\(index).m4a"),
            segmentIndex: index,
            capturedAt: Date()
        )
    }

    func test_successOutcome_isSuccessTrue() {
        let r = TranscriptionResult(segment: makeSegment(),
                                     outcome: .success(transcript: "Hi", attemptNumber: 1))
        XCTAssertTrue(r.isSuccess)
    }

    func test_failureOutcome_isSuccessFalse() {
        let r = TranscriptionResult(segment: makeSegment(),
                                     outcome: .failure(errorDescription: "err", totalAttempts: 3))
        XCTAssertFalse(r.isSuccess)
    }

    func test_successOutcome_transcriptReturnsText() {
        let r = TranscriptionResult(segment: makeSegment(),
                                     outcome: .success(transcript: "Hello world", attemptNumber: 2))
        XCTAssertEqual(r.transcript, "Hello world")
    }

    func test_failureOutcome_transcriptReturnsNil() {
        let r = TranscriptionResult(segment: makeSegment(),
                                     outcome: .failure(errorDescription: "err", totalAttempts: 1))
        XCTAssertNil(r.transcript)
    }

    func test_segmentIdentityPreserved() {
        let seg = makeSegment(index: 7)
        let r = TranscriptionResult(segment: seg,
                                     outcome: .success(transcript: "ok", attemptNumber: 1))
        XCTAssertEqual(r.segment.id, seg.id)
        XCTAssertEqual(r.segment.segmentIndex, 7)
    }
}

// MARK: - RecordingState Tests

final class RecordingStateTests: XCTestCase {

    func test_sameStates_areEqual() {
        XCTAssertEqual(RecordingState.stopped, .stopped)
        XCTAssertEqual(RecordingState.recording, .recording)
        XCTAssertEqual(RecordingState.paused, .paused)
        XCTAssertEqual(RecordingState.interrupted, .interrupted)
        // .failed == .failed regardless of associated value
        XCTAssertEqual(RecordingState.failed(.alreadyRecording), .failed(.permissionDenied))
    }

    func test_differentStates_areNotEqual() {
        XCTAssertNotEqual(RecordingState.stopped, .recording)
        XCTAssertNotEqual(RecordingState.paused, .interrupted)
        XCTAssertNotEqual(RecordingState.recording, .failed(.permissionDenied))
    }

    func test_isActive_trueOnlyWhenRecording() {
        XCTAssertTrue(RecordingState.recording.isActive)
        XCTAssertFalse(RecordingState.stopped.isActive)
        XCTAssertFalse(RecordingState.paused.isActive)
        XCTAssertFalse(RecordingState.interrupted.isActive)
        XCTAssertFalse(RecordingState.failed(.permissionDenied).isActive)
    }

    func test_isStopped_trueOnlyWhenStopped() {
        XCTAssertTrue(RecordingState.stopped.isStopped)
        XCTAssertFalse(RecordingState.recording.isStopped)
        XCTAssertFalse(RecordingState.paused.isStopped)
        XCTAssertFalse(RecordingState.interrupted.isStopped)
    }

    func test_description_nonEmptyForAllCases() {
        let states: [RecordingState] = [
            .stopped, .recording, .paused, .interrupted,
            .failed(.alreadyRecording)
        ]
        for s in states {
            XCTAssertFalse(s.description.isEmpty, "description was empty for \(s)")
        }
    }
}

// MARK: - AudioCaptureError Tests

final class AudioCaptureErrorTests: XCTestCase {

    func test_permissionDenied_hasNonNilDescription() {
        XCTAssertNotNil(AudioCaptureError.permissionDenied.errorDescription)
    }

    func test_alreadyRecording_hasNonNilDescription() {
        XCTAssertNotNil(AudioCaptureError.alreadyRecording.errorDescription)
    }

    func test_recordingNotActive_hasNonNilDescription() {
        XCTAssertNotNil(AudioCaptureError.recordingNotActive.errorDescription)
    }

    func test_engineStartFailed_includesUnderlyingMessage() {
        struct FakeErr: LocalizedError {
            var errorDescription: String? { "engine exploded" }
        }
        let err = AudioCaptureError.engineStartFailed(FakeErr())
        XCTAssertTrue(err.errorDescription?.contains("engine exploded") == true)
    }

    func test_sessionConfigurationFailed_includesUnderlyingMessage() {
        struct FakeErr: LocalizedError {
            var errorDescription: String? { "session blew up" }
        }
        let err = AudioCaptureError.sessionConfigurationFailed(FakeErr())
        XCTAssertTrue(err.errorDescription?.contains("session blew up") == true)
    }

    func test_fileCreationFailed_includesUnderlyingMessage() {
        struct FakeErr: LocalizedError {
            var errorDescription: String? { "disk full" }
        }
        let err = AudioCaptureError.fileCreationFailed(FakeErr())
        XCTAssertTrue(err.errorDescription?.contains("disk full") == true)
    }
}

// MARK: - PersistenceTypes Tests

final class PersistenceTypesTests: XCTestCase {

    func test_allStatuses_roundtripViaRawValue() {
        for status in TranscriptionStatus.allCases {
            XCTAssertNotNil(TranscriptionStatus(rawValue: status.rawValue),
                            "Round-trip failed for: \(status.rawValue)")
        }
    }

    func test_transcriptionStatus_allCasesNonEmpty() {
        XCTAssertFalse(TranscriptionStatus.allCases.isEmpty)
    }

    func test_processingMetadata_optionalFieldsDefaultToNil() {
        let meta = ProcessingMetadata(attemptNumber: 1, processingDuration: 0.5)
        XCTAssertNil(meta.modelVersion)
        XCTAssertNil(meta.language)
    }

    func test_processingMetadata_storesAllProvidedFields() {
        let meta = ProcessingMetadata(
            attemptNumber: 3, processingDuration: 1.2,
            modelVersion: "whisper-1", language: "fr"
        )
        XCTAssertEqual(meta.attemptNumber, 3)
        XCTAssertEqual(meta.processingDuration, 1.2, accuracy: 0.001)
        XCTAssertEqual(meta.modelVersion, "whisper-1")
        XCTAssertEqual(meta.language, "fr")
    }

    func test_segmentSaveRequest_storesAllFields() {
        let id = UUID(); let sessionID = UUID()
        let url = URL(fileURLWithPath: "/tmp/seg.m4a")
        let req = SegmentSaveRequest(id: id, sessionID: sessionID,
                                      startTime: Date(), duration: 30, audioFileURL: url)
        XCTAssertEqual(req.id, id)
        XCTAssertEqual(req.sessionID, sessionID)
        XCTAssertEqual(req.duration, 30)
        XCTAssertEqual(req.audioFileURL, url)
    }

    func test_persistenceError_sessionNotFound_preservesID() {
        let id = UUID()
        if case .sessionNotFound(let extracted) = PersistenceError.sessionNotFound(id) {
            XCTAssertEqual(extracted, id)
        } else { XCTFail("Wrong error case") }
    }

    func test_persistenceError_segmentNotFound_preservesID() {
        let id = UUID()
        if case .segmentNotFound(let extracted) = PersistenceError.segmentNotFound(id) {
            XCTAssertEqual(extracted, id)
        } else { XCTFail("Wrong error case") }
    }

    func test_persistenceError_duplicateID_preservesID() {
        let id = UUID()
        if case .duplicateID(let extracted) = PersistenceError.duplicateID(id) {
            XCTAssertEqual(extracted, id)
        } else { XCTFail("Wrong error case") }
    }
}

// MARK: - DataManagerActor helpers

private func makeInMemoryDataManager() throws -> DataManagerActor {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: RecordingSession.self, Segment.self, Transcription.self,
        configurations: config
    )
    return DataManagerActor(modelContainer: container)
}

// MARK: - DataManagerActor Session Tests

final class DataManagerActorSessionTests: XCTestCase {

    func test_createSession_canBeRetrieved() async throws {
        let mgr = try makeInMemoryDataManager()
        let id  = UUID()
        try await mgr.createRecordingSession(id: id, name: "Test Session")
        let dto = try await mgr.fetchSession(id: id)
        XCTAssertNotNil(dto)
        XCTAssertEqual(dto?.sessionName, "Test Session")
    }

    func test_createSession_duplicateID_throwsDuplicateError() async throws {
        let mgr = try makeInMemoryDataManager()
        let id  = UUID()
        try await mgr.createRecordingSession(id: id, name: "Original")
        do {
            try await mgr.createRecordingSession(id: id, name: "Duplicate")
            XCTFail("Expected PersistenceError.duplicateID")
        } catch PersistenceError.duplicateID(let thrownID) {
            XCTAssertEqual(thrownID, id)
        }
    }

    func test_fetchSession_unknownID_returnsNil() async throws {
        let mgr = try makeInMemoryDataManager()
        let result = try await mgr.fetchSession(id: UUID())
        XCTAssertNil(result)
    }

    func test_updateSessionDuration_reflectsNewValue() async throws {
        let mgr = try makeInMemoryDataManager()
        let id  = UUID()
        try await mgr.createRecordingSession(id: id, name: "Session")
        try await mgr.updateSessionDuration(id, duration: 123.4)
        let dto = try await mgr.fetchSession(id: id)
        XCTAssertEqual(dto?.totalDuration ?? 0, 123.4, accuracy: 0.001)
    }

    func test_updateSessionDuration_unknownID_throwsSessionNotFound() async throws {
        let mgr = try makeInMemoryDataManager()
        do {
            try await mgr.updateSessionDuration(UUID(), duration: 10)
            XCTFail("Expected sessionNotFound")
        } catch PersistenceError.sessionNotFound { /* expected */ }
    }

    func test_deleteSession_removesRecord() async throws {
        let mgr = try makeInMemoryDataManager()
        let id  = UUID()
        try await mgr.createRecordingSession(id: id, name: "To Delete")
        try await mgr.deleteSession(id: id)
        let deleted = try await mgr.fetchSession(id: id)
        XCTAssertNil(deleted)
    }

    func test_deleteSession_unknownID_throwsSessionNotFound() async throws {
        let mgr = try makeInMemoryDataManager()
        do {
            try await mgr.deleteSession(id: UUID())
            XCTFail("Expected sessionNotFound")
        } catch PersistenceError.sessionNotFound { /* expected */ }
    }

    func test_sessionCount_incrementsOnEachCreate() async throws {
        let mgr = try makeInMemoryDataManager()
        let initial = try await mgr.sessionCount()
        try await mgr.createRecordingSession(id: UUID(), name: "A")
        try await mgr.createRecordingSession(id: UUID(), name: "B")
        let finalCount = try await mgr.sessionCount()
        XCTAssertEqual(finalCount, initial + 2)
    }

    func test_fetchSessions_respectsLimit() async throws {
        let mgr = try makeInMemoryDataManager()
        for i in 0..<10 { try await mgr.createRecordingSession(id: UUID(), name: "S\(i)") }
        let page = try await mgr.fetchSessions(limit: 3, offset: 0)
        XCTAssertEqual(page.count, 3)
    }

    func test_fetchSessions_respectsOffset() async throws {
        let mgr = try makeInMemoryDataManager()
        for i in 0..<6 { try await mgr.createRecordingSession(id: UUID(), name: "S\(i)") }
        let all    = try await mgr.fetchSessions(limit: 10, offset: 0)
        let offset = try await mgr.fetchSessions(limit: 10, offset: 2)
        XCTAssertEqual(offset.count, all.count - 2)
    }

    func test_fetchSessions_sortedByDateDescending() async throws {
        let mgr = try makeInMemoryDataManager()
        let t0  = Date()
        try await mgr.createRecordingSession(id: UUID(), name: "Older",
                                              createdDate: t0.addingTimeInterval(-100))
        try await mgr.createRecordingSession(id: UUID(), name: "Newer",
                                              createdDate: t0)
        let sessions = try await mgr.fetchSessions(limit: 10)
        XCTAssertEqual(sessions.first?.sessionName, "Newer")
    }
}

// MARK: - DataManagerActor Segment Tests

final class DataManagerActorSegmentTests: XCTestCase {

    private func makeManagerAndSession() async throws -> (DataManagerActor, UUID) {
        let mgr = try makeInMemoryDataManager()
        let sid = UUID()
        try await mgr.createRecordingSession(id: sid, name: "Session")
        return (mgr, sid)
    }

    private func makeRequest(sessionID: UUID, index: Int = 0) -> SegmentSaveRequest {
        SegmentSaveRequest(
            id: UUID(), sessionID: sessionID,
            startTime: Date().addingTimeInterval(Double(index) * 30),
            duration: 30,
            audioFileURL: URL(fileURLWithPath: "/tmp/seg\(index).m4a")
        )
    }

    func test_saveSegment_appearsInFetch() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let req        = makeRequest(sessionID: sid)
        try await mgr.saveSegment(req)
        let segments = try await mgr.fetchSegments(for: sid)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.id, req.id)
    }

    func test_saveSegment_unknownSessionID_throwsSessionNotFound() async throws {
        let mgr = try makeInMemoryDataManager()
        do {
            try await mgr.saveSegment(makeRequest(sessionID: UUID()))
            XCTFail("Expected sessionNotFound")
        } catch PersistenceError.sessionNotFound { /* expected */ }
    }

    func test_saveSegments_batch_allInserted() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let requests   = (0..<5).map { makeRequest(sessionID: sid, index: $0) }
        try await mgr.saveSegments(requests)
        let count = try await mgr.segmentCount(for: sid)
        XCTAssertEqual(count, 5)
    }

    func test_saveSegments_empty_noThrow() async throws {
        let mgr = try makeInMemoryDataManager()
        try await mgr.saveSegments([])
    }

    func test_updateSegmentStatus_reflectsChange() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let req        = makeRequest(sessionID: sid)
        try await mgr.saveSegment(req)
        try await mgr.updateSegmentStatus(req.id, status: .completed)
        let completed = try await mgr.fetchSegments(for: sid, status: .completed)
        XCTAssertEqual(completed.count, 1)
    }

    func test_updateSegmentStatus_unknownID_throwsSegmentNotFound() async throws {
        let mgr = try makeInMemoryDataManager()
        do {
            try await mgr.updateSegmentStatus(UUID(), status: .failed)
            XCTFail("Expected segmentNotFound")
        } catch PersistenceError.segmentNotFound { /* expected */ }
    }

    func test_updateSegmentStatus_setsErrorDescription() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let req        = makeRequest(sessionID: sid)
        try await mgr.saveSegment(req)
        try await mgr.updateSegmentStatus(req.id, status: .failed,
                                           errorDescription: "network timeout")
        let failed = try await mgr.fetchSegments(for: sid, status: .failed)
        XCTAssertEqual(failed.first?.transcriptionErrorDescription, "network timeout")
    }

    func test_fetchSegments_filterByStatus_returnsOnlyMatching() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let ids = (0..<3).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            let req = SegmentSaveRequest(id: id, sessionID: sid,
                                          startTime: Date(), duration: 30,
                                          audioFileURL: URL(fileURLWithPath: "/tmp/\(i).m4a"))
            try await mgr.saveSegment(req)
        }
        try await mgr.updateSegmentStatus(ids[2], status: .completed)
        let pending   = try await mgr.fetchSegments(for: sid, status: .pending)
        let completed = try await mgr.fetchSegments(for: sid, status: .completed)
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(completed.count, 1)
    }

    func test_fetchPendingSegments_excludesCompleted() async throws {
        let (mgr, sid) = try await makeManagerAndSession()
        let ids = (0..<3).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            let req = SegmentSaveRequest(id: id, sessionID: sid,
                                          startTime: Date(), duration: 30,
                                          audioFileURL: URL(fileURLWithPath: "/tmp/\(i).m4a"))
            try await mgr.saveSegment(req)
        }
        try await mgr.updateSegmentStatus(ids[0], status: .completed)
        try await mgr.updateSegmentStatus(ids[1], status: .failed)

        let pending  = try await mgr.fetchPendingSegments()
        let statuses = Set(pending.map(\.transcriptionStatus))
        XCTAssertFalse(statuses.contains(.completed))
    }
}

// MARK: - DataManagerActor Transcription Tests

final class DataManagerActorTranscriptionTests: XCTestCase {

    private func makeManagerWithSegment() async throws -> (DataManagerActor, UUID, UUID) {
        let mgr = try makeInMemoryDataManager()
        let sid = UUID(); let segID = UUID()
        try await mgr.createRecordingSession(id: sid, name: "Session")
        let req = SegmentSaveRequest(id: segID, sessionID: sid,
                                      startTime: Date(), duration: 30,
                                      audioFileURL: URL(fileURLWithPath: "/tmp/s.m4a"))
        try await mgr.saveSegment(req)
        return (mgr, sid, segID)
    }

    func test_saveTranscription_canBeRetrieved() async throws {
        let (mgr, _, segID) = try await makeManagerWithSegment()
        let meta = ProcessingMetadata(attemptNumber: 1, processingDuration: 0.8,
                                       modelVersion: "whisper-1", language: "en")
        try await mgr.saveTranscription(for: segID, text: "Hello world", metadata: meta)
        let dto = try await mgr.fetchTranscription(for: segID)
        XCTAssertEqual(dto?.text, "Hello world")
        XCTAssertEqual(dto?.processingMetadata.modelVersion, "whisper-1")
        XCTAssertEqual(dto?.processingMetadata.language, "en")
    }

    func test_saveTranscription_marksSegmentCompleted() async throws {
        let (mgr, sid, segID) = try await makeManagerWithSegment()
        let meta = ProcessingMetadata(attemptNumber: 1, processingDuration: 0.5)
        try await mgr.saveTranscription(for: segID, text: "Test", metadata: meta)
        let completed = try await mgr.fetchSegments(for: sid, status: .completed)
        XCTAssertEqual(completed.count, 1)
    }

    func test_saveTranscription_unknownSegmentID_throws() async throws {
        let mgr  = try makeInMemoryDataManager()
        let meta = ProcessingMetadata(attemptNumber: 1, processingDuration: 0)
        do {
            try await mgr.saveTranscription(for: UUID(), text: "text", metadata: meta)
            XCTFail("Expected segmentNotFound")
        } catch PersistenceError.segmentNotFound { /* expected */ }
    }

    func test_fetchTranscription_unknownSegment_returnsNil() async throws {
        let mgr = try makeInMemoryDataManager()
        let result = try await mgr.fetchTranscription(for: UUID())
        XCTAssertNil(result)
    }

    func test_saveTranscription_clearsErrorDescription() async throws {
        let (mgr, sid, segID) = try await makeManagerWithSegment()
        try await mgr.updateSegmentStatus(segID, status: .failed,
                                           errorDescription: "some error")
        let meta = ProcessingMetadata(attemptNumber: 2, processingDuration: 0.3)
        try await mgr.saveTranscription(for: segID, text: "Fixed", metadata: meta)
        let segment = try await mgr.fetchSegments(for: sid).first
        XCTAssertNil(segment?.transcriptionErrorDescription)
    }
}

// MARK: - TranscriptionActor Tests

private final class MockTranscriptionAPI: TranscriptionAPI, @unchecked Sendable {
    enum Behaviour {
        case alwaysSucceed(String)
        case alwaysFail(Error)
        case failThenSucceed(failCount: Int, transcript: String)
        /// Suspends forever — useful for freezing in-flight tasks so queue
        /// counts can be inspected without racing against completion.
        case neverComplete
    }
    private let behaviour: Behaviour
    private var callCount = 0
    private let lock = NSLock()

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func transcribe(audioURL: URL) async throws -> String {
        lock.lock(); callCount += 1; let n = callCount; lock.unlock()
        switch behaviour {
        case .alwaysSucceed(let t):   return t
        case .alwaysFail(let e):      throw e
        case .failThenSucceed(let fc, let t):
            if n <= fc { throw URLError(.notConnectedToInternet) }
            return t
        case .neverComplete:
            // Suspend until the task is cancelled (test teardown).
            try await Task.sleep(for: .seconds(60 * 60))
            throw CancellationError()
        }
    }
}

final class TranscriptionActorTests: XCTestCase {

    private func makeSegment(index: Int = 0) -> TranscriptionSegment {
        TranscriptionSegment(id: UUID(),
                              audioURL: URL(fileURLWithPath: "/tmp/seg\(index).m4a"),
                              segmentIndex: index, capturedAt: Date())
    }

    private func makeActor(
        api: any TranscriptionAPI,
        policy: RetryPolicy = .noRetry,
        maxConcurrent: Int = 3
    ) -> TranscriptionActor {
        TranscriptionActor(api: api, retryPolicy: policy,
                            networkMonitor: NetworkMonitor(),
                            maxConcurrentTranscriptions: maxConcurrent)
    }

    func test_submit_successfulAPI_emitsSuccessResult() async throws {
        let a   = makeActor(api: MockTranscriptionAPI(.alwaysSucceed("Hello world")))
        let seg = makeSegment()
        await a.submit(seg)
        let result = try await firstResult(from: a.results, timeout: 5)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.transcript, "Hello world")
        XCTAssertEqual(result.segment.id, seg.id)
    }

    func test_submit_multipleSegments_allResultsEmitted() async throws {
        let a = makeActor(api: MockTranscriptionAPI(.alwaysSucceed("text")), maxConcurrent: 5)
        for i in 0..<5 { await a.submit(makeSegment(index: i)) }
        let results = try await collectResults(from: a.results, count: 5, timeout: 10)
        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy(\.isSuccess))
    }

    func test_submit_alwaysFailingAPI_emitsFailureResult() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0, multiplier: 1, maxDelay: 0)
        let a = makeActor(api: MockTranscriptionAPI(.alwaysFail(URLError(.badServerResponse))),
                           policy: policy)
        await a.submit(makeSegment())
        let result = try await firstResult(from: a.results, timeout: 5)
        XCTAssertFalse(result.isSuccess)
    }

    func test_submit_failThenSucceed_retryLeadsToSuccess() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, multiplier: 1, maxDelay: 0)
        let a = makeActor(
            api: MockTranscriptionAPI(.failThenSucceed(failCount: 1, transcript: "Retry worked")),
            policy: policy
        )
        await a.submit(makeSegment())
        let result = try await firstResult(from: a.results, timeout: 5)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.transcript, "Retry worked")
    }

    func test_submit_zeroMaxAttempts_treatedAsSingleAttempt() async throws {
        let policy = RetryPolicy(maxAttempts: 0, baseDelay: 0, multiplier: 1, maxDelay: 0)
        let a = makeActor(api: MockTranscriptionAPI(.alwaysFail(URLError(.timedOut))),
                           policy: policy)
        await a.submit(makeSegment())
        let result = try await firstResult(from: a.results, timeout: 5)
        XCTAssertFalse(result.isSuccess)
    }

    func test_submit_emptyAudioPath_stillEmitsResult() async throws {
        let a = makeActor(api: MockTranscriptionAPI(.alwaysSucceed("ok")))
        let seg = TranscriptionSegment(id: UUID(), audioURL: URL(fileURLWithPath: ""),
                                        segmentIndex: 0, capturedAt: Date())
        await a.submit(seg)
        let result = try await firstResult(from: a.results, timeout: 5)
        XCTAssertNotNil(result)
    }

    func test_pendingPlusActiveEqualsSubmitted() async throws {
        // Use a never-completing mock so all submitted segments stay in-flight
        // (active or pending) while we read the counters — avoids a race where
        // alwaysSucceed finishes before we can observe the queue state.
        let a = makeActor(api: MockTranscriptionAPI(.neverComplete), maxConcurrent: 1)
        for i in 0..<4 { await a.submit(makeSegment(index: i)) }
        let active  = await a.activeCount
        let pending = await a.pendingSegmentCount
        XCTAssertEqual(active + pending, 4)
    }
}

// MARK: - Async helpers

private func firstResult(
    from stream: AsyncStream<TranscriptionResult>,
    timeout seconds: TimeInterval
) async throws -> TranscriptionResult {
    try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
        group.addTask {
            for await result in stream { return result }
            throw XCTestError(.timeoutWhileWaiting)
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw XCTestError(.timeoutWhileWaiting)
        }
        let first = try await group.next()!
        group.cancelAll()
        return first
    }
}

private func collectResults(
    from stream: AsyncStream<TranscriptionResult>,
    count: Int,
    timeout seconds: TimeInterval
) async throws -> [TranscriptionResult] {
    try await withThrowingTaskGroup(of: [TranscriptionResult].self) { group in
        group.addTask {
            var results: [TranscriptionResult] = []
            for await result in stream {
                results.append(result)
                if results.count == count { return results }
            }
            return results
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw XCTestError(.timeoutWhileWaiting)
        }
        let first = try await group.next()!
        group.cancelAll()
        return first
    }
}
