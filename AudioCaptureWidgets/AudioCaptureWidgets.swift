//
//  AudioCaptureWidgets.swift
//  AudioCaptureWidgets
//
//  Created by Talal El Zeini on 3/11/26.
//

import WidgetKit
import SwiftUI

struct RecordingEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let isPaused: Bool
    let sessionName: String
    let recordingStartDate: Date?
}

struct RecordingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordingEntry {
        RecordingEntry(date: Date(), isRecording: false, isPaused: false, sessionName: "", recordingStartDate: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordingEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> RecordingEntry {
        RecordingEntry(
            date: Date(),
            isRecording: SharedDefaults.isRecording,
            isPaused: SharedDefaults.isPaused,
            sessionName: SharedDefaults.sessionName ?? "",
            recordingStartDate: SharedDefaults.recordingStartDate
        )
    }
}

struct RecordingWidgetView: View {
    var entry: RecordingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if entry.isRecording {
            activeView
        } else {
            idleView
        }
    }

    var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Not Recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    var activeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                Text(entry.isPaused ? "Paused" : "Recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.sessionName.isEmpty {
                Text(entry.sessionName)
                    .font(.caption2)
                    .lineLimit(1)
            }
            if let start = entry.recordingStartDate {
                Text(start, style: .timer)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RecordingWidget: Widget {
    let kind = "RecordingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecordingTimelineProvider()) { entry in
            RecordingWidgetView(entry: entry)
        }
        .configurationDisplayName("Recording Status")
        .description("Shows the current recording session status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
