//
//  AppIntent.swift
//  AudioCaptureWidgets
//
//  Created by Talal El Zeini on 3/11/26.
//

import AppIntents
import Foundation

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription(
        "Begins a new audio recording and transcription session.",
        categoryName: "Recording"
    )

    static let openAppWhenRun: Bool = true

    @Parameter(title: "Session Name", description: "A label for the new recording session.", requestValueDialog: "What should this session be called?")
    var sessionName: String?

    func perform() async throws -> some IntentResult {
        SharedDefaults.pendingSessionName    = sessionName
        SharedDefaults.pendingStartRecording = true
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription(
        "Stops the current audio recording and saves all pending transcriptions.",
        categoryName: "Recording"
    )

    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDefaults.pendingStopRecording = true
        return .result()
    }
}
