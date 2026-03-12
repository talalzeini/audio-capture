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
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            RecordingSession.self,
            Segment.self,
            Transcription.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
