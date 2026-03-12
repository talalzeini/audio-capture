//
//  SegmentedAudioFileWriter.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Foundation

final class SegmentedAudioFileWriter: @unchecked Sendable {
    private let baseDirectory: URL
    private let format: AVAudioFormat
    private let framesPerSegment: AVAudioFrameCount

    nonisolated(unsafe) private var currentFile: AVAudioFile?
    nonisolated(unsafe) private var currentURL: URL?
    nonisolated(unsafe) private var framesInCurrentSegment: AVAudioFrameCount = 0
    nonisolated(unsafe) private var segmentCounter: Int = 0
    nonisolated(unsafe) private let lock = NSLock()

    nonisolated let completedSegments: AsyncStream<URL>
    nonisolated(unsafe) private let segmentContinuation: AsyncStream<URL>.Continuation

    nonisolated init(
        baseDirectory: URL,
        format: AVAudioFormat,
        segmentDuration: TimeInterval
    ) {
        self.baseDirectory = baseDirectory
        self.format = format
        self.framesPerSegment = AVAudioFrameCount(format.sampleRate * segmentDuration)
        (completedSegments, segmentContinuation) = AsyncStream<URL>.makeStream()
    }

    deinit {
        segmentContinuation.finish()
    }

    nonisolated func openFirstSegment() throws {
        lock.lock()
        defer { lock.unlock() }
        try openNextSegmentLocked()
    }

    nonisolated func finalizeCurrentSegment() -> URL? {
        lock.lock()
        let frames = framesInCurrentSegment
        let url = currentURL
        currentFile = nil
        currentURL = nil
        framesInCurrentSegment = 0
        lock.unlock()
        return frames > 0 ? url : nil
    }

    nonisolated func write(_ buffer: AVAudioPCMBuffer) {
        var completedURLs: [URL] = []

        lock.lock()

        var frameOffset: AVAudioFrameCount = 0
        let totalFrames = buffer.frameLength

        while frameOffset < totalFrames {

            if currentFile == nil {
                do {
                    try openNextSegmentLocked()
                } catch {
                    lock.unlock()
                    assertionFailure("[SegmentedAudioFileWriter] Failed to open segment: \(error)")
                    return
                }
            }

            let remainingInSegment = framesPerSegment - framesInCurrentSegment
            let framesToWrite = min(totalFrames - frameOffset, remainingInSegment)

            do {
                if frameOffset == 0 && framesToWrite == totalFrames {
                    // Fast path: entire buffer fits
                    try currentFile?.write(from: buffer)
                } else if let slice = slice(buffer, from: Int(frameOffset), count: Int(framesToWrite)) {
                    try currentFile?.write(from: slice)
                }
            } catch {
                assertionFailure("[SegmentedAudioFileWriter] Write error: \(error)")
            }

            framesInCurrentSegment += framesToWrite
            frameOffset += framesToWrite

            // Roll over when segment is full
            if framesInCurrentSegment >= framesPerSegment {
                if let url = currentURL { completedURLs.append(url) }
                currentFile = nil
                currentURL = nil
                framesInCurrentSegment = 0
            }
        }

        lock.unlock()

        for url in completedURLs {
            segmentContinuation.yield(url)
        }
    }

    // MARK: - Private Helpers

    // Must be called with lock held.
    private func openNextSegmentLocked() throws {
        let name = String(format: "segment_%04d.caf", segmentCounter)
        let url = baseDirectory.appendingPathComponent(name)
        segmentCounter += 1

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: !format.isInterleaved
        ]

        currentFile = try AVAudioFile(forWriting: url, settings: settings)
        currentURL = url
        framesInCurrentSegment = 0
    }

    // Slices a buffer from start to start + count. Handles all PCM data types.
    private func slice(
        _ source: AVAudioPCMBuffer,
        from start: Int,
        count: Int
    ) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: AVAudioFrameCount(count)
        ) else { return nil }
        dst.frameLength = AVAudioFrameCount(count)

        let channels = Int(source.format.channelCount)

        if let src = source.floatChannelData, let d = dst.floatChannelData {
            for ch in 0..<channels {
                memcpy(d[ch], src[ch].advanced(by: start), count * MemoryLayout<Float>.size)
            }
        } else if let src = source.int32ChannelData, let d = dst.int32ChannelData {
            for ch in 0..<channels {
                memcpy(d[ch], src[ch].advanced(by: start), count * MemoryLayout<Int32>.size)
            }
        } else if let src = source.int16ChannelData, let d = dst.int16ChannelData {
            for ch in 0..<channels {
                memcpy(d[ch], src[ch].advanced(by: start), count * MemoryLayout<Int16>.size)
            }
        }

        return dst
    }
}
