//
//  AudioSessionManager.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import AVFoundation
import Foundation

extension AVAudioSession.RouteChangeReason: @retroactive Sendable {}

enum AudioSessionEvent: Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason)
    case mediaServicesReset
}

final class AudioSessionManager: @unchecked Sendable {
    nonisolated(unsafe) private let session: AVAudioSession
    nonisolated(unsafe) private let eventContinuation: AsyncStream<AudioSessionEvent>.Continuation

    nonisolated let events: AsyncStream<AudioSessionEvent>

    nonisolated init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        (events, eventContinuation) = AsyncStream<AudioSessionEvent>.makeStream()
        registerForNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        eventContinuation.finish()
    }

    nonisolated func configureForRecording() throws {
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker
                ]
            )
            try session.setPreferredSampleRate(44_100)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            throw AudioCaptureError.sessionConfigurationFailed(error)
        }
    }

    nonisolated func deactivate() throws {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.sessionConfigurationFailed(error)
        }
    }

    nonisolated private func registerForNotifications() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )

        // object: nil because media-services-reset is not tied to a specific session.
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    // MARK: - Notification Handlers

    // All marked nonisolated because NotificationCenter delivers on arbitrary threads
    // and we want to avoid main-actor hops in audio contexts.

    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            eventContinuation.yield(.interruptionBegan)

        case .ended:
            let optionValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            eventContinuation.yield(.interruptionEnded(shouldResume: options.contains(.shouldResume)))

        @unknown default:
            break
        }
    }

    @objc nonisolated private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        eventContinuation.yield(.routeChanged(reason: reason))
    }

    @objc nonisolated private func handleMediaServicesReset() {
        eventContinuation.yield(.mediaServicesReset)
    }
}
