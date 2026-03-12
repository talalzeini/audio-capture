//
//  AudioCapturePerformanceTests.swift
//  AudioCapturePerformanceTests
//
//  Created by Talal El Zeini on 3/12/26.
//
//  Performance tests covering:
//    · RetryPolicy delay-calculation throughput (pure CPU, sync)
//    · DataManagerActor bulk insert / paginated fetch / status update
//    · DataManagerActor predicate query under realistic data volume
//    · TranscriptionActor end-to-end and submission throughput
//

import XCTest
import SwiftData
@testable import AudioCapture

// MARK: - Shared Helpers

/// Creates a fresh, in-memory DataManagerActor for each test / iteration so
/// no on-disk state leaks between measurements.
private func makeInMemoryDataManager() throws -> DataManagerActor {
    let schema = Schema([RecordingSession.self, Segment.self, Transcription.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return DataManagerActor(modelContainer: container)
}

private func makeSegmentRequest(sessionID: UUID, index: Int) -> SegmentSaveRequest {
    SegmentSaveRequest(
        id: UUID(),
        sessionID: sessionID,
        startTime: Date(timeIntervalSinceNow: Double(index) * 30),
        duration: 30,
        audioFileURL: URL(fileURLWithPath: "/tmp/perf_seg\(index).m4a")
    )
}

/// Instant mock — returns a canned transcript immediately, no real I/O.
private final class InstantMockAPI: TranscriptionAPI, @unchecked Sendable {
    func transcribe(audioURL: URL) async throws -> String { "transcript" }
}

// MARK: - RetryPolicy Performance

/// Pure CPU: measures how quickly the backoff formula can be evaluated in a
/// tight loop across all preset policies. Should run in single-digit ms.
final class RetryPolicyPerformanceTests: XCTestCase {

    /// 10 000 iterations across all three preset policies.
    func test_delay_computationThroughput() {
        let policies: [RetryPolicy] = [.default, .aggressive, .noRetry]
        measure {
            for _ in 0..<10_000 {
                for policy in policies {
                    for attempt in 1...max(policy.maxAttempts, 1) {
                        _ = policy.delay(for: attempt)
                    }
                }
            }
        }
    }

    /// Verifies clamping to maxDelay doesn't introduce unexpected cost for
    /// policies with a large maxAttempts.
    func test_delay_maxDelayClamping_throughput() {
        let policy = RetryPolicy(
            maxAttempts: 1_000,
            baseDelay: 1.0,
            multiplier: 2.0,
            maxDelay: 30.0
        )
        measure {
            for attempt in 1...1_000 {
                _ = policy.delay(for: attempt)
            }
        }
    }
}

// MARK: - DataManagerActor Performance

final class DataManagerActorPerformanceTests: XCTestCase {

    /// 5 iterations keeps CI quick while still capturing variance.
    private var options: XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }

    // MARK: Session throughput

    /// Insert 100 sessions one at a time and measure total wall-clock time.
    /// Represents the worst-case initialisation cost on first launch.
    func test_insertSessions_100_sequential() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    for i in 0..<100 {
                        try await mgr.createRecordingSession(
                            id: UUID(),
                            name: "Session \(i)"
                        )
                    }
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Seed 100 sessions then measure a paginated fetch of the first 50,
    /// sorted by date descending — the default sessions-list query.
    func test_fetchSessions_paginated50_from100() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    for i in 0..<100 {
                        try await mgr.createRecordingSession(id: UUID(), name: "S\(i)")
                    }
                    _ = try await mgr.fetchSessions(limit: 50, offset: 0)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    // MARK: Segment throughput

    /// Batch-save 50 segments in a single save() call.
    /// Represents the cost of persisting one full recording session's worth of
    /// segments at once (the hot path at session end).
    func test_saveSegments_batch50() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    let sessionID = UUID()
                    try await mgr.createRecordingSession(id: sessionID, name: "Perf")
                    let requests = (0..<50).map {
                        makeSegmentRequest(sessionID: sessionID, index: $0)
                    }
                    try await mgr.saveSegments(requests)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Seed 200 segments (100 pending, 100 completed), then measure
    /// `fetchPendingSegments` — this predicate query runs on every app launch
    /// to rehydrate the offline transcription queue.
    func test_fetchPendingSegments_from200Segments() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    let sessionID = UUID()
                    try await mgr.createRecordingSession(id: sessionID, name: "Perf")

                    let requests = (0..<200).map {
                        makeSegmentRequest(sessionID: sessionID, index: $0)
                    }
                    try await mgr.saveSegments(requests)

                    // Mark the first 100 as completed so the predicate has real
                    // filtering work to do (not all rows qualify).
                    let all = try await mgr.fetchSegments(for: sessionID)
                    for seg in all.prefix(100) {
                        try await mgr.updateSegmentStatus(seg.id, status: .completed)
                    }

                    _ = try await mgr.fetchPendingSegments(limit: 100)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 60)
        }
    }

    /// Measure the filtered `fetchSegments(for:status:)` predicate against a
    /// session with 100 segments — used when the UI filters by transcription state.
    func test_fetchSegments_filteredByStatus_from100() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    let sessionID = UUID()
                    try await mgr.createRecordingSession(id: sessionID, name: "Perf")
                    let requests = (0..<100).map {
                        makeSegmentRequest(sessionID: sessionID, index: $0)
                    }
                    try await mgr.saveSegments(requests)
                    _ = try await mgr.fetchSegments(for: sessionID, status: .pending)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Measure sequential status updates for 50 segments — called once per
    /// completed transcription during a live recording session.
    func test_updateSegmentStatus_sequential50() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    let sessionID = UUID()
                    try await mgr.createRecordingSession(id: sessionID, name: "Perf")
                    let requests = (0..<50).map {
                        makeSegmentRequest(sessionID: sessionID, index: $0)
                    }
                    try await mgr.saveSegments(requests)
                    let segments = try await mgr.fetchSegments(for: sessionID)
                    for seg in segments {
                        try await mgr.updateSegmentStatus(seg.id, status: .completed)
                    }
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Measure the full transcription save path: fetch segment → create
    /// Transcription model → update status → save. Called per result.
    func test_saveTranscription_sequential30() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                do {
                    let mgr = try makeInMemoryDataManager()
                    let sessionID = UUID()
                    try await mgr.createRecordingSession(id: sessionID, name: "Perf")
                    let requests = (0..<30).map {
                        makeSegmentRequest(sessionID: sessionID, index: $0)
                    }
                    try await mgr.saveSegments(requests)
                    let segments = try await mgr.fetchSegments(for: sessionID)
                    let metadata = ProcessingMetadata(
                        attemptNumber: 1,
                        processingDuration: 0.5
                    )
                    for seg in segments {
                        try await mgr.saveTranscription(
                            for: seg.id,
                            text: "Hello world",
                            metadata: metadata
                        )
                    }
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }
}

