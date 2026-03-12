//
//  SessionsListView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI
import SwiftData

struct SessionsListView: View {
    @Query(sort: \RecordingSession.createdDate, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var searchText = ""

    private var filteredSessions: [RecordingSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter {
            $0.sessionName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedSessions: [(key: String, sessions: [RecordingSession])] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: filteredSessions) {
            calendar.startOfDay(for: $0.createdDate)
        }
        return byDay
            .sorted { $0.key > $1.key }
            .map { (key: Self.sectionTitle(for: $0.key), sessions: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else if filteredSessions.isEmpty {
                    noResultsState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Recordings")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search by session name"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(sessions.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(sessions.count) total sessions")
                }
            }
        }
    }

    // MARK: - List

    private var sessionList: some View {
        List {
            ForEach(groupedSessions, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.sessions) { session in
                        NavigationLink(
                            destination: SessionDetailView(session: session)
                        ) {
                            SessionRowView(session: session)
                        }
                        .accessibilityHint("Opens session detail")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { }
        .animation(.easeInOut(duration: 0.2), value: sessions.count)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Recordings Yet",
            systemImage: "mic.slash",
            description: Text("Tap the Record tab to start your first session.")
        )
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private static func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct SessionRowView: View {
    let session: RecordingSession

    private var completedCount: Int {
        session.segments.filter { $0.transcriptionStatus == .completed }.count
    }

    private var totalCount: Int { session.segments.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.sessionName)
                .font(.body.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 14) {
                Label(durationText, systemImage: "clock")
                Label(segmentSummary, systemImage: "waveform")
                if totalCount > 0 {
                    Label(transcriptionSummary, systemImage: "text.bubble")
                        .foregroundStyle(
                            completedCount == totalCount ? .green : .secondary
                        )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.sessionName), " +
            "\(durationText), " +
            "\(segmentSummary), " +
            "\(transcriptionSummary)"
        )
    }

    private var durationText: String {
        let d = Int(session.totalDuration)
        if d == 0 { return "—" }
        if d >= 3600 { return String(format: "%d:%02d:%02d", d/3600, (d%3600)/60, d%60) }
        return String(format: "%d:%02d", d/60, d%60)
    }

    private var segmentSummary: String {
        "\(totalCount) segment\(totalCount == 1 ? "" : "s")"
    }

    private var transcriptionSummary: String {
        "\(completedCount)/\(totalCount) transcribed"
    }
}
