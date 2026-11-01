JUMP IN - XCODE STARTER PROJECT

Open and run
1. Extract JumpIn-Xcode-Starter.zip.
2. Move the JumpIn folder to Documents/Developer (or another folder you choose).
3. Double-click JumpIn.xcodeproj inside that folder.
4. In Xcode, choose the JumpIn scheme and My Mac destination.
5. Press Command-R or click the Run triangle.

Requirements
- macOS 14 or later.
- Xcode 15 or later, compatible with your installed macOS.
- Local development uses ad-hoc signing (Sign to Run Locally). A developer
  team is not configured. Distribution signing can be set up later.

Included
- A native SwiftUI macOS application.
- Jump In starter screen with a working coaching-mode selector.
- Bundle identifier: technology.renatus.JumpIn
- Swift 5 language mode, generated Info.plist, app sandbox enabled.
- Shared JumpIn run scheme and asset catalog.
- Git ignore rules. No external packages or database setup required.

This is the initial project setup. Audio capture, headphone routing, AI,
accounts, and backend connections are not implemented. Changing the mode
changes the introductory text only. The app does not request microphone
access or start listening.

Files
JumpIn/JumpInApp.swift       Application entry point and window
JumpIn/ContentView.swift     Starter interface
JumpIn/JumpIn.entitlements  App sandbox setting
JumpIn/Assets.xcassets       Accent color
JumpIn.xcodeproj             Open this in Xcode

Validation
The project structure, object references, XML files, assets, and ZIP archive
were checked during preparation. Victor subsequently supplied a screenshot
of the app running on his Mac. No automated tests or CI are configured yet.

If signing needs attention
Select the blue JumpIn project, select TARGETS > JumpIn, then open Signing &
Capabilities. For local testing, choose Sign to Run Locally if Xcode offers
it. Do not select distribution signing just to run the starter.

Version control
The project is prepared as a Git repository on the main branch. README.md
contains repository setup instructions and development milestones.

Next development milestone
Capture meeting audio and the microphone separately, and prove private
headphone playback during a practice call before adding AI coaching.
