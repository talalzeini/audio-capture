//
//  AudioCaptureShortcuts.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AppIntents

struct AudioCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Begin audio capture with \(.applicationName)",
                "Record with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "End recording with \(.applicationName)",
                "Stop audio capture with \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
    }
}
