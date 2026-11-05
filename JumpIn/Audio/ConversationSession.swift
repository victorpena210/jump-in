import AVFoundation
import Combine
import AppKit

@MainActor
final class ConversationSession: ObservableObject {
    @Published var transcriptionEnabled = true
    @Published var localOnly = true
    @Published var localeIdentifier = "en-US"
    @Published var mode: CoachingMode = .upwork { didSet { cancelSuggestion() } }
    @Published var background = "" { didSet { cancelSuggestion() } }
    @Published var aiEnabled = false { didSet { if !aiEnabled { cancelSuggestion(); automatic = false } } }
    @Published var automatic = false { didSet { if !automatic { cancelSuggestion() } } }
    @Published var paused = false { didSet { if paused { cancelSuggestion() } } }
    @Published var interval: Double = 45
    @Published var backendURL: String {
        didSet {
            if oldValue != backendURL {
                cancelSuggestion(); backendReady = false; accessToken = ""
                UserDefaults.standard.set(backendURL, forKey: "coachBackendURL")
            }
        }
    }
    @Published var accessToken: String { didSet { backendReady = false; cancelSuggestion() } }
    @Published private(set) var backendReady = false
    @Published private(set) var checkingBackend = false
    @Published private(set) var lines: [TranscriptLine] = []
    @Published private(set) var suggestion = ""
    @Published private(set) var requesting = false
    @Published private(set) var speaking = false
    @Published private(set) var running = false
    @Published var playbackAvailable = true
    @Published private(set) var status = "Start a session to see live transcription."
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastLatency: Double?
    private(set) var microphoneSpeech: SpeechStream?
    private(set) var meetingSpeech: SpeechStream?
    var play: ((String, @escaping (String?) -> Void) -> Void)?
    var stopPlayback: (() -> Void)?
    private let client: CoachingService
    private var ledger = TranscriptLedger()
    private var policy = CoachingPolicy()
    private var task: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private var requestGeneration = UUID()
    private var automaticRequestActive = false
    private var lastSpeech = Date.distantPast
    private var timer: Timer?

    init(client: CoachingService = CoachClient(), loadSettings: Bool = true) {
        self.client = client
        let address = loadSettings ? (UserDefaults.standard.string(forKey: "coachBackendURL") ?? "http://localhost:8080") : "http://localhost:8080"
        backendURL = address
        accessToken = loadSettings ? CoachKeychain.read(for: address) : ""
    }

    var canRequest: Bool {
        running && transcriptionEnabled && aiEnabled && !paused && !requesting && !speaking && playbackAvailable &&
        !accessToken.isEmpty && !ledger.context(now: Date()).isEmpty
    }

