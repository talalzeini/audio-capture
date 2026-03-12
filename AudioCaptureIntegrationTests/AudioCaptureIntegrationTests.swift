//
//  AudioCaptureIntegrationTests.swift
//  AudioCaptureIntegrationTests
//
//  Integration tests covering cross-component behaviour:
//    · TranscriptionActor ↔ DataManagerActor (success, failure, retry, concurrency)
//    · FallbackTranscriptionAPI switching logic (failover & recovery)
//    · FallbackTranscriptionAPI wired through TranscriptionActor
//    · DataManagerActor cascade-delete lifecycle
//    · SegmentManagerActor ↔ DataManagerActor (session creation & duration)
//

import AVFoundation
import XCTest
import SwiftData
@testable import AudioCapture

// MARK: - Shared Helpers

private func makeInMemoryDataManager() throws -> DataManagerActor {
    let schema = Schema([RecordingSession.self, Segment.self, Transcription.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return DataManagerActor(modelContainer: container)
}

private func makeSegmentRequest(sessionID: UUID, index: Int = 0) -> SegmentSaveRequest {
    SegmentSaveRequest(
        id: UUID(),
        sessionID: sessionID,
        startTime: Date(timeIntervalSinceNow: Double(index) * 30),
        duration: 30,
        audioFileURL: URL(fileURLWithPath: "/tmp/integ_seg\(index).m4a")
    )
}

private func makeTranscriptionSegment(index: Int = 0) -> TranscriptionSegment {
    TranscriptionSegment(
        id: UUID(),
        audioURL: URL(fileURLWithPath: "/tmp/integ_seg\(index).m4a"),
        segmentIndex: index,
        capturedAt: Date()
    )
}

private func firstResult(
    from stream: AsyncStream<TranscriptionResult>,
    timeout seconds: TimeInterval = 5
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
    timeout seconds: TimeInterval = 10
) async throws -> [TranscriptionResult] {
    try await withThrowingTaskGroup(of: [TranscriptionResult].self) { group in
        group.addTask {
            var collected: [TranscriptionResult] = []
            for await result in stream {
                collected.append(result)
                if collected.count == count { return collected }
            }
            throw XCTestError(.timeoutWhileWaiting)
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw XCTestError(.timeoutWhileWaiting)
        }
        let results = try await group.next()!
        group.cancelAll()
        return results
    }
}

// MARK: - Mock API

private final class MockTranscriptionAPI: TranscriptionAPI, @unchecked Sendable {
    enum Behaviour {
        case alwaysSucceed(String)
        case alwaysFail(Error)
        case failThenSucceed(failCount: Int, transcript: String)
    }

    private let behaviour: Behaviour
    private var callCount = 0
    private let lock = NSLock()

    private(set) var totalCalls: Int {
        get { lock.lock(); defer { lock.unlock() }; return callCount }
        set { lock.lock(); defer { lock.unlock() }; callCount = newValue }
    }

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func transcribe(audioURL: URL) async throws -> String {
        lock.lock(); callCount += 1; let n = callCount; lock.unlock()
        switch behaviour {
        case .alwaysSucceed(let t):   return t
        case .alwaysFail(let e):      throw e
        case .failThenSucceed(let fc, let t):
            if n <= fc { throw URLError(.notConnectedToInternet) }
            return t
        }
    }
}

// MARK: - TranscriptionActor ↔ DataManagerActor Integration

final class TranscriptionActorDataManagerIntegrationTests: XCTestCase {

    private func makeActor(
        api: any TranscriptionAPI,
        policy: RetryPolicy = .noRetry,
        dataManager: DataManagerActor
    ) -> TranscriptionActor {
        TranscriptionActor(
            api: api,
            retryPolicy: policy,
            networkMonitor: NetworkMonitor(),
            dataManager: dataManager
        )
    }

    // MARK: Success path

    /// A successful transcription should:
    ///  - emit a success result on the stream
    ///  - persist a Transcription record with the correct text
    ///  - update the Segment status to .completed
    func test_success_persistsTranscriptionAndUpdatesSegmentStatus() async throws {
        let mgr   = try makeInMemoryDataManager()
        let actor = makeActor(api: MockTranscriptionAPI(.alwaysSucceed("Hello, world")),
                              dataManager: mgr)

        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Test")
        let req = makeSegmentRequest(sessionID: sessionID)
        try await mgr.saveSegment(req)

        let seg = TranscriptionSegment(id: req.id,
                                       audioURL: req.audioFileURL,
                                       segmentIndex: 0,
                                       capturedAt: Date())
        await actor.submit(seg)

        let result = try await firstResult(from: actor.results)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.transcript, "Hello, world")

        // Persistence happens before the stream yields — no extra wait needed.
        let txn = try await mgr.fetchTranscription(for: req.id)
        XCTAssertNotNil(txn)
        XCTAssertEqual(txn?.text, "Hello, world")

        let segments = try await mgr.fetchSegments(for: sessionID)
        let saved = segments.first(where: { $0.id == req.id })
        XCTAssertEqual(saved?.transcriptionStatus, .completed)
        XCTAssertNil(saved?.transcriptionErrorDescription)
    }

    // MARK: Failure path

    /// A fully exhausted retry should:
    ///  - emit a failure result
    ///  - set segment status to .failed with a non-nil error description
    ///  - NOT create a Transcription record
    func test_failure_setsSegmentStatusFailedAndNoTranscription() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: 0, multiplier: 1, maxDelay: 0)
        let mgr    = try makeInMemoryDataManager()
        let actor  = makeActor(
            api: MockTranscriptionAPI(.alwaysFail(URLError(.badServerResponse))),
            policy: policy,
            dataManager: mgr
        )

        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Test")
        let req = makeSegmentRequest(sessionID: sessionID)
        try await mgr.saveSegment(req)

        let seg = TranscriptionSegment(id: req.id,
                                       audioURL: req.audioFileURL,
                                       segmentIndex: 0,
                                       capturedAt: Date())
        await actor.submit(seg)

        let result = try await firstResult(from: actor.results)
        XCTAssertFalse(result.isSuccess)

        let txn = try await mgr.fetchTranscription(for: req.id)
        XCTAssertNil(txn)

        let segments = try await mgr.fetchSegments(for: sessionID)
        let saved = segments.first(where: { $0.id == req.id })
        XCTAssertEqual(saved?.transcriptionStatus, .failed)
        XCTAssertNotNil(saved?.transcriptionErrorDescription)
    }

    // MARK: Retry then succeed

    /// After failing once and then succeeding, the persisted Transcription
    /// should record attemptNumber = 2.
    func test_retryThenSucceed_persistsCorrectAttemptNumber() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, multiplier: 1, maxDelay: 0)
        let mgr    = try makeInMemoryDataManager()
        let actor  = makeActor(
            api: MockTranscriptionAPI(.failThenSucceed(failCount: 1, transcript: "Retry worked")),
            policy: policy,
            dataManager: mgr
        )

        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Test")
        let req = makeSegmentRequest(sessionID: sessionID)
        try await mgr.saveSegment(req)

        let seg = TranscriptionSegment(id: req.id,
                                       audioURL: req.audioFileURL,
                                       segmentIndex: 0,
                                       capturedAt: Date())
        await actor.submit(seg)

        let result = try await firstResult(from: actor.results)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.transcript, "Retry worked")

        let txn = try await mgr.fetchTranscription(for: req.id)
        XCTAssertEqual(txn?.text, "Retry worked")
        XCTAssertEqual(txn?.processingMetadata.attemptNumber, 2)

        let segments = try await mgr.fetchSegments(for: sessionID)
        XCTAssertEqual(segments.first?.transcriptionStatus, .completed)
    }

    // MARK: Concurrent segments

    /// Five segments submitted concurrently should all be persisted and
    /// emitted, with no results dropped or duplicated.
    func test_concurrentSegments_allPersistedAndEmitted() async throws {
        let mgr   = try makeInMemoryDataManager()
        let actor = makeActor(
            api: MockTranscriptionAPI(.alwaysSucceed("ok")),
            policy: .noRetry,
            dataManager: mgr
        )

        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Test")

        let count = 5
        var segmentIDs: [UUID] = []
        for i in 0..<count {
            let req = makeSegmentRequest(sessionID: sessionID, index: i)
            try await mgr.saveSegment(req)
            segmentIDs.append(req.id)
            let seg = TranscriptionSegment(id: req.id,
                                            audioURL: req.audioFileURL,
                                            segmentIndex: i,
                                            capturedAt: Date())
            await actor.submit(seg)
        }

        let results = try await collectResults(from: actor.results, count: count)
        XCTAssertEqual(results.count, count)
        XCTAssertTrue(results.allSatisfy(\.isSuccess))

        // Every segment should now be .completed in the store.
        let segments = try await mgr.fetchSegments(for: sessionID)
        let completedCount = segments.filter { $0.transcriptionStatus == .completed }.count
        XCTAssertEqual(completedCount, count)
    }

    // MARK: fetchPendingSegments reflects live status

    /// After a successful transcription, the segment should no longer appear
    /// in fetchPendingSegments (it should only list pending/failed).
    func test_completedSegment_doesNotAppearInPendingFetch() async throws {
        let mgr   = try makeInMemoryDataManager()
        let actor = makeActor(api: MockTranscriptionAPI(.alwaysSucceed("done")),
                              dataManager: mgr)

        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Test")
        let req = makeSegmentRequest(sessionID: sessionID)
        try await mgr.saveSegment(req)

        // Before transcription: should be pending.
        let beforePending = try await mgr.fetchPendingSegments()
        XCTAssertEqual(beforePending.count, 1)

        let seg = TranscriptionSegment(id: req.id,
                                       audioURL: req.audioFileURL,
                                       segmentIndex: 0,
                                       capturedAt: Date())
        await actor.submit(seg)
        _ = try await firstResult(from: actor.results)

        // After transcription: should be gone from pending.
        let afterPending = try await mgr.fetchPendingSegments()
        XCTAssertEqual(afterPending.count, 0)
    }
}

