//
//  AudioCaptureWidgetsBundle.swift
//  AudioCaptureWidgets
//
//  Created by Talal El Zeini on 3/11/26.
//

import WidgetKit
import SwiftUI

@main
struct AudioCaptureWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecordingWidget()
        AudioCaptureWidgetsLiveActivity()
    }
}
