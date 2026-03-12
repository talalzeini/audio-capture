# AudioCapture

An iOS app that records audio in segments and transcribes each one in real time using OpenAI Whisper, with a Live Activity, home screen widget, and Siri support.

## Requirements

- Xcode 16+
- iOS 26.2+
- Swift 6
- iPhone (for Live Activity and widget)

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/talalzeini/AudioCapture.git
cd AudioCapture
open AudioCapture.xcodeproj
```

### 2. Set your Development Team

Select the AudioCapture project in the navigator. For both targets (AudioCapture and AudioCaptureWidgets), go to Signing & Capabilities and set your Team.

### 3. Add your OpenAI API key

The key is stored in Keychain, not in source code. To add it:

1. Build and run the app
2. Go to the Settings tab
3. Paste your key and tap Save

The app falls back to Apple's on-device SFSpeechRecognizer if no key is set or if Whisper fails repeatedly, so it works without one.

### 4. Set up the App Group

The widget and Live Activity share state with the main app through a shared UserDefaults suite. You need to register an App Group in your developer account and update the identifier in the code.

The convention is `group.` + your bundle ID. The default bundle ID is `com.talalzeini.AudioCapture`, so change it to use your own name if needed, then set the group ID to match.

Steps:
1. In Xcode, select the AudioCapture target, go to Signing & Capabilities, click +, and add App Groups
2. Add your identifier, e.g. `group.com.yourname.AudioCapture`
3. Do the same for the AudioCaptureWidgets target using the same identifier
4. Open `AudioCapture/Shared/SharedDefaults.swift` and update the suite name:

```swift
private static let suiteName = "group.com.yourname.AudioCapture"
```

Without this the app still records and transcribes, but the widget and Live Activity won't reflect recording state.

### 5. Add shared files to the widget target

Four files from the main app also need to be in the widget extension. Select each one in Xcode, open the File Inspector (Option+Command+1), and check AudioCaptureWidgets under Target Membership:

- `AudioCapture/Shared/RecordingActivityAttributes.swift`
- `AudioCapture/Shared/SharedDefaults.swift`
- `AudioCapture/AppIntents/StartRecordingIntent.swift`
- `AudioCapture/AppIntents/StopRecordingIntent.swift`

### 6. Check Info.plist

Make sure the main app's Info.plist has:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>AudioCapture needs microphone access to record audio.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>AudioCapture uses on-device speech recognition as a transcription fallback.</string>

<key>NSSupportsLiveActivities</key>
<true/>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

### 7. Build and run

Select an iPhone simulator or device running iOS 26.2+ and press Command+R. The Live Activity and widget only show up on a physical device.

## Architecture

All mutable state lives in Swift actors.

```
RecordingViewModel (@MainActor, @Observable)
    ├── AudioRecorderActor          — AVAudioEngine lifecycle + interruption handling
    │       └── AudioSessionManager — NotificationCenter -> AsyncStream<AudioSessionEvent>
    ├── SegmentManagerActor         — 30-second segment timing + file rotation
    │       └── SegmentedAudioFileWriter
    ├── TranscriptionActor          — parallel dispatch + exponential retry
    │       └── FallbackTranscriptionAPI
    │               ├── WhisperTranscriptionAPI
    │               └── AppleSpeechTranscriptionAPI
    ├── DataManagerActor (@ModelActor)
    └── NetworkMonitor              — NWPathMonitor -> AsyncStream<Bool>
```

Widget and Live Activity state is shared via App Group UserDefaults. Live Activity updates go through ActivityKit.

## Known Issues

- App Group needs to be configured per developer account
- Whisper requires converting .caf to .m4a before upload, which adds a small delay per segment
- Segment audio files are not cleaned up automatically
- No pagination on the sessions list
- Background transcription can be suspended by iOS; pending segments are recovered on next launch

## Documentation

See `AudioCapture_Documentation.docx` for full details on the architecture, audio system design, data model, and known issues.
