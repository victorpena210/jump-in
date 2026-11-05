# Jump In

A native macOS conversation coach for Upwork client meetings and job interviews.

## Current status — 0.3.0

The conversation-coaching implementation includes:

- Separate microphone and meeting-app capture, device selectors, and live meters.
- Live transcript labeled **You** and **Meeting**, with partial updates, language
  selection, and a warning on low-confidence final text.
- On-device recognition by default, with an explicit Apple speech-service option
  when local recognition is unavailable. Transcription can also be turned off.
- One short coaching suggestion requested with **Coach me** or a keyboard shortcut.
- Upwork-client and interview coaching modes, plus optional meeting context.
- Automatic suggestions at most every 20, 45, or 90 seconds, after a pause in
  speech. Pause, resume, cancel, duplicate suppression, and late-reply rejection.
- Private spoken suggestions bound to the selected headphones, with the existing
  output-device checks preserved.
- A Java 17 / Spring Boot backend with token authentication, request limits,
  provider timeouts, and backend-only API credentials.

Audio and transcript text are held in memory, not saved to files. Transcription
alone does not call the coaching backend. Enabling AI coaching allows recent
transcript text and your meeting context to be sent through your backend to
OpenAI. See [backend setup and data handling](backend/README.md).

The audio foundation was verified by the user. The new Mac transcription and
coaching code still requires a macOS build/test run and a device acceptance test.
The backend builds and its 10 automated tests pass locally using a fake AI
provider; real provider access has not been tested without an API key.

## Requirements and run instructions

- macOS 14 or later.
- Xcode 15 or later, compatible with the installed macOS version.
- Wired, USB, or Bluetooth headphones. Built-in speakers, virtual/aggregate
  outputs, AirPlay, HDMI, and DisplayPort outputs are excluded from test playback.
- Audio meters and Apple Speech transcription do not need an OpenAI key.
- AI coaching needs the [backend](backend/README.md), its access token, and a
  backend OpenAI API key. No database is required.

```sh
cd ~/Desktop/IdeaProjects/RENATUS/jump-in
git pull --ff-only
open JumpIn.xcodeproj
```

Choose **JumpIn → My Mac**, then press **Command + R**. Local development uses
ad-hoc signing (**Sign to Run Locally**).

## Use transcription and coaching

1. Keep **Transcribe this session** enabled and choose a recognition language.
   Allow microphone, meeting-audio, and Speech Recognition permissions when asked.
2. Start the session. Speak and verify that the **You** transcript is accurate.
   During a practice call, confirm the **Meeting** transcript follows the other
   person. A browser captures the whole browser app, including other audible tabs.
3. If local speech recognition is unavailable, configure the language in macOS
   Dictation settings or explicitly turn off **Keep speech recognition on this Mac**.
   The latter allows Apple to process audio. There is no silent network fallback.
4. Follow [backend setup](backend/README.md), paste its access token in **Coach
   settings**, and check the connection. Do not enter an OpenAI key into the app.
5. Choose a coaching mode and optionally describe your experience or meeting goal.
   Enable **AI coaching**, then click **Coach me** after a few sentences.
6. While your meeting app is in front, press **Control–Option–Space** to ask for a
   suggestion and **Control–Option–Escape** to cancel. **Command–Shift–J** also
   works while Jump In is focused. Shortcut conflicts are shown in the audio status.
7. Enable **Automatic suggestions** when ready. They wait for at least 1.5 seconds
   without detected speech, use only changed conversation, and respect the chosen
   interval. New speech cancels a pending or playing automatic suggestion. A failed
   automatic request pauses coaching until you resume it.
8. **Pause coaching** keeps transcription running. **Stop** stops capture,
   transcription, pending coaching, and playback. Stopping retains the displayed
   transcript in memory; clear it explicitly, start a new session, or quit to remove it.

Use the recognition language that matches the conversation. Speaker labels indicate
which audio source produced the text; people within the meeting app are not
individually identified. Recognition quality, simultaneous streams, and latency
must be checked on the intended Mac. Recognition rotates at silence or after 45
seconds to support longer conversations; briefly overlapping speech can still be
misrecognized. The app shows the last AI-response time.

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
- `JumpIn/Audio/LiveSpeech.swift`: independent bounded recognition streams.
- `JumpIn/Audio/Conversation.swift`: transcript limits and automatic-coaching policy.
- `JumpIn/Audio/ConversationSession.swift`: request lifecycle, cancellation, and playback.
- `JumpIn/Audio/CoachClient.swift`: authenticated backend client and Keychain storage.
- `JumpIn/Audio/CoachShortcut.swift`: global ask/cancel shortcuts.
- `JumpIn/ContentView.swift` and `ConversationView.swift`: setup and coaching UI.
- `backend/`: Spring Boot coaching API, local configuration scripts, and Docker build.

The sandbox enables microphone, speech recognition, and outgoing network access.
Microphone and Speech Recognition purpose strings are generated for both build
configurations; the Info.plist permits local backend networking. Bundle identifier remains
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

## Acceptance checks for the new milestone

- Read a short paragraph and compare both transcript sources with what was said.
- Run a conversation longer than one minute and confirm new segments keep appearing.
- Test a manual prompt, pause/resume, cancellation while thinking, and both global shortcuts.
- Enable automatic coaching and confirm it stays quiet during speech and respects the interval.
- Stop or disconnect headphones while waiting for a response; no late speech may play.
- Stop the backend or use a wrong access token and verify a recoverable error.
- Recheck headphone-only output with a practice partner after enabling generated speech.

The GitHub workflows build the Mac app and run Swift tests, and separately build
and test the Java backend. CI does not prove speech recognition, headphone routing,
or actual model access on the user's hardware/account.
