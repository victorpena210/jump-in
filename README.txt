JUMP IN — macOS conversation coach

Open JumpIn.xcodeproj, select JumpIn / My Mac, and press Command + R.

The app now supports microphone selection, headphone-only test playback,
and separate meeting-app audio capture. Select and confirm your headphones
before starting. Use a practice call to verify the other person cannot hear
the test voice. Keep system-audio sharing off in the meeting app.

See README.md for permissions, the complete setup steps, device-disconnection
checks, and build/test commands.

Live transcription, requested coaching, and automatic coaching are implemented.
See backend/README.md to configure and run the Spring Boot coaching service.
The OpenAI API key stays on the backend; the Mac app uses its access token.
Transcription defaults to on-device recognition. AI coaching sends recent
transcript text only when enabled. The new Mac milestone still needs a device acceptance check. Automated build
and test results are reported in GitHub Actions; see README.md for details.