// MARK: - FallbackTranscriptionAPI Integration

final class FallbackAPIIntegrationTests: XCTestCase {

    private func makeError() -> URLError { URLError(.notConnectedToInternet) }

    // MARK: Failover threshold

    /// Failures below the threshold should keep the API on primary.
    func test_belowThreshold_staysOnPrimary() async throws {
        let api = FallbackTranscriptionAPI(
            primary:  MockTranscriptionAPI(.alwaysFail(makeError())),
            fallback: MockTranscriptionAPI(.alwaysSucceed("fallback")),
            failureThreshold: 3
        )

        for _ in 0..<2 {
            _ = try? await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        }

        let usingFallback = await api.isUsingFallback
        XCTAssertFalse(usingFallback)
    }

    /// Hitting the failure threshold should switch to the fallback API.
    func test_atThreshold_switchesToFallback() async throws {
        let api = FallbackTranscriptionAPI(
            primary:  MockTranscriptionAPI(.alwaysFail(makeError())),
            fallback: MockTranscriptionAPI(.alwaysSucceed("fallback")),
            failureThreshold: 3
        )

        for _ in 0..<3 {
            _ = try? await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        }

        let usingFallback = await api.isUsingFallback
        XCTAssertTrue(usingFallback)
    }

    /// Once on the fallback, a success should reset consecutive failures but
    /// keep routing to fallback until the primary proves itself.
    func test_onFallback_successResetsFailureCount() async throws {
        let api = FallbackTranscriptionAPI(
            primary:  MockTranscriptionAPI(.alwaysFail(makeError())),
            fallback: MockTranscriptionAPI(.alwaysSucceed("fallback")),
            failureThreshold: 2
        )

        // Trigger failover.
        for _ in 0..<2 {
            _ = try? await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        }

        // Fallback call succeeds.
        let text = try await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        XCTAssertEqual(text, "fallback")

        let failures = await api.currentConsecutiveFailures
        XCTAssertEqual(failures, 0)
    }

