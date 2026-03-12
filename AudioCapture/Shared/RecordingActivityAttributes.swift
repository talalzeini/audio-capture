//
//  RecordingActivityAttributes.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import ActivityKit
import Foundation

public enum ActivityRecordingState: String, Codable, Hashable, Sendable {
    case recording
    case paused
    case interrupted
    case stopped
}

public struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var state: ActivityRecordingState
        public var elapsedSeconds: Int
        public var sessionName: String
        public var transcribedSegments: Int
        public var totalSegments: Int
        public var audioLevel: Float
    }

    public var sessionID: UUID
}
