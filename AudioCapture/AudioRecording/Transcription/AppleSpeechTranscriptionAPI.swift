//
//  AppleSpeechTranscriptionAPI.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import Speech

struct AppleSpeechTranscriptionAPI: TranscriptionAPI {
    func transcribe(audioURL: URL) async throws -> String {
        try await requestAuthorizationIfNeeded()

        let locale = SFSpeechRecognizer.supportedLocales().contains(Locale.current)
            ? Locale.current
            : Locale(identifier: "en-US")

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppleSpeechError.recognizerUnavailable
        }

        guard recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else { return }

                if result.isFinal {
                    hasResumed = true
                    let text = result.bestTranscription.formattedString
                    if text.isEmpty {
                        continuation.resume(throwing: AppleSpeechError.emptyTranscription)
                    } else {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current != .authorized else { return }

        guard current == .notDetermined else {
            throw AppleSpeechError.permissionDenied
        }

        let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard granted else {
            throw AppleSpeechError.permissionDenied
        }
    }
}

// MARK: - AppleSpeechError

enum AppleSpeechError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied. Enable it in Settings → Privacy."
        case .recognizerUnavailable:
            return "On-device speech recognizer is not available for the current locale."
        case .emptyTranscription:
            return "Speech recognizer returned an empty transcription."
        }
    }
}
