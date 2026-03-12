//
//  RecordingView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct RecordingView: View {
    let vm: RecordingViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConnectivityStatusView(isOnline: vm.isOnline)

                ScrollView {
                    VStack(spacing: 28) {
                        stateLabelSection
                        AudioLevelMeterView(level: vm.audioLevel)
                            .padding(.horizontal, 24)
                        elapsedTimerSection
                        if vm.recordingState.isActive {
                            segmentProgressSection
                        }
                        controlsSection

                        if !vm.liveTranscriptions.isEmpty {
                            Divider().padding(.horizontal)
                            liveTranscriptionFeed
                        }
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("AudioCapture")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Recording Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var stateLabelSection: some View {
        HStack(spacing: 8) {
            if vm.recordingState == .recording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(0.9)
                    .scaleEffect(vm.recordingState == .recording ? 1.2 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        value: vm.recordingState == .recording
                    )
            }
            Text(vm.recordingState.displayLabel)
                .font(.headline)
                .foregroundStyle(vm.recordingState.labelColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(vm.recordingState.displayLabel)")
    }

    private var elapsedTimerSection: some View {
        Text(vm.elapsedTimeFormatted)
            .font(.system(size: 62, weight: .thin, design: .monospaced))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.1), value: vm.elapsedSeconds)
            .accessibilityLabel("Elapsed time \(vm.elapsedTimeFormatted)")
    }

    private var segmentProgressSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Segment \(vm.currentSegmentNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vm.secondsUntilNextSegment)s to next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: vm.segmentProgress)
                .tint(.accentColor)
                .animation(.linear(duration: 1), value: vm.segmentProgress)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Segment \(vm.currentSegmentNumber), " +
            "\(vm.secondsUntilNextSegment) seconds until next segment"
        )
    }

    private var controlsSection: some View {
        RecordingControlsView(vm: vm)
    }

    private var liveTranscriptionFeed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live Transcriptions", systemImage: "text.bubble.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(vm.liveTranscriptions) { entry in
                LiveTranscriptionCard(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecordingControlsView: View {
    let vm: RecordingViewModel

    var body: some View {
        HStack(spacing: 36) {
            switch vm.recordingState {
            case .stopped, .failed:
                recordButton

            case .recording:
                pauseButton
                stopButton

            case .paused:
                resumeButton
                stopButton

            case .interrupted:
                interruptedIndicator
                stopButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.recordingState.displayLabel)
    }

    private var recordButton: some View {
        Button {
            Task { await vm.startRecording() }
        } label: {
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 72, height: 72)
                    .shadow(color: .red.opacity(0.4), radius: 8, y: 4)
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .disabled(vm.isLoading)
        .accessibilityLabel("Start recording")
    }

    private var pauseButton: some View {
        ControlButton(
            icon: "pause.fill",
            tint: .yellow,
            size: 56,
            label: "Pause recording"
        ) {
            Task { await vm.pauseRecording() }
        }
    }

    private var resumeButton: some View {
        ControlButton(
            icon: "play.fill",
            tint: .green,
            size: 56,
            label: "Resume recording"
        ) {
            Task { await vm.resumeRecording() }
        }
    }

    private var stopButton: some View {
        ControlButton(
            icon: "stop.fill",
            tint: .red,
            size: 56,
            label: "Stop recording"
        ) {
            Task { await vm.stopRecording() }
        }
        .disabled(vm.isLoading)
    }

    private var interruptedIndicator: some View {
        Label("Interrupted", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Recording interrupted")
    }
}

private struct ControlButton: View {
    let icon: String
    let tint: Color
    let size: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: size, height: size)
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityLabel(label)
    }
}

private struct LiveTranscriptionCard: View {
    let entry: LiveTranscriptionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Segment \(entry.segmentIndex + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Segment \(entry.segmentIndex + 1) transcription: \(entry.text)")
    }
}

private extension RecordingState {
    var displayLabel: String {
        switch self {
        case .stopped:     return "Ready"
        case .recording:   return "Recording"
        case .paused:      return "Paused"
        case .interrupted: return "Interrupted"
        case .failed:      return "Error"
        }
    }

    var labelColor: Color {
        switch self {
        case .recording:   return .red
        case .paused:      return .yellow
        case .interrupted: return .orange
        case .failed:      return .red
        case .stopped:     return .secondary
        }
    }
}
