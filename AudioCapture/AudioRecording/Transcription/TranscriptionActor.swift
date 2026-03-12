//
//  TranscriptionActor.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

protocol TranscriptionAPI: Sendable {
    func transcribe(audioURL: URL) async throws -> String
}

actor TranscriptionActor {
    private let api: any TranscriptionAPI
    private let retryPolicy: RetryPolicy
    private let networkMonitor: NetworkMonitor
    private let maxConcurrentTranscriptions: Int
    private let dataManager: DataManagerActor?

    private var pendingQueue: [TranscriptionSegment] = []
    private var activeTranscriptionCount: Int = 0

    let results: AsyncStream<TranscriptionResult>
    private let resultContinuation: AsyncStream<TranscriptionResult>.Continuation

    init(
        api: any TranscriptionAPI,
        retryPolicy: RetryPolicy = .default,
        networkMonitor: NetworkMonitor,
        maxConcurrentTranscriptions: Int = 3,
        dataManager: DataManagerActor? = nil
    ) {
        self.api = api
        self.retryPolicy = retryPolicy
        self.networkMonitor = networkMonitor
        self.maxConcurrentTranscriptions = maxConcurrentTranscriptions
        self.dataManager = dataManager

        (results, resultContinuation) = AsyncStream<TranscriptionResult>.makeStream()

        let connectivityStream = networkMonitor.isConnected
        Task { [weak self] in
            for await isConnected in connectivityStream where isConnected {
                await self?.drainQueue()
            }
        }
    }

    deinit {
        resultContinuation.finish()
    }

    func submit(_ segment: TranscriptionSegment) {
        pendingQueue.append(segment)
        drainQueue()
    }

    var pendingSegmentCount: Int { pendingQueue.count }
    var activeCount: Int { activeTranscriptionCount }

    private func drainQueue() {
        while activeTranscriptionCount < maxConcurrentTranscriptions
                && !pendingQueue.isEmpty
                && networkMonitor.isCurrentlyConnected {
            let segment = pendingQueue.removeFirst()
            startTranscription(for: segment)
        }
    }

    private func startTranscription(for segment: TranscriptionSegment) {
        activeTranscriptionCount += 1

        let api = self.api
        let policy = self.retryPolicy

        Task { [weak self] in
            let result = await TranscriptionActor.transcribeWithRetry(
                segment: segment,
                api: api,
                retryPolicy: policy
            )
            await self?.handleResult(result)
        }
    }

    private func handleResult(_ result: TranscriptionResult) async {
        activeTranscriptionCount -= 1

        if let dataManager {
            await persistResult(result, dataManager: dataManager)
        }

        resultContinuation.yield(result)
        drainQueue()
    }

    private func persistResult(_ result: TranscriptionResult, dataManager: DataManagerActor) async {
        let segmentID = result.segment.id

        switch result.outcome {
        case .success(let transcript, let attempt):
            let metadata = ProcessingMetadata(
                attemptNumber: attempt,
                processingDuration: 0
            )
            try? await dataManager.saveTranscription(
                for: segmentID,
                text: transcript,
                metadata: metadata
            )

        case .failure(let errorDescription, _):
            try? await dataManager.updateSegmentStatus(
                segmentID,
                status: .failed,
                errorDescription: errorDescription
            )
        }
    }

    private static func transcribeWithRetry(
        segment: TranscriptionSegment,
        api: any TranscriptionAPI,
        retryPolicy: RetryPolicy
    ) async -> TranscriptionResult {

        var lastErrorDescription = "Unknown error"

        for attempt in 1...max(retryPolicy.maxAttempts, 1) {

            guard !Task.isCancelled else {
                return TranscriptionResult(
                    segment: segment,
                    outcome: .failure(
                        errorDescription: "Cancelled after \(attempt - 1) attempt(s).",
                        totalAttempts: attempt - 1
                    )
                )
            }

            do {
                let transcript = try await api.transcribe(audioURL: segment.audioURL)
                return TranscriptionResult(
                    segment: segment,
                    outcome: .success(transcript: transcript, attemptNumber: attempt)
                )
            } catch {
                lastErrorDescription = error.localizedDescription

                guard attempt < retryPolicy.maxAttempts else { break }

                let delay = retryPolicy.delay(for: attempt)
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        return TranscriptionResult(
            segment: segment,
            outcome: .failure(
                errorDescription: lastErrorDescription,
                totalAttempts: retryPolicy.maxAttempts
            )
        )
    }
}
