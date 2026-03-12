//
//  WhisperTranscriptionAPI.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Foundation

struct WhisperTranscriptionAPI: TranscriptionAPI {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    func transcribe(audioURL: URL) async throws -> String {
        guard
            let apiKey = try KeychainManager.read(forKey: KeychainManager.Keys.openAIAPIKey),
            !apiKey.isEmpty
        else {
            throw WhisperError.missingAPIKey
        }

        let uploadURL = try await convertToM4A(sourceURL: audioURL)
        defer { try? FileManager.default.removeItem(at: uploadURL) }

        let boundary = "AudioCapture-\(UUID().uuidString)"
        let body     = try makeMultipartBody(fileURL: uploadURL, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(WhisperErrorResponse.self, from: data))
                            .map { $0.error.message }
            throw WhisperError.httpError(
                statusCode: httpResponse.statusCode,
                detail: detail ?? String(data: data, encoding: .utf8)
            )
        }

        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }

    // MARK: - Private: .caf → .m4a Conversion

    // Converts .caf to .m4a using AVAssetExportSession. Caller is responsible for
    // cleaning up the returned URL.
    private func convertToM4A(sourceURL: URL) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw WhisperError.audioConversionFailed("Could not create AVAssetExportSession.")
        }

        session.outputURL      = outputURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            let reason = session.error?.localizedDescription ?? "Unknown AVAssetExportSession error"
            throw WhisperError.audioConversionFailed(reason)
        }

        return outputURL
    }

    private func makeMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        let audioData = try Data(contentsOf: fileURL)
        let filename  = fileURL.lastPathComponent
        let crlf      = "\r\n"

        var body = Data()

        body.appendString("--\(boundary)\(crlf)")
        body.appendString("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)")
        body.appendString("whisper-1\(crlf)")

        body.appendString("--\(boundary)\(crlf)")
        body.appendString(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(crlf)"
        )
        body.appendString("Content-Type: audio/m4a\(crlf)\(crlf)")
        body.append(audioData)
        body.appendString(crlf)

        body.appendString("--\(boundary)--\(crlf)")

        return body
    }
}

// MARK: - WhisperError

enum WhisperError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case audioConversionFailed(String)
    case httpError(statusCode: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenAI API key found. Add your key in Settings → OpenAI API Key."
        case .invalidResponse:
            return "Received a non-HTTP response from the Whisper endpoint."
        case .audioConversionFailed(let reason):
            return "Audio conversion to .m4a failed: \(reason)"
        case .httpError(let code, let detail):
            let base = "Whisper API returned HTTP \(code)"
            return detail.map { "\(base): \($0)" } ?? base
        }
    }
}

// MARK: - Response Models

private struct WhisperResponse: Decodable {
    let text: String
}

private struct WhisperErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}

// MARK: - Data helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
