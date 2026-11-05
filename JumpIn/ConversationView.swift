import SwiftUI

struct ConversationView: View {
    @ObservedObject var coach: ConversationSession
    let audioBusy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Live transcript") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Transcribe this session", isOn: $coach.transcriptionEnabled).disabled(audioBusy)
                    HStack {
                        Picker("Language", selection: $coach.localeIdentifier) {
                            Text("English (US)").tag("en-US")
                            Text("Spanish (Mexico)").tag("es-MX")
                        }.disabled(audioBusy)
                        Button("Speech permissions") { coach.openSpeechSettings() }.buttonStyle(.link)
                    }
                    Toggle("Keep speech recognition on this Mac", isOn: $coach.localOnly).disabled(audioBusy)
                    if !coach.localOnly {
                        Text("Apple Speech may send audio to Apple for recognition.").font(.caption).foregroundStyle(.orange)
                    }
                    Text(coach.status).font(.caption).foregroundStyle(.secondary)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                if coach.lines.isEmpty {
                                    Text("Your conversation will appear here, labeled You and Meeting.")
                                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(coach.lines) { line in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(line.speaker.title).font(.caption.bold())
                                            Text(line.startedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                                            if !line.isFinal { Text("Listening…").font(.caption).foregroundStyle(.secondary) }
                                            if let confidence = line.confidence, confidence < 0.5 {
                                                Text("Check wording").font(.caption).foregroundStyle(.orange)
                                            }
                                        }
                                        Text(line.text).textSelection(.enabled)
                                    }.id(line.id)
                                }
                            }.padding(8)
                        }.frame(height: 200)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: coach.lines) { _, lines in
                            if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    Button("Clear transcript") { coach.clearTranscript() }.disabled(audioBusy || coach.lines.isEmpty)
                }.padding(8)
            }

            GroupBox("Conversation coach") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $coach.mode) {
                        ForEach(CoachingMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(coach.mode.description).foregroundStyle(.secondary).font(.caption)
                    TextField("Optional context: your experience, project, or meeting goal", text: $coach.background, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: coach.background) { _, value in
                            if value.count > 2_000 { coach.background = String(value.prefix(2_000)) }
                        }
                    Toggle("Enable AI coaching", isOn: $coach.aiEnabled)
                    Text("When enabled, a request sends up to three minutes of recent transcript, your context, and the previous suggestion through your backend to OpenAI. Audio is not sent to the coach. API usage may incur charges.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(coach.requesting ? "Thinking…" : "Coach me") { coach.requestSuggestion() }
                            .keyboardShortcut("j", modifiers: [.command, .shift])
                            .buttonStyle(.borderedProminent).disabled(!coach.canRequest)
                        Button("Cancel suggestion") { coach.cancelSuggestion() }
                            .disabled(!coach.requesting && !coach.speaking)
                        Button(coach.paused ? "Resume coaching" : "Pause coaching") { coach.paused.toggle() }
                            .disabled(!coach.aiEnabled)
                    }
                    Text("From your meeting app: Control–Option–Space to ask; Control–Option–Escape to cancel.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle("Automatic suggestions", isOn: $coach.automatic).disabled(!coach.aiEnabled)
                        Picker("At most once every", selection: $coach.interval) {
                            Text("20 seconds").tag(20.0)
                            Text("45 seconds").tag(45.0)
                            Text("90 seconds").tag(90.0)
                        }.frame(maxWidth: 260)
                    }
                    if !coach.suggestion.isEmpty {
                        Text(coach.suggestion).font(.title3).textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let latency = coach.lastLatency {
                        Text(String(format: "Last response: %.1f seconds", latency)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = coach.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                    }
                    DisclosureGroup("Coach settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Backend address", text: $coach.backendURL)
                            SecureField("Backend access token", text: $coach.accessToken)
                            HStack {
                                Button(coach.checkingBackend ? "Checking…" : "Save token & check connection") { coach.saveAndCheckBackend() }
                                    .disabled(coach.checkingBackend)
                                if coach.backendReady { Label("Backend ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            Text("Use your backend access token here. The OpenAI API key belongs only in the backend environment. The access token is saved in this Mac’s Keychain.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }
                }.padding(8)
            }
        }
    }
}
