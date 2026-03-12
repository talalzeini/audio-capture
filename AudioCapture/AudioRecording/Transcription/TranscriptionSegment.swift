//
//  TranscriptionSegment.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

struct TranscriptionSegment: Sendable, Identifiable {
    let id: UUID
    let audioURL: URL
    let segmentIndex: Int
    let capturedAt: Date
}

struct TranscriptionResult: Sendable {
    let segment: TranscriptionSegment
    let outcome: Outcome

    enum Outcome: Sendable {
        case success(transcript: String, attemptNumber: Int)
        case failure(errorDescription: String, totalAttempts: Int)
    }
}

extension TranscriptionResult {
    nonisolated var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    nonisolated var transcript: String? {
        if case .success(let text, _) = outcome { return text }
        return nil
    }
}