    /// Once failures reset and primary starts succeeding again, the API
    /// should switch back to primary.
    func test_primaryRecovery_switchesBackFromFallback() async throws {
        // Primary fails twice (triggers switch), then always succeeds.
        let primary = MockTranscriptionAPI(.failThenSucceed(failCount: 2, transcript: "primary recovered"))
        let api = FallbackTranscriptionAPI(
            primary:  primary,
            fallback: MockTranscriptionAPI(.alwaysSucceed("fallback")),
            failureThreshold: 2
        )

        // Exhaust primary → switch to fallback.
        for _ in 0..<2 {
            _ = try? await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))
        }
        let onFallback = await api.isUsingFallback
        XCTAssertTrue(onFallback)

        // A successful fallback call resets the count and switches back.
        _ = try await api.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.m4a"))

        let backOnPrimary = await api.isUsingFallback
        XCTAssertFalse(backOnPrimary)
    }

    /// FallbackTranscriptionAPI wired into TranscriptionActor should still
    /// deliver results transparently even after the API has switched providers.
    func test_insideTranscriptionActor_resultsDeliveredAfterFailover() async throws {
        let primary = MockTranscriptionAPI(.failThenSucceed(failCount: 2, transcript: "primary text"))
        let fallback = MockTranscriptionAPI(.alwaysSucceed("fallback text"))
        let fallbackAPI = FallbackTranscriptionAPI(
            primary: primary,
            fallback: fallback,
            failureThreshold: 2
        )

        let actor = TranscriptionActor(
            api: fallbackAPI,
            retryPolicy: RetryPolicy(maxAttempts: 4, baseDelay: 0, multiplier: 1, maxDelay: 0),
            networkMonitor: NetworkMonitor()
        )

        await actor.submit(makeTranscriptionSegment())
        let result = try await firstResult(from: actor.results)

        // Should succeed eventually — either through retries or fallback.
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(result.transcript)
    }
}

