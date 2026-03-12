//
//  Transcription.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import Foundation
import SwiftData

@Model
final class Transcription {
    @Attribute(.unique)
    var id: UUID

    var text: String
    var createdAt: Date

    var attemptNumber: Int
    var processingDuration: TimeInterval
    var modelVersion: String?
    var detectedLanguage: String?

    var segment: Segment?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        attemptNumber: Int,
        processingDuration: TimeInterval,
        modelVersion: String? = nil,
        detectedLanguage: String? = nil
    ) {
        self.id                 = id
        self.text               = text
        self.createdAt          = createdAt
        self.attemptNumber      = attemptNumber
        self.processingDuration = processingDuration
        self.modelVersion       = modelVersion
        self.detectedLanguage   = detectedLanguage
    }
}
