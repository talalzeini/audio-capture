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

    var transcriptionStatus: TranscriptionStatus
    var transcriptionErrorDescription: String?

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
        self.transcriptionStatus = transcriptionStatus
    }
}
