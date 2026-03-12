//
//  AudioCaptureWidgetsLiveActivity.swift
//  AudioCaptureWidgets
//
//  Created by Talal El Zeini on 3/11/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AudioCaptureWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.state == .recording ? "mic.fill" : "mic.slash.fill")
                            .foregroundStyle(context.state.state == .recording ? .red : .orange)
                        Text(context.state.sessionName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...(Date().addingTimeInterval(Double(context.state.elapsedSeconds))), countsDown: false)
                        .font(.caption.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.state == .recording ? "Recording" : context.state.state == .paused ? "Paused" : "Stopped")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.transcribedSegments)/\(context.state.totalSegments) segments transcribed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        AudioLevelBar(level: context.state.audioLevel)
                            .frame(width: 60, height: 8)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } compactTrailing: {
                Text(timerInterval: Date()...(Date().addingTimeInterval(Double(context.state.elapsedSeconds))), countsDown: false)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 40)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
            .widgetURL(URL(string: "audiocapture://recording"))
            .keylineTint(.red)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RecordingActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.state == .recording ? "mic.fill" : "mic.slash.fill")
                .font(.title2)
                .foregroundStyle(context.state.state == .recording ? .red : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.sessionName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(context.state.state == .recording ? "Recording" : context.state.state == .paused ? "Paused" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(context.state.transcribedSegments)/\(context.state.totalSegments) transcribed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: Date()...(Date().addingTimeInterval(Double(context.state.elapsedSeconds))), countsDown: false)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.white)
                AudioLevelBar(level: context.state.audioLevel)
                    .frame(width: 50, height: 6)
            }
        }
        .padding()
    }
}

private struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(Color.red)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
    }
}
