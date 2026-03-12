//
//  TranscriptionStatusBadge.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct TranscriptionStatusBadge: View {
    let status: TranscriptionStatus

    var body: some View {
        Label(status.displayLabel, systemImage: status.badgeSystemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.badgeColor.opacity(0.14))
            .foregroundStyle(status.badgeColor)
            .clipShape(Capsule())
            .accessibilityLabel("Transcription status: \(status.displayLabel)")
    }
}

extension TranscriptionStatus {

    var displayLabel: String {
        switch self {
        case .pending:    return "Pending"
        case .inProgress: return "Processing"
        case .completed:  return "Done"
        case .failed:     return "Failed"
        }
    }

    var badgeSystemImage: String {
        switch self {
        case .pending:    return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "exclamationmark.circle.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .pending:    return .secondary
        case .inProgress: return .orange
        case .completed:  return .green
        case .failed:     return .red
        }
    }
}
