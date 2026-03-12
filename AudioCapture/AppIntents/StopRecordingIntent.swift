//
//  StopRecordingIntent.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AppIntents
import Foundation

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
