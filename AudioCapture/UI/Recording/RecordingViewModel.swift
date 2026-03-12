//
//  RecordingViewModel.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

struct LiveTranscriptionEntry: Identifiable, Sendable {
    let id: UUID
    let segmentIndex: Int
    let text: String
    let timestamp: Date
}

@Observable
@MainActor
final class RecordingViewModel {
    private(set) var recordingState: RecordingState = .stopped
    private(set) var elapsedSeconds: Int = 0
    private(set) var audioLevel: Float = 0
    private(set) var liveTranscriptions: [LiveTranscriptionEntry] = []
    private(set) var isOnline: Bool = true
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    var segmentProgress: Double {
        let dur = Int(segmentDuration)
        guard dur > 0 else { return 0 }
        return Double(elapsedSeconds % dur) / Double(dur)
    }

    var currentSegmentNumber: Int {
        elapsedSeconds / Int(segmentDuration) + 1
    }

    var secondsUntilNextSegment: Int {
        let dur = Int(segmentDuration)
        guard dur > 0 else { return 0 }
        return dur - (elapsedSeconds % dur)
    }

    var elapsedTimeFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Dependencies

    private let recorder: AudioRecorderActor
    private let segmentManager: SegmentManagerActor
    private let transcriptionActor: TranscriptionActor
    private let networkMonitor: NetworkMonitor
    private let liveActivityManager = LiveActivityManager()

    let segmentDuration: TimeInterval = 30

    private var currentSessionID: UUID = UUID()
    private var currentSessionName: String = ""

    private var timerTask: Task<Void, Never>?

    init(
        recorder: AudioRecorderActor,
        segmentManager: SegmentManagerActor,
        transcriptionActor: TranscriptionActor,
        networkMonitor: NetworkMonitor
    ) {
        self.recorder           = recorder
        self.segmentManager     = segmentManager
        self.transcriptionActor = transcriptionActor
        self.networkMonitor     = networkMonitor

        startObservingState()
        startObservingLevel()
        startObservingTranscriptions()
        startObservingConnectivity()
    }

    func startRecording(sessionName: String? = nil) async {
        guard !isLoading else { return }
        isLoading          = true
        errorMessage       = nil
        elapsedSeconds     = 0
        liveTranscriptions = []

        currentSessionID   = UUID()
        currentSessionName = sessionName ?? Self.generateSessionName()

        do {
            try await recorder.startSegmentedRecording(segmentManager: segmentManager)
            startElapsedTimer()
            liveActivityManager.startActivity(
                sessionID: currentSessionID,
                sessionName: currentSessionName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func pauseRecording() async {
        do {
            try await recorder.pauseRecording()
            timerTask?.cancel()
            liveActivityManager.update(
                state: .paused,
                elapsedSeconds: elapsedSeconds,
                transcribedSegments: liveTranscriptions.count,
                totalSegments: currentSegmentNumber,
                audioLevel: 0
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeRecording() async {
        do {
            try await recorder.resumeRecording()
            startElapsedTimer()
            liveActivityManager.update(
                state: .recording,
                elapsedSeconds: elapsedSeconds,
                transcribedSegments: liveTranscriptions.count,
                totalSegments: currentSegmentNumber,
                audioLevel: audioLevel
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard !isLoading else { return }
        isLoading = true
        timerTask?.cancel()
        do {
            try await recorder.stopRecording()
        } catch {
            errorMessage = error.localizedDescription
        }
        liveActivityManager.endActivity()
        isLoading = false
    }

    private func startElapsedTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.recordingState == .recording {
                    self.elapsedSeconds += 1
                    self.liveActivityManager.update(
                        state: .recording,
                        elapsedSeconds: self.elapsedSeconds,
                        transcribedSegments: self.liveTranscriptions.count,
                        totalSegments: self.currentSegmentNumber,
                        audioLevel: self.audioLevel
                    )
                }
            }
        }
    }

    private func startObservingState() {
        let stream = recorder.stateStream
        Task { @MainActor [weak self] in
            for await state in stream {
                guard let self else { return }
                self.recordingState = state
                if state.isStopped {
                    self.timerTask?.cancel()
                    self.audioLevel = 0
                }
                self.liveActivityManager.update(
                    state: self.activityState(from: state),
                    elapsedSeconds: self.elapsedSeconds,
                    transcribedSegments: self.liveTranscriptions.count,
                    totalSegments: self.currentSegmentNumber,
                    audioLevel: self.audioLevel
                )
            }
        }
    }

    private func startObservingLevel() {
        let stream = recorder.levelStream
        Task { @MainActor [weak self] in
            for await level in stream {
                self?.audioLevel = level
            }
        }
    }

    private func startObservingTranscriptions() {
        let stream = transcriptionActor.results
        Task { @MainActor [weak self] in
            for await result in stream {
                guard let self else { return }
                if case .success(let text, _) = result.outcome {
                    let entry = LiveTranscriptionEntry(
                        id: result.segment.id,
                        segmentIndex: result.segment.segmentIndex,
                        text: text,
                        timestamp: Date()
                    )
                    self.liveTranscriptions.insert(entry, at: 0)

                    self.liveActivityManager.update(
                        state: self.activityState(from: self.recordingState),
                        elapsedSeconds: self.elapsedSeconds,
                        transcribedSegments: self.liveTranscriptions.count,
                        totalSegments: self.currentSegmentNumber,
                        audioLevel: self.audioLevel
                    )
                }
            }
        }
    }

    private func startObservingConnectivity() {
        let stream = networkMonitor.isConnected
        Task { @MainActor [weak self] in
            for await connected in stream {
                self?.isOnline = connected
            }
        }
    }

    // MARK: - Private: Helpers

    private func activityState(from recordingState: RecordingState) -> ActivityRecordingState {
        switch recordingState {
        case .recording:        return .recording
        case .paused:           return .paused
        case .interrupted:      return .interrupted
        case .stopped, .failed: return .stopped
        }
    }

    private static func generateSessionName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, h:mm a"
        return "Session – \(fmt.string(from: Date()))"
    }
}
