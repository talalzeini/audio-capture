//
//  LiveActivityManager.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import ActivityKit
import WidgetKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var activity: Activity<RecordingActivityAttributes>?

    func startActivity(sessionID: UUID, sessionName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities are disabled or unavailable.")
            return
        }

        endActivity()

        let attributes = RecordingActivityAttributes(sessionID: sessionID)
        let initialState = RecordingActivityAttributes.ContentState(
            state: .recording,
            elapsedSeconds: 0,
            sessionName: sessionName,
            transcribedSegments: 0,
            totalSegments: 0,
            audioLevel: 0
        )

        do {
            let content = ActivityContent(state: initialState, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("[LiveActivityManager] Could not start activity: \(error)")
        }

        SharedDefaults.isRecording        = true
        SharedDefaults.isPaused           = false
        SharedDefaults.isInterrupted      = false
        SharedDefaults.recordingStartDate = Date()
        SharedDefaults.sessionName        = sessionName
        SharedDefaults.transcribedCount   = 0
        SharedDefaults.totalSegments      = 0

        WidgetCenter.shared.reloadAllTimelines()
    }

    func update(
        state: ActivityRecordingState,
        elapsedSeconds: Int,
        transcribedSegments: Int,
        totalSegments: Int,
        audioLevel: Float
    ) {
        guard let activity else { return }

        let newState = RecordingActivityAttributes.ContentState(
            state: state,
            elapsedSeconds: elapsedSeconds,
            sessionName: SharedDefaults.sessionName ?? "Recording",
            transcribedSegments: transcribedSegments,
            totalSegments: totalSegments,
            audioLevel: audioLevel
        )

        Task {
            let content = ActivityContent(state: newState, staleDate: nil)
            await activity.update(content)
        }

        // Mirror to SharedDefaults for the widget timeline.
        SharedDefaults.isRecording      = (state == .recording)
        SharedDefaults.isPaused         = (state == .paused)
        SharedDefaults.isInterrupted    = (state == .interrupted)
        SharedDefaults.transcribedCount = transcribedSegments
        SharedDefaults.totalSegments    = totalSegments

        // Only reload the widget on meaningful state changes to avoid hammering WidgetCenter.
        if state != .recording {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - End

    // Ends the Live Activity with a 5-second stale window, then clears shared state
    // and triggers a widget timeline reload.
    func endActivity() {
        guard let activity else {
            // No active Live Activity, but still clean up shared state.
            SharedDefaults.clearRecordingState()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let lastState = activity.content.state

        let finalContent = RecordingActivityAttributes.ContentState(
            state: .stopped,
            elapsedSeconds: lastState.elapsedSeconds,
            sessionName: lastState.sessionName,
            transcribedSegments: lastState.transcribedSegments,
            totalSegments: lastState.totalSegments,
            audioLevel: 0
        )

        Task {
            let content = ActivityContent(state: finalContent, staleDate: nil)
            // Show "stopped" state for 5 s, then dismiss automatically.
            await activity.end(content, dismissalPolicy: .after(.now + 5))
        }

        self.activity = nil

        SharedDefaults.clearRecordingState()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
