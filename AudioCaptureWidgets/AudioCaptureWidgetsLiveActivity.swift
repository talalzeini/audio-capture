//
//  AudioCaptureWidgetsLiveActivity.swift
//  AudioCaptureWidgets
//
//  Created by Talal El Zeini on 3/11/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AudioCaptureWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AudioCaptureWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudioCaptureWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension AudioCaptureWidgetsAttributes {
    fileprivate static var preview: AudioCaptureWidgetsAttributes {
        AudioCaptureWidgetsAttributes(name: "World")
    }
}

extension AudioCaptureWidgetsAttributes.ContentState {
    fileprivate static var smiley: AudioCaptureWidgetsAttributes.ContentState {
        AudioCaptureWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AudioCaptureWidgetsAttributes.ContentState {
         AudioCaptureWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AudioCaptureWidgetsAttributes.preview) {
   AudioCaptureWidgetsLiveActivity()
} contentStates: {
    AudioCaptureWidgetsAttributes.ContentState.smiley
    AudioCaptureWidgetsAttributes.ContentState.starEyes
}
