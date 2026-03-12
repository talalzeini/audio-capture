//
//  SegmentManagerActor.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Foundation

actor SegmentManagerActor {
    private let transcriptionActor: TranscriptionActor
    private let dataManager: DataManagerActor?
    let segmentDuration: TimeInterval

    private var writer: SegmentedAudioFileWriter?
    private var segmentIndex: Int = 0
    private var sessionID: UUID?
    private var sessionStartTime: Date?
    private var consumptionTask: Task<Void, Never>?

    init(
        transcriptionActor: TranscriptionActor,
        dataManager: DataManagerActor? = nil,
        segmentDuration: TimeInterval = 30
    ) {
        self.transcriptionActor = transcriptionActor
        self.dataManager = dataManager
        self.segmentDuration = segmentDuration
    }

    func beginSession(format: AVAudioFormat) async throws -> SegmentedAudioFileWriter {
        consumptionTask?.cancel()

        let id = UUID()
        let now = Date()
        sessionID = id
        segmentIndex = 0
        sessionStartTime = now

        let directory = try makeSessionDirectory(id: id)

        if let dataManager {
            let name = Self.defaultSessionName(date: now)
            try await dataManager.createRecordingSession(id: id, name: name, createdDate: now)
        }

        let writer = SegmentedAudioFileWriter(
            baseDirectory: directory,
            format: format,
            segmentDuration: segmentDuration
        )
        try writer.openFirstSegment()
        self.writer = writer

        startConsuming(stream: writer.completedSegments)

        return writer
    }

    func endSession() async {
        defer {
            consumptionTask?.cancel()
            consumptionTask = nil
            writer = nil
            sessionID = nil
            sessionStartTime = nil
        }

        guard let writer else { return }

        if let finalURL = writer.finalizeCurrentSegment() {
            await dispatchSegment(url: finalURL)
        }

        if let dataManager, let id = sessionID, let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            try? await dataManager.updateSessionDuration(id, duration: duration)
        }
    }

    // MARK: - Private

    private func startConsuming(stream: AsyncStream<URL>) {
        consumptionTask = Task { [weak self] in
            for await url in stream {
                guard let self else { return }
                await self.dispatchSegment(url: url)
            }
        }
    }

    // Persists segment to SwiftData, wraps in TranscriptionSegment, forwards to actor.
    private func dispatchSegment(url: URL) async {
        let currentIndex = segmentIndex
        let capturedAt   = Date()
        let segmentID    = UUID()
        segmentIndex += 1

        // Persist before forwarding so a durable record exists even if transcription fails.
        if let dataManager, let id = sessionID, let startTime = sessionStartTime {
            let segmentStart = startTime.addingTimeInterval(
                Double(currentIndex) * segmentDuration
            )
            let request = SegmentSaveRequest(
                id: segmentID,
                sessionID: id,
                startTime: segmentStart,
                duration: segmentDuration,
                audioFileURL: url
            )
            try? await dataManager.saveSegment(request)
        }

        let segment = TranscriptionSegment(
            id: segmentID,
            audioURL: url,
            segmentIndex: currentIndex,
            capturedAt: capturedAt
        )

        await transcriptionActor.submit(segment)
    }

    private func makeSessionDirectory(id: UUID) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioCapture/Sessions/\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func defaultSessionName(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
}
