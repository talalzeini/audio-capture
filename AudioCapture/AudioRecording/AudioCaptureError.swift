//
//  AudioCaptureError.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

public enum AudioCaptureError: Error, Sendable {
    case permissionDenied
    case sessionConfigurationFailed(Error)
    case engineStartFailed(Error)
    case fileCreationFailed(Error)
    case recordingNotActive
    case alreadyRecording
}

extension AudioCaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Please enable it in Settings → Privacy → Microphone."
        case .sessionConfigurationFailed(let underlying):
            return "Failed to configure the audio session: \(underlying.localizedDescription)"
        case .engineStartFailed(let underlying):
            return "The audio engine could not start: \(underlying.localizedDescription)"
        case .fileCreationFailed(let underlying):
            return "Failed to create the recording file: \(underlying.localizedDescription)"
        case .recordingNotActive:
            return "No active recording. Call startRecording() first."
        case .alreadyRecording:
            return "A recording is already in progress."
        }
    }
}
