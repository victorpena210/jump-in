# Jump In

A native macOS conversation coach for Upwork client meetings and job interviews.

## Current status

The SwiftUI starter runs on Victor's Mac. The app currently includes a native
window, a coaching-mode selector, and introductory text for each mode.

Audio capture, private headphone playback, transcription, AI advice, accounts,
and backend connections are planned. The current app does not listen or make
network requests.

## Requirements

- macOS 14 or later
- Xcode 15 or later, compatible with the installed macOS version

No external packages, API keys, or database setup are needed for the starter.
Local development uses ad-hoc signing (`Sign to Run Locally`).

## Run locally

1. Clone or download this repository.
2. Open `JumpIn.xcodeproj` in Xcode.
3. Choose the **JumpIn** scheme and **My Mac** destination.
4. Press **Command + R**.

From Terminal, an unsigned build can be checked with:

```sh
xcodebuild -project JumpIn.xcodeproj -scheme JumpIn \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Project files

| Path | Purpose |
| --- | --- |
| `JumpIn/JumpInApp.swift` | Application entry point and window |
| `JumpIn/ContentView.swift` | Starter screen and coaching-mode selection |
| `JumpIn/JumpIn.entitlements` | App sandbox configuration |
| `JumpIn/Assets.xcassets` | Accent color and asset catalog |
| `JumpIn.xcodeproj` | Build settings and shared run scheme |

Bundle identifier: `technology.renatus.JumpIn`.

## Development milestones

1. Select microphone and headphones and validate private playback on a practice call.
2. Capture meeting audio and the local microphone as separate streams.
3. Add live transcription and inspect recognition accuracy.
4. Generate one short coaching suggestion through a keyboard shortcut.
5. Add automatic coaching with configurable frequency, cancellation, and pause controls.

The planned architecture uses Apple's audio frameworks in the Mac client and a
Spring Boot service for AI requests. API credentials belong on the backend.

## Validation

The starter's project structure, file references, XML, and assets were checked
during preparation. Victor subsequently supplied a screenshot of the app
running on his Mac. There is no automated test suite or CI workflow yet.

## Version control

Keep changes focused and describe their outcome in the commit message. Use
`feat:`, `fix:`, `docs:`, and `chore:` prefixes where appropriate. Generated
build output, Xcode user state, and local environment files are excluded by
`.gitignore`.
