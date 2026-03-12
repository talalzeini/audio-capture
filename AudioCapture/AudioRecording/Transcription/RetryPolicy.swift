//
//  RetryPolicy.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let multiplier: Double
    let maxDelay: TimeInterval

    static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        multiplier: 2.0,
        maxDelay: 30.0
    )

    static let aggressive = RetryPolicy(
        maxAttempts: 5,
        baseDelay: 0.5,
        multiplier: 2.0,
        maxDelay: 60.0
    )

    static let noRetry = RetryPolicy(
        maxAttempts: 1,
        baseDelay: 0,
        multiplier: 1,
        maxDelay: 0
    )

    func delay(for attempt: Int) -> TimeInterval {
        guard attempt < maxAttempts else { return 0 }
        let raw = baseDelay * pow(multiplier, Double(attempt - 1))
        return min(raw, maxDelay)
    }
}
