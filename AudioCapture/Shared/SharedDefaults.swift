//
//  SharedDefaults.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

public enum SharedDefaults {
    private static let suiteName = "group.com.talalzeini.AudioCapture"

    private static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let isRecording        = "sd_isRecording"
        static let isPaused           = "sd_isPaused"
        static let isInterrupted      = "sd_isInterrupted"
        static let recordingStartDate = "sd_recordingStartDate"
        static let sessionName        = "sd_sessionName"
        static let transcribedCount   = "sd_transcribedCount"
        static let totalSegments      = "sd_totalSegments"
        static let pendingStart       = "sd_pendingStartRecording"
        static let pendingStop        = "sd_pendingStopRecording"
        static let pendingSessionName = "sd_pendingSessionName"
    }

    public static var isRecording: Bool {
        get { store.bool(forKey: Key.isRecording) }
        set { store.set(newValue, forKey: Key.isRecording) }
    }

    public static var isPaused: Bool {
        get { store.bool(forKey: Key.isPaused) }
        set { store.set(newValue, forKey: Key.isPaused) }
    }

    public static var isInterrupted: Bool {
        get { store.bool(forKey: Key.isInterrupted) }
        set { store.set(newValue, forKey: Key.isInterrupted) }
    }

    public static var recordingStartDate: Date? {
        get { store.object(forKey: Key.recordingStartDate) as? Date }
        set { store.set(newValue, forKey: Key.recordingStartDate) }
    }

    public static var sessionName: String? {
        get { store.string(forKey: Key.sessionName) }
        set { store.set(newValue, forKey: Key.sessionName) }
    }

    public static var transcribedCount: Int {
        get { store.integer(forKey: Key.transcribedCount) }
        set { store.set(newValue, forKey: Key.transcribedCount) }
    }

    public static var totalSegments: Int {
        get { store.integer(forKey: Key.totalSegments) }
        set { store.set(newValue, forKey: Key.totalSegments) }
    }

    public static var pendingStartRecording: Bool {
        get { store.bool(forKey: Key.pendingStart) }
        set { store.set(newValue, forKey: Key.pendingStart) }
    }

    public static var pendingStopRecording: Bool {
        get { store.bool(forKey: Key.pendingStop) }
        set { store.set(newValue, forKey: Key.pendingStop) }
    }

    public static var pendingSessionName: String? {
        get { store.string(forKey: Key.pendingSessionName) }
        set { store.set(newValue, forKey: Key.pendingSessionName) }
    }

    public static func clearRecordingState() {
        isRecording        = false
        isPaused           = false
        isInterrupted      = false
        recordingStartDate = nil
        sessionName        = nil
        transcribedCount   = 0
        totalSegments      = 0
    }

    public static func clearPendingIntents() {
        pendingStartRecording = false
        pendingStopRecording  = false
        pendingSessionName    = nil
    }
}
