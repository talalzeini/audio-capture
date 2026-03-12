//
//  AppCoordinator.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import SwiftData

@Observable
final class AppCoordinator {
    let modelContainer: ModelContainer
    let recordingViewModel: RecordingViewModel
    let sessionsViewModel: SessionsViewModel

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let networkMonitor = NetworkMonitor()
        let dataManager    = DataManagerActor(modelContainer: modelContainer)

        let transcriptionAPI = FallbackTranscriptionAPI(
            primary:  WhisperTranscriptionAPI(),
            fallback: AppleSpeechTranscriptionAPI(),
            failureThreshold: 5
        )

        let transcriptionActor = TranscriptionActor(
            api: transcriptionAPI,
            networkMonitor: networkMonitor,
            dataManager: dataManager
        )
        let segmentManager = SegmentManagerActor(
            transcriptionActor: transcriptionActor,
            dataManager: dataManager
        )
        let recorder = AudioRecorderActor()

        recordingViewModel = RecordingViewModel(
            recorder: recorder,
            segmentManager: segmentManager,
            transcriptionActor: transcriptionActor,
            networkMonitor: networkMonitor
        )
        sessionsViewModel = SessionsViewModel(dataManager: dataManager)
    }

    static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
            RecordingSession.self,
            Segment.self,
            Transcription.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}

@Observable
final class SessionsViewModel {
    private let dataManager: DataManagerActor

    init(dataManager: DataManagerActor) {
        self.dataManager = dataManager
    }
}
