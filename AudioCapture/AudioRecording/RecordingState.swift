//
//  RecordingState.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

public enum RecordingState: Sendable {
    case stopped
    case recording
    case paused
    case interrupted
    case failed(AudioCaptureError)
}

extension RecordingState: Equatable {
    public static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped),
             (.recording, .recording),
             (.paused, .paused),
             (.interrupted, .interrupted),
             (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

extension RecordingState {
    public nonisolated var isActive: Bool { self == .recording }
    public nonisolated var isStopped: Bool { self == .stopped }
}

extension RecordingState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stopped:       return "stopped"
        case .recording:     return "recording"
        case .paused:        return "paused"
        case .interrupted:   return "interrupted"
        case .failed(let e): return "failed(\(e.localizedDescription))"
        }
    }
}
