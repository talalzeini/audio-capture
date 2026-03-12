//
//  SessionDetailView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: RecordingSession

    @Query private var segments: [Segment]

    init(session: RecordingSession) {
        self.session = session
        let sessionID = session.id
        _segments = Query(
            filter: #Predicate<Segment> { $0.session?.id == sessionID },
            sort: \Segment.startTime
        )
    }

    var body: some View {
        List {
            summarySection
            segmentsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.sessionName)
        .navigationBarTitleDisplayMode(.large)
    }

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Date") {
                Text(session.createdDate.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Duration") {
                Text(durationText)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Segments") {
                Text("\(segments.count)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Transcribed") {
                let done = segments.filter { $0.transcriptionStatus == .completed }.count
                Text("\(done) / \(segments.count)")
                    .foregroundStyle(
                        done == segments.count && segments.count > 0 ? .green : .secondary
                    )
            }
        }
    }

    @ViewBuilder
    private var segmentsSection: some View {
        Section("Segments") {
            if segments.isEmpty {
                Text("No segments yet")
                    .foregroundStyle(.secondary)
                    .italic()
                    .accessibilityLabel("No segments recorded yet")
            } else {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    SegmentRowView(segment: segment, displayIndex: index + 1)
                }
            }
        }
    }

    // MARK: - Helpers

    private var durationText: String {
        let d = Int(session.totalDuration)
        if d == 0 { return "—" }
        if d >= 3600 { return String(format: "%dh %02dm %02ds", d/3600, (d%3600)/60, d%60) }
        return String(format: "%dm %02ds", d/60, d%60)
    }
}

// MARK: - SegmentRowView

// Shows 1-based index, status badge, and transcript text (or in-progress indicator).
struct SegmentRowView: View {

    let segment: Segment
    let displayIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(alignment: .center) {
                Text("Segment \(displayIndex)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                TranscriptionStatusBadge(status: segment.transcriptionStatus)
            }

            switch segment.transcriptionStatus {
            case .completed:
                if let text = segment.transcription?.text {
                    Text(text)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Transcript unavailable")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                }

            case .inProgress, .pending:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text(
                        segment.transcriptionStatus == .inProgress
                        ? "Transcribing…"
                        : "Queued for transcription"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .italic()
                }

            case .failed:
                Label(
                    segment.transcriptionErrorDescription ?? "Transcription failed",
                    systemImage: "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let statusText = segment.transcriptionStatus.displayLabel
        switch segment.transcriptionStatus {
        case .completed:
            let text = segment.transcription?.text ?? "unavailable"
            return "Segment \(displayIndex), \(statusText): \(text)"
        case .inProgress:
            return "Segment \(displayIndex), currently transcribing"
        case .pending:
            return "Segment \(displayIndex), queued for transcription"
        case .failed:
            let err = segment.transcriptionErrorDescription ?? "unknown error"
            return "Segment \(displayIndex), failed: \(err)"
        }
    }
}