// MARK: - TranscriptionActor Performance

final class TranscriptionActorPerformanceTests: XCTestCase {

    private var options: XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }

    private func makeSegment(index: Int) -> TranscriptionSegment {
        TranscriptionSegment(
            id: UUID(),
            audioURL: URL(fileURLWithPath: "/tmp/perf\(index).m4a"),
            segmentIndex: index,
            capturedAt: Date()
        )
    }

    private func makeActor(maxConcurrent: Int = 5,
                            policy: RetryPolicy = .noRetry) -> TranscriptionActor {
        TranscriptionActor(
            api: InstantMockAPI(),
            retryPolicy: policy,
            networkMonitor: NetworkMonitor(),
            maxConcurrentTranscriptions: maxConcurrent
        )
    }

    /// End-to-end wall-clock time to submit and fully process 20 segments
    /// with up to 5 concurrent slots and an instant mock API.
    /// Establishes a baseline for the actor's scheduling overhead.
    func test_throughput_20Segments_5Concurrent() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                let actor = makeActor(maxConcurrent: 5)
                for i in 0..<20 { await actor.submit(makeSegment(index: i)) }
                var count = 0
                for await _ in actor.results {
                    count += 1
                    if count == 20 { break }
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Same as above but with a single concurrency slot.
    /// Isolates the sequential scheduling + actor-hop cost.
    func test_throughput_20Segments_1Concurrent() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                let actor = makeActor(maxConcurrent: 1)
                for i in 0..<20 { await actor.submit(makeSegment(index: i)) }
                var count = 0
                for await _ in actor.results {
                    count += 1
                    if count == 20 { break }
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Measures the raw cost of calling `submit()` 50 times — the actor-hop
    /// and queue-append overhead, without waiting for results.
    func test_submitThroughput_50Segments() {
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                let actor = makeActor(maxConcurrent: 50)
                for i in 0..<50 { await actor.submit(makeSegment(index: i)) }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }

    /// Throughput with a retry policy configured for zero delay — verifies that
    /// the retry loop itself doesn't add measurable overhead when no retries occur.
    func test_throughput_withZeroDelayRetryPolicy() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, multiplier: 1, maxDelay: 0)
        measure(options: options) {
            let exp = expectation(description: "done")
            Task {
                let actor = makeActor(maxConcurrent: 10, policy: policy)
                for i in 0..<20 { await actor.submit(makeSegment(index: i)) }
                var count = 0
                for await _ in actor.results {
                    count += 1
                    if count == 20 { break }
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 30)
        }
    }
}
