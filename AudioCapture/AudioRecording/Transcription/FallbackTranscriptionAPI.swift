//
//  FallbackTranscriptionAPI.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

actor FallbackTranscriptionAPI: TranscriptionAPI {
    let failureThreshold: Int

    private let primary:  any TranscriptionAPI
    private let fallback: any TranscriptionAPI

    private var consecutiveFailures: Int = 0
    private var usingFallback:       Bool = false

    init(
        primary:  any TranscriptionAPI,
        fallback: any TranscriptionAPI,
        failureThreshold: Int = 5
    ) {
        self.primary          = primary
        self.fallback         = fallback
        self.failureThreshold = failureThreshold
    }

    func transcribe(audioURL: URL) async throws -> String {
        let activeAPI = usingFallback ? fallback : primary
        let apiName   = usingFallback ? "AppleSpeech" : "Whisper"

        do {
            let text = try await activeAPI.transcribe(audioURL: audioURL)
            consecutiveFailures = 0
            if usingFallback {
                usingFallback = false
            }
            return text

        } catch {
            consecutiveFailures += 1

            if !usingFallback && consecutiveFailures >= failureThreshold {
                usingFallback = true
            }

            throw FallbackTranscriptionError.wrapped(
                underlying: error,
                api: apiName,
                consecutiveFailures: consecutiveFailures
            )
        }
    }

    var currentConsecutiveFailures: Int { consecutiveFailures }
    var isUsingFallback: Bool { usingFallback }
}

enum FallbackTranscriptionError: LocalizedError {
    case wrapped(underlying: Error, api: String, consecutiveFailures: Int)

    var errorDescription: String? {
        if case .wrapped(let err, let api, let count) = self {
            return "[\(api)] \(err.localizedDescription) (consecutive failures: \(count))"
        }
        return nil
    }

    var underlyingError: Error? {
        if case .wrapped(let err, _, _) = self { return err }
        return nil
    }
}
