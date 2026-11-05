import SwiftUI

struct ContentView: View {
    @StateObject private var audio = PracticeSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 60, height: 60)
                        .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jump In").font(.largeTitle.bold())
                        Text("Your conversation coach").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(audio.state == .running ? "Listening" : "Audio setup",
                          systemImage: audio.state == .running ? "waveform.circle.fill" : "headphones")
                        .foregroundStyle(audio.state == .running ? Color.teal : Color.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Microphone", selection: $audio.microphoneUID) {
                            Text("Select a microphone").tag("")
                            ForEach(audio.microphones) { Text($0.name).tag($0.uid) }
                        }
                        .disabled(audio.isBusy)
                        AudioMeter(title: "Your voice", level: audio.microphoneLevel)
                    }.padding(8)
                } label: { Label("1. Your microphone", systemImage: "mic") }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Headphones", selection: $audio.headphoneUID) {
                            Text("Select your headphones").tag("")
                            ForEach(audio.headphones) { Text($0.name).tag($0.uid) }
                        }
                        .disabled(audio.isBusy || audio.isTestingVoice)
                        Toggle("This output is connected to headphones I’m wearing", isOn: $audio.headphonesConfirmed)
                            .disabled(audio.headphoneUID.isEmpty || audio.isBusy || audio.isTestingVoice)
                        HStack {
                            Button(audio.isTestingVoice ? "Stop test voice" : "Test voice") {
                                if audio.isTestingVoice { audio.stopVoice() } else { audio.testVoice() }
                            }
                            .disabled(!audio.isTestingVoice && !audio.canTestVoice)
                            Button("Refresh devices") { audio.refreshDevices() }.disabled(audio.isBusy)
                        }
                        Text("Built-in speakers and virtual outputs are excluded. Playback stops if the selected connection changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                } label: { Label("2. Private playback", systemImage: "headphones") }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Meeting app", selection: $audio.meetingPID) {
                                Text("Microphone only — test my setup").tag(Int32(0))
                                ForEach(audio.applications) { Text($0.name).tag($0.id) }
                            }
                            Button(audio.isLoadingApplications ? "Loading…" : "Load apps") { audio.loadApplications() }
                                .disabled(audio.isLoadingApplications)
                        }.disabled(audio.isBusy)
                        AudioMeter(title: "Meeting audio", level: audio.meetingLevel)
                        Text("Open your meeting app, click Load apps, then choose it here. macOS may ask for Screen Recording or Screen & System Audio Recording access. Jump In receives audio only.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("For browser meetings, audio from other tabs in that browser may also be captured. Use headphones for the meeting, and leave system-audio sharing off while testing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                } label: { Label("3. The other person’s voice", systemImage: "person.wave.2") }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(audio.state == .starting ? "Starting…" : "Start practice") { audio.startPractice() }
                            .buttonStyle(.borderedProminent).tint(.teal)
                            .disabled(!audio.canStart)
                        Button(audio.state == .stopping ? "Stopping…" : "Stop") { audio.stopPractice() }
                            .keyboardShortcut(.cancelAction)
                            .disabled((!audio.isBusy && !audio.isTestingVoice) || audio.state == .stopping)
                        if audio.state == .starting || audio.state == .stopping {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text(audio.status).font(.callout).accessibilityAddTraits(.updatesFrequently)
                    if let error = audio.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Microphone permissions") { audio.openPrivacySettings(microphone: true) }
                        Button("Meeting-audio permissions") { audio.openPrivacySettings(microphone: false) }
                    }.buttonStyle(.link).font(.caption)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                ConversationView(coach: audio.conversation, audioBusy: audio.isBusy)

                Text("Use with participants who know you’re using a conversation assistant. Audio and transcripts are not saved to files. Coach settings control whether speech or transcript text leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(28)
        }
        .frame(minWidth: 620, minHeight: 600)
        .onAppear { audio.activate() }
        .onDisappear { audio.deactivate() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            audio.deactivate()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            audio.stopPractice(message: "Audio stopped because the Mac went to sleep. Start again when ready.")
        }
    }
}

private struct AudioMeter: View {
    let title: String
    let level: Double
    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 110, alignment: .leading)
            ProgressView(value: level, total: 1).tint(.teal)
            Text(level > 0.02 ? "Signal" : "Quiet")
                .font(.caption).foregroundStyle(.secondary).frame(width: 42)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(level > 0.02 ? "Audio detected" : "Quiet")
    }
}

#Preview { ContentView() }