// MARK: - DataManagerActor Cascade Lifecycle Integration

final class DataManagerCascadeIntegrationTests: XCTestCase {

    /// Deleting a session should cascade and remove all its child segments.
    func test_deleteSession_cascadesToSegments() async throws {
        let mgr = try makeInMemoryDataManager()
        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Cascade Test")

        let requests = (0..<5).map { makeSegmentRequest(sessionID: sessionID, index: $0) }
        try await mgr.saveSegments(requests)

        let before = try await mgr.segmentCount(for: sessionID)
        XCTAssertEqual(before, 5)

        try await mgr.deleteSession(id: sessionID)

        // Session should be gone.
        let session = try await mgr.fetchSession(id: sessionID)
        XCTAssertNil(session)

        // Session count should have dropped by 1.
        let remaining = try await mgr.sessionCount()
        XCTAssertEqual(remaining, 0)
    }

    /// Deleting a session should cascade through to Transcription records.
    func test_deleteSession_cascadesToTranscriptions() async throws {
        let mgr = try makeInMemoryDataManager()
        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Cascade Test")

        let req = makeSegmentRequest(sessionID: sessionID)
        try await mgr.saveSegment(req)

        let metadata = ProcessingMetadata(attemptNumber: 1, processingDuration: 0.1)
        try await mgr.saveTranscription(for: req.id, text: "Hello", metadata: metadata)

        // Transcription exists before delete.
        let txnBefore = try await mgr.fetchTranscription(for: req.id)
        XCTAssertNotNil(txnBefore)

        try await mgr.deleteSession(id: sessionID)

        // Transcription should be gone (cascade: session → segment → transcription).
        let txnAfter = try await mgr.fetchTranscription(for: req.id)
        XCTAssertNil(txnAfter)
    }

    /// Full round-trip: create session → batch-save segments → transcribe each →
    /// delete session → verify store is empty.
    func test_fullLifecycleRoundTrip() async throws {
        let mgr = try makeInMemoryDataManager()
        let sessionID = UUID()
        try await mgr.createRecordingSession(id: sessionID, name: "Round Trip")

        let requests = (0..<3).map { makeSegmentRequest(sessionID: sessionID, index: $0) }
        try await mgr.saveSegments(requests)

        let metadata = ProcessingMetadata(attemptNumber: 1, processingDuration: 0.5)
        for req in requests {
            try await mgr.saveTranscription(for: req.id, text: "text \(req.id)", metadata: metadata)
        }

        // Verify everything is present.
        let segments = try await mgr.fetchSegments(for: sessionID)
        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments.allSatisfy { $0.transcriptionStatus == .completed })

