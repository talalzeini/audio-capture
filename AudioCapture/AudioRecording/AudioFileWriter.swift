//
//  AudioFileWriter.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Foundation

final class AudioFileWriter: @unchecked Sendable {
    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private let lock = NSLock()

    nonisolated init() {}

    nonisolated func open(url: URL, inputFormat: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: !inputFormat.isInterleaved
        ]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw AudioCaptureError.fileCreationFailed(error)
        }

        lock.lock()
        defer { lock.unlock() }
        audioFile = file
    }

    nonisolated func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let file = audioFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            assertionFailure("[AudioFileWriter] Buffer write failed: \(error)")
        }
    }

    nonisolated func close() {
        lock.lock()
        defer { lock.unlock() }
        audioFile = nil
    }

    nonisolated var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return audioFile != nil
    }
}
