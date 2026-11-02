# Jump In

A native macOS conversation coach for Upwork client meetings and job interviews.

## Current status — 0.2.0

The audio practice milestone includes:

- A microphone selector and a live level meter.
- An explicit headphone selector and a local **Test voice** button.
- A separate meter for audio from a selected running meeting app.
- **Start practice**, **Stop**, and Escape to stop.
- Cleanup on device changes, capture errors, window close, and Mac sleep.

Audio is processed in memory on the Mac. This version does not record files,
transcribe, call an AI service, or upload audio. The coaching-mode selector is
retained for the next milestone; it does not change audio capture behavior yet.

## Requirements and run instructions

- macOS 14 or later.
- Xcode 15 or later, compatible with the installed macOS version.
- Wired, USB, or Bluetooth headphones. Built-in speakers, virtual/aggregate
  outputs, AirPlay, HDMI, and DisplayPort outputs are excluded from test playback.
- No API keys, external packages, database, or paid service is required.

```sh
cd ~/Desktop/IdeaProjects/RENATUS/jump-in
git pull --ff-only
open JumpIn.xcodeproj
```

Choose **JumpIn → My Mac**, then press **Command + R**. Local development uses
ad-hoc signing (**Sign to Run Locally**).

## First audio check

1. Connect and wear headphones. Select them in the meeting app as well.
2. Select your microphone and headphones in Jump In. Confirm that the chosen
   output is connected to headphones you are wearing. External speakers may
   appear as external hardware; Jump In cannot identify what is plugged into
   every USB audio interface.
3. Click **Test voice**. You should hear a short sentence only in those headphones.
4. Leave **Meeting app** on **Microphone only**, click **Start practice**, and
   allow microphone access when macOS asks. Speak and watch **Your voice** move.
5. Click **Stop**, open a meeting app, then click **Load apps** in Jump In. macOS
   may ask for **Screen Recording** or **Screen & System Audio Recording** access.
   This is the permission ScreenCaptureKit uses to capture another app's audio;
   Jump In attaches no video output and saves no images.
6. Select the meeting app and click **Start practice**. During a call with a
   willing practice partner, confirm that the two meters respond independently.
7. Click **Test voice** during the call. Ask your partner whether they heard it.
   Keep meeting system-audio sharing off: another app that shares the entire
   system output can retransmit headphone audio. Jump In cannot control that app.
8. Click **Stop**. Both meters should clear and capture should stop.

**Browser meetings:** capture applies to the selected browser application, not
an individual tab. Other tabs playing audio in that browser may also move the
meeting meter. Close or mute those tabs during the test. If the meeting app is
restarted, reload the list and select its new process.

If permission was denied, use the permission links in the app. After changing
screen/audio recording access, quit and reopen Jump In if macOS requests it.
Ad-hoc builds may need permission to be granted again after a rebuild.

## Device and interruption checks

Perform these before using the prototype in an actual meeting:

| Check | Expected behavior |
| --- | --- |
| Unplug headphones or disconnect Bluetooth during Test voice | Playback stops; no new device is selected automatically. Reconnect, select, and confirm before testing again. |
| Remove a headphone plug from a built-in headphone jack | The change in data source/stream terminal invalidates playback even if the hardware ID stays the same. |
| Change output format or switch a Bluetooth headset profile | Stop and require an explicit restart; do not automatically recover through a different route. |
| Change the Mac's default output | Jump In stays bound to the chosen hardware, or stops if its audio engine is reconfigured. It never intentionally follows the new default. |
| Disconnect the selected microphone | Capture stops and the microphone selection clears if unavailable. |
| Press Stop while a permission prompt or startup is pending | Stop becomes Stopping until startup unwinds. A late permission result cannot start a new session. |
| Deny microphone or meeting-audio access | Show a recoverable error; stop any partially started microphone capture. |
| Quit the selected meeting app, sleep the Mac, or close Jump In | Stop capture and playback. |
| Leave a meeting silent | Its meter falls back to Quiet instead of retaining the last level. |
| Start and stop repeatedly | Release capture streams, microphone taps, engine observers, and queued voice buffers each time. |

Hardware behavior, Bluetooth profile transitions, and whether another meeting
app retransmits prompts must be verified on the intended Mac. A successful build
and unit tests do not establish those physical-device results.

## Implementation

- `JumpIn/Audio/AudioDevices.swift`: HAL device enumeration, headphone-output
  filtering, route fingerprints, and hardware change observation.
- `JumpIn/Audio/AudioCapture.swift`: an AVAudioEngine microphone tap and a
  ScreenCaptureKit stream restricted to the selected app. Separate meters;
  neither capture path is monitored through the output.
- `JumpIn/Audio/HeadphonePlayer.swift`: renders AVSpeechSynthesizer buffers in
  memory and plays them through an AVAudioEngine explicitly bound to the chosen
  HAL device. Does not use default-output speech playback or change system defaults.
- `JumpIn/Audio/PracticeSession.swift`: permissions, start/stop lifecycle,
  cancellation, stale-callback rejection, and interruption handling.
- `JumpIn/Audio/AudioLogic.swift`: route validation and meter math.
- `JumpIn/ContentView.swift`: setup and practice UI.

Only microphone access is added to the app sandbox. `NSMicrophoneUsageDescription`
is generated for both build configurations. Bundle identifier remains
`technology.renatus.JumpIn`.

Apple API references:

- [ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Application inclusion filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:including:exceptingwindows:))
- [Speech buffer rendering](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:))

## Validation

On a Mac:

```sh
swift test
xcodebuild -project JumpIn.xcodeproj -scheme JumpIn \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The Swift package compiles the audio implementation and tests output-route
validation, rejected late callbacks, level math, and actual two-channel PCM
buffers without asking for microphone access. GitHub Actions runs those tests
and builds the app on a macOS runner. Complete the manual checks above on a Mac
with headphones; CI has no practice-call partner or physical headphones.

## Next milestones

1. Live transcription with recognition-quality checks.
2. One short coaching suggestion requested by a keyboard shortcut.
3. Automatic coaching with frequency, cancellation, and pause controls.

AI requests will use a Spring Boot backend. API credentials belong on that
backend, not in the Mac app.
