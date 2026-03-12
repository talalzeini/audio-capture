//
//  RecordingSession.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import SwiftData

@Model
final class RecordingSession {
    @Attribute(.unique)
    var id: UUID

    var createdDate: Date
    var sessionName: String
    var totalDuration: TimeInterval

    @Relationship(deleteRule: .cascade, inverse: \Segment.session)
    var segments: [Segment] = []

    init(
        id: UUID = UUID(),
        createdDate: Date = Date(),
        sessionName: String,
        totalDuration: TimeInterval = 0
    ) {
        self.id = id
        self.createdDate = createdDate
        self.sessionName = sessionName
        self.totalDuration = totalDuration
    }
}