    func start(includeMeeting: Bool) async throws {
        stop()
        let token = UUID(); sessionGeneration = token
        ledger.clear(); lines = []; suggestion = ""; lastLatency = nil; errorMessage = nil
        lastSpeech = .distantPast
        policy = CoachingPolicy(lastAttempt: Date())
        paused = false
        guard transcriptionEnabled else { status = "Audio meters only. Transcription is off."; return }
        guard await SpeechStream.requestAccess() else {
            throw AudioFailure.message("Allow Jump In in System Settings → Privacy & Security → Speech Recognition, then restart the session.")
        }
        try Task.checkCancellation()
        guard sessionGeneration == token else { throw CancellationError() }
        let receive: (TranscriptLine) -> Void = { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == token else { return }
                self.receive(line)
            }
        }
        let failed: (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == token else { return }
                self.stop(); self.errorMessage = message; self.status = "Transcription needs attention. Stop and restart the session."
            }
        }
        microphoneSpeech = try SpeechStream(speaker: .you, locale: Locale(identifier: localeIdentifier),
                                            localOnly: localOnly, update: receive, failed: failed)
        do {
            if includeMeeting {
                meetingSpeech = try SpeechStream(speaker: .meeting, locale: Locale(identifier: localeIdentifier),
                                                 localOnly: localOnly, update: receive, failed: failed)
            }
        } catch { stop(); throw error }
        status = localOnly ? "Transcribing on this Mac…" : "Transcribing with Apple Speech; audio may be processed by Apple."
    }

    func audioDidStart() {
        guard transcriptionEnabled else { return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func stop() {
        sessionGeneration = UUID(); running = false
        timer?.invalidate(); timer = nil
        microphoneSpeech?.stop(); microphoneSpeech = nil
        meetingSpeech?.stop(); meetingSpeech = nil
        cancelSuggestion()
        status = "Session stopped. Transcript stays here until cleared or a new session starts."
    }

    func noteSpeech(level: Double) {
        if level > 0.08 {
            lastSpeech = Date()
            if automaticRequestActive { cancelSuggestion() }
        }
    }

    func receive(_ line: TranscriptLine) {
        ledger.update(line); lines = ledger.lines
    }

    func clearTranscript() {
        // A running recognizer could repopulate a cleared partial segment.
        guard !running else { return }
        cancelSuggestion(); ledger.clear(); lines = []; suggestion = ""
    }

    func cancelSuggestion() {
        requestGeneration = UUID(); task?.cancel(); task = nil
        requesting = false; speaking = false; stopPlayback?()
        automaticRequestActive = false
    }

    func requestSuggestion(automaticRequest: Bool = false) {
        guard canRequest else { return }
        do {
            let endpoint = try BackendAddress.validate(backendURL)
            let now = Date()
            let turns = ledger.context(now: now)
            let request = CoachRequest(mode: mode, context: String(background.prefix(2_000)),
                                       turns: turns, previousSuggestion: String(suggestion.prefix(500)))
            policy.attempted(now: now, fingerprint: Self.fingerprint(turns))
            errorMessage = nil; requesting = true
            automaticRequestActive = automaticRequest
            let token = UUID(); requestGeneration = token
            let credential = accessToken
            let lastSuggestion = suggestion
            task = Task { [weak self, client] in
                do {
                    let text = try await client.suggest(request, baseURL: endpoint, token: credential)
                    guard let self, !Task.isCancelled, self.requestGeneration == token,
                          self.running, self.aiEnabled, !self.paused else { return }
                    self.requesting = false; self.backendReady = true
                    self.lastLatency = Date().timeIntervalSince(now)
                    if automaticRequest && text.caseInsensitiveCompare(lastSuggestion) == .orderedSame {
                        self.automaticRequestActive = false; return
                    }
                    self.suggestion = text
                    // A delayed automatic reply is still visible, but must not talk over a new turn.
                    if automaticRequest && Date().timeIntervalSince(self.lastSpeech) < 1.5 {
                        self.automaticRequestActive = false; return
                    }
                    self.speaking = true
                    self.play?(text) { [weak self] message in
                        guard let self, self.requestGeneration == token else { return }
                        self.speaking = false
                        self.automaticRequestActive = false
                        if let message { self.errorMessage = message }
                    }
                } catch {
                    guard let self, !Task.isCancelled, self.requestGeneration == token else { return }
                    self.requesting = false
                    self.automaticRequestActive = false
                    self.errorMessage = error.localizedDescription
                    if automaticRequest { self.paused = true }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveAndCheckBackend() {
        checkTask?.cancel()
        do {
            let endpoint = try BackendAddress.validate(backendURL)
            let address = backendURL; let credential = accessToken
            try CoachKeychain.save(credential, for: address)
            checkingBackend = true; errorMessage = nil
            checkTask = Task { [weak self, client] in
                do {
                    try await client.check(baseURL: endpoint, token: credential)
                    guard let self, !Task.isCancelled else { return }
                    self.checkingBackend = false
                    guard self.backendURL == address, self.accessToken == credential else { return }
                    self.backendReady = true
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    self.checkingBackend = false
                    guard self.backendURL == address, self.accessToken == credential else { return }
                    self.backendReady = false; self.errorMessage = error.localizedDescription
                }
            }
        } catch { checkingBackend = false; errorMessage = error.localizedDescription }
    }

    func openSpeechSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    private func tick() {
        let now = Date()
        let fingerprint = Self.fingerprint(ledger.context(now: now))
        if policy.shouldRequest(now: now, interval: interval, running: running, enabled: automatic && aiEnabled,
                                paused: paused, busy: requesting || speaking, lastSpeech: lastSpeech, fingerprint: fingerprint) {
            requestSuggestion(automaticRequest: true)
        }
    }
    private static func fingerprint(_ turns: [CoachTurn]) -> String {
        turns.map { "\($0.speaker):\($0.text)" }.joined(separator: "\n")
    }
}
