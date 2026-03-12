//
//  NetworkMonitor.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import Network

final class NetworkMonitor: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    nonisolated(unsafe) private var _isCurrentlyConnected: Bool = true
    nonisolated(unsafe) private let lock = NSLock()

    nonisolated var isCurrentlyConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCurrentlyConnected
    }

    nonisolated let isConnected: AsyncStream<Bool>
    nonisolated(unsafe) private let continuation: AsyncStream<Bool>.Continuation

    nonisolated init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.audiocapture.networkmonitor", qos: .utility)
        (isConnected, continuation) = AsyncStream<Bool>.makeStream()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            self.lock.lock()
            self._isCurrentlyConnected = connected
            self.lock.unlock()
            self.continuation.yield(connected)
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
