//
//  Segment.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import SwiftData

@Model
final class Segment {
    @Attribute(.unique)
    var id: UUID

    var startTime: Date
    var duration: TimeInterval
    var audioFileURLString: String

    // Stored as a raw String so SwiftData's #Predicate macro can query it
    // without resolving `.rawValue` at runtime (which causes a fatal crash).
    // The `originalName` attribute tells SwiftData this column was previously
    // called "transcriptionStatus", enabling lightweight migration.
    @Attribute(originalName: "transcriptionStatus")
    var transcriptionStatusRaw: String

    var transcriptionErrorDescription: String?

    var transcriptionStatus: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: transcriptionStatusRaw) ?? .pending }
        set { transcriptionStatusRaw = newValue.rawValue }
    }

    var audioFileURL: URL {
        URL(fileURLWithPath: audioFileURLString)
    }

    var session: RecordingSession?

    @Relationship(deleteRule: .cascade, inverse: \Transcription.segment)
    var transcription: Transcription?

    init(
        id: UUID = UUID(),
        startTime: Date,
        duration: TimeInterval,
        audioFileURL: URL,
        transcriptionStatus: TranscriptionStatus = .pending
    ) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.audioFileURLString = audioFileURL.path
        self.transcriptionStatusRaw = transcriptionStatus.rawValue
    }
}
