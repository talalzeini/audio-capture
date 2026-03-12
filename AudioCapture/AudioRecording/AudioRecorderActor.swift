//
//  AudioRecorderActor.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Accelerate
import Foundation

actor AudioRecorderActor {
    private let sessionManager: AudioSessionManager
    private let fileWriter: AudioFileWriter

    private var engine: AVAudioEngine

    private(set) var state: RecordingState = .stopped {
        didSet { stateContinuation.yield(state) }
    }

    let stateStream: AsyncStream<RecordingState>
    private let stateContinuation: AsyncStream<RecordingState>.Continuation

    nonisolated let levelStream: AsyncStream<Float>
    nonisolated(unsafe) private let levelContinuation: AsyncStream<Float>.Continuation

    private var currentRecordingURL: URL?
    private var activeSegmentManager: SegmentManagerActor?
    private var activeSegmentWriter: SegmentedAudioFileWriter?

    private var wasInterruptedWhileRecording = false

    init(
        sessionManager: AudioSessionManager = AudioSessionManager(),
        fileWriter: AudioFileWriter = AudioFileWriter()
    ) {
        self.sessionManager = sessionManager
        self.fileWriter = fileWriter
        self.engine = AVAudioEngine()

        (stateStream, stateContinuation) = AsyncStream<RecordingState>.makeStream()
        (levelStream, levelContinuation) = AsyncStream<Float>.makeStream()

        let events = sessionManager.events
        Task { [weak self] in
            guard let self else { return }
            await self.consumeSessionEvents(events)
        }
    }

    deinit {
        stateContinuation.finish()
        levelContinuation.finish()
    }

    func startRecording(to url: URL) async throws {
        guard state == .stopped else {
            throw AudioCaptureError.alreadyRecording
        }

        try await requestMicrophonePermission()
        try sessionManager.configureForRecording()

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)

        try fileWriter.open(url: url, inputFormat: inputFormat)
        currentRecordingURL = url

        installSingleFileTap(format: inputFormat)
        try launchEngine()

        state = .recording
    }

    func startSegmentedRecording(segmentManager: SegmentManagerActor) async throws {
        guard state == .stopped else {
            throw AudioCaptureError.alreadyRecording
        }

        try await requestMicrophonePermission()
        try sessionManager.configureForRecording()

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)

        let writer = try await segmentManager.beginSession(format: inputFormat)
        activeSegmentManager = segmentManager
        activeSegmentWriter = writer

        installSegmentedTap(writer: writer, format: inputFormat)
        try launchEngine()

        state = .recording
    }

    func pauseRecording() throws {
        guard state == .recording else {
            throw AudioCaptureError.recordingNotActive
        }
        engine.pause()
        levelContinuation.yield(0)
        state = .paused
    }

    func resumeRecording() async throws {
        guard state == .paused || state == .interrupted else {
            throw AudioCaptureError.recordingNotActive
        }
        try sessionManager.configureForRecording()
        try launchEngine()
        state = .recording
    }

    @discardableResult
    func stopRecording() async throws -> URL? {
        guard state != .stopped else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let finalisedURL: URL?

        if let manager = activeSegmentManager {
            await manager.endSession()
            activeSegmentManager = nil
            activeSegmentWriter = nil
            fileWriter.close()
            finalisedURL = nil
        } else {
            fileWriter.close()
            finalisedURL = currentRecordingURL
        }

        currentRecordingURL = nil
        wasInterruptedWhileRecording = false
        levelContinuation.yield(0)

        try? sessionManager.deactivate()
        state = .stopped

        return finalisedURL
    }

    private func installSingleFileTap(format: AVAudioFormat) {
        let writer = fileWriter
        let level  = levelContinuation
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.write(buffer)
            level.yield(buffer.rmsLevel)
        }
    }

    private func installSegmentedTap(writer: SegmentedAudioFileWriter, format: AVAudioFormat) {
        let level = levelContinuation
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.write(buffer)
            level.yield(buffer.rmsLevel)
        }
    }

    private func launchEngine() throws {
        do {
            engine.prepare()
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(error)
        }
    }

    private func requestMicrophonePermission() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw AudioCaptureError.permissionDenied }
    }

    private func consumeSessionEvents(_ events: AsyncStream<AudioSessionEvent>) async {
        for await event in events {
            await handleSessionEvent(event)
        }
    }

    private func handleSessionEvent(_ event: AudioSessionEvent) async {
        switch event {
        case .interruptionBegan:
            handleInterruptionBegan()
        case .interruptionEnded(let shouldResume):
            await handleInterruptionEnded(shouldResume: shouldResume)
        case .routeChanged(let reason):
            handleRouteChange(reason: reason)
        case .mediaServicesReset:
            await handleMediaServicesReset()
        }
    }

    private func handleInterruptionBegan() {
        guard state == .recording else { return }
        wasInterruptedWhileRecording = true
        levelContinuation.yield(0)
        state = .interrupted
    }

    private func handleInterruptionEnded(shouldResume: Bool) async {
        guard state == .interrupted else { return }

        if wasInterruptedWhileRecording && shouldResume {
            do {
                try sessionManager.configureForRecording()
                try launchEngine()
                state = .recording
            } catch {
                state = .failed(error as? AudioCaptureError ?? .engineStartFailed(error))
            }
        } else {
            state = .paused
        }

        wasInterruptedWhileRecording = false
    }

    private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .oldDeviceUnavailable:
            guard state == .recording else { return }
            engine.pause()
            state = .paused

        case .newDeviceAvailable:
            break

        case .categoryChange:
            if state == .recording {
                engine.pause()
                state = .paused
            }

        case .override, .wakeFromSleep, .noSuitableRouteForCategory,
             .routeConfigurationChange, .unknown:
            break

        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() async {
        let wasRecording = state == .recording || state == .interrupted
        let savedURL = currentRecordingURL
        let savedSegmentManager = activeSegmentManager

        if let manager = savedSegmentManager {
            await manager.endSession()
        }

        engine = AVAudioEngine()
        fileWriter.close()
        currentRecordingURL = nil
        activeSegmentManager = nil
        activeSegmentWriter = nil
        wasInterruptedWhileRecording = false
        state = .stopped

        guard wasRecording else { return }

        do {
            if let manager = savedSegmentManager {
                try await startSegmentedRecording(segmentManager: manager)
            } else if let url = savedURL {
                try await startRecording(to: url)
            }
        } catch {
            state = .failed(error as? AudioCaptureError ?? .engineStartFailed(error))
        }
    }
}

private extension AVAudioPCMBuffer {
    var rmsLevel: Float {
        guard let data = floatChannelData else { return 0 }
        let frameCount = vDSP_Length(frameLength)
        guard frameCount > 0 else { return 0 }

        var meanSquare: Float = 0
        vDSP_measqv(data[0], 1, &meanSquare, frameCount)
        let rms = sqrt(meanSquare)
        return min(rms * 10.0, 1.0)
    }
}
