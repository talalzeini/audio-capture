//
//  AudioCaptureApp.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI
import SwiftData

@main
struct AudioCaptureApp: App {
    private let coordinator: AppCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = AppCoordinator.makeModelContainer()
        coordinator = AppCoordinator(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .modelContainer(coordinator.modelContainer)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                handlePendingIntents()
            }
        }
    }

    @MainActor
    private func handlePendingIntents() {
        let vm = coordinator.recordingViewModel

        if SharedDefaults.pendingStartRecording {
            let name = SharedDefaults.pendingSessionName
            SharedDefaults.clearPendingIntents()
            Task { @MainActor in
                await vm.startRecording(sessionName: name)
            }
        } else if SharedDefaults.pendingStopRecording {
            SharedDefaults.clearPendingIntents()
            Task { @MainActor in
                await vm.stopRecording()
            }
        }
    }
}