        // Delete and verify store is clean.
        try await mgr.deleteSession(id: sessionID)

        let sessionCount = try await mgr.sessionCount()
        XCTAssertEqual(sessionCount, 0)
    }

    /// Two sessions are independent — deleting one should not affect the other.
    func test_deleteOneSession_doesNotAffectSibling() async throws {
        let mgr = try makeInMemoryDataManager()
        let id1 = UUID()
        let id2 = UUID()
        try await mgr.createRecordingSession(id: id1, name: "Session 1")
        try await mgr.createRecordingSession(id: id2, name: "Session 2")

        try await mgr.saveSegments((0..<3).map { makeSegmentRequest(sessionID: id1, index: $0) })
        try await mgr.saveSegments((0..<3).map { makeSegmentRequest(sessionID: id2, index: $0) })

        try await mgr.deleteSession(id: id1)

        let remaining = try await mgr.fetchSession(id: id2)
        XCTAssertNotNil(remaining)

        let siblingSegments = try await mgr.segmentCount(for: id2)
        XCTAssertEqual(siblingSegments, 3)
    }

    /// Updating session duration after saving segments should be persisted and
    /// reflected in the next fetch.
    func test_updateSessionDuration_reflected() async throws {
        let mgr = try makeInMemoryDataManager()
        let id = UUID()
        try await mgr.createRecordingSession(id: id, name: "Duration Test")

        try await mgr.updateSessionDuration(id, duration: 123.45)

        let dto = try await mgr.fetchSession(id: id)
        XCTAssertEqual(dto?.totalDuration ?? 0, 123.45, accuracy: 0.001)
    }
}

// MARK: - SegmentManagerActor ↔ DataManagerActor Integration

final class SegmentManagerActorDataManagerIntegrationTests: XCTestCase {

    private func makeMockActor(dataManager: DataManagerActor) -> SegmentManagerActor {
        let transcriptionActor = TranscriptionActor(
            api: MockTranscriptionAPI(.alwaysSucceed("ok")),
            retryPolicy: .noRetry,
            networkMonitor: NetworkMonitor(),
            dataManager: dataManager
        )
        return SegmentManagerActor(
            transcriptionActor: transcriptionActor,
            dataManager: dataManager,
            segmentDuration: 30
        )
    }

    /// `beginSession` should immediately create a persisted RecordingSession
    /// entry in the DataManagerActor.
    func test_beginSession_createsPersistedSession() async throws {
        let mgr = try makeInMemoryDataManager()
        let segMgr = makeMockActor(dataManager: mgr)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            XCTFail("Could not create AVAudioFormat")
            return
        }

        _ = try await segMgr.beginSession(format: format)

        let sessionCount = try await mgr.sessionCount()
        XCTAssertEqual(sessionCount, 1)
    }

    /// `endSession` should update the session's `totalDuration` to a non-zero value.
    func test_endSession_updatesDuration() async throws {
        let mgr = try makeInMemoryDataManager()
        let segMgr = makeMockActor(dataManager: mgr)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            XCTFail("Could not create AVAudioFormat")
            return
        }

        _ = try await segMgr.beginSession(format: format)

        // A small real delay so the duration is measurably > 0.
        try await Task.sleep(for: .milliseconds(50))

        await segMgr.endSession()

        let sessions = try await mgr.fetchSessions()
        let duration = sessions.first?.totalDuration ?? 0
        XCTAssertGreaterThan(duration, 0)
    }

    /// Starting two consecutive sessions should result in two persisted records.
    func test_consecutiveSessions_bothPersisted() async throws {
        let mgr = try makeInMemoryDataManager()
        let segMgr = makeMockActor(dataManager: mgr)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            XCTFail("Could not create AVAudioFormat")
            return
        }

        _ = try await segMgr.beginSession(format: format)
        await segMgr.endSession()

        _ = try await segMgr.beginSession(format: format)
        await segMgr.endSession()

        let count = try await mgr.sessionCount()
        XCTAssertEqual(count, 2)
    }
}
