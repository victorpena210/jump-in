import AppKit
import AVFoundation
import Combine

@MainActor
final class PracticeSession: ObservableObject {
    enum State: Equatable { case idle, starting, running, stopping }

    @Published private(set) var devices: [AudioDevice] = []
    @Published var microphoneUID = "" { didSet { if oldValue != microphoneUID { selectionChanged() } } }
    @Published var headphoneUID = "" {
        didSet {
            if oldValue != headphoneUID {
                headphonesConfirmed = false
                selectionChanged()
            }
        }
    }
    @Published var headphonesConfirmed = false {
        didSet { if !headphonesConfirmed && oldValue { selectionChanged() } }
    }
    @Published private(set) var applications: [MeetingApplication] = []
    @Published var meetingPID: Int32 = 0 { didSet { if oldValue != meetingPID { selectionChanged() } } }
    @Published private(set) var isLoadingApplications = false
    @Published private(set) var state: State = .idle
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var meetingLevel = 0.0
    @Published private(set) var isTestingVoice = false
    @Published private(set) var status = "Choose your microphone and headphones to begin."
    @Published private(set) var errorMessage: String?

    var microphones: [AudioDevice] { devices.filter { $0.inputChannels > 0 } }
    var headphones: [AudioDevice] { devices.filter { $0.route.allowsPrivatePlayback } }
    var canTestVoice: Bool { selectedHeadphones != nil && headphonesConfirmed && !isTestingVoice && state != .starting && state != .stopping }
    var canStart: Bool { state == .idle && selectedMicrophone != nil && selectedHeadphones != nil && headphonesConfirmed && !isTestingVoice }
    var isBusy: Bool { state != .idle }

    private var selectedMicrophone: AudioDevice? { microphones.first { $0.uid == microphoneUID } }
    private var selectedHeadphones: AudioDevice? { headphones.first { $0.uid == headphoneUID } }
    private var microphone: MicrophoneCapture?
    private var meeting: MeetingAudioCapture?
    private let voice = HeadphonePlayer()
    private var hardware: AudioHardwareObserver?
    private var timer: Timer?
    private var startup: Task<Void, Never>?
    private var appLoad: Task<Void, Never>?
    private var generation = RunGeneration()
    private var activeRoute: AudioRoute?
    private var activeMicrophone: AudioDevice?
    private var microphoneUpdatedAt = Date.distantPast
    private var meetingUpdatedAt = Date.distantPast
    private var lastHardwareCheck = Date.distantPast
    private var observing = false

    func activate() {
        guard !observing else { return }
        observing = true
        refreshDevices()
        if microphoneUID.isEmpty { microphoneUID = AudioDevices.defaultInputUID() ?? "" }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func deactivate() {
        observing = false
        timer?.invalidate()
        timer = nil
        hardware = nil
        appLoad?.cancel()
        appLoad = nil
        isLoadingApplications = false
        stopPractice()
    }

    func refreshDevices() {
        let current = AudioDevices.all()
        if let activeRoute,
           !AudioSafety.canContinue(expected: activeRoute,
                                    current: current.first(where: { $0.uid == activeRoute.uid })?.route,
                                    confirmed: headphonesConfirmed) {
            stopPractice(message: "Your headphone connection changed. Select and confirm your headphones again.")
            headphonesConfirmed = false
        }
        if let activeMicrophone,
           !current.contains(where: { $0.uid == activeMicrophone.uid && $0.deviceID == activeMicrophone.deviceID && $0.inputChannels > 0 }) {
            stopPractice(message: "The selected microphone disconnected. Reconnect it and start again.")
        }
        if devices != current || hardware == nil {
            devices = current
            if observing {
                hardware = AudioHardwareObserver(devices: current) { [weak self] in
                    Task { @MainActor in self?.refreshDevices() }
                }
            }
        }
        if !microphoneUID.isEmpty && selectedMicrophone == nil { microphoneUID = "" }
        if !headphoneUID.isEmpty && selectedHeadphones == nil { headphoneUID = "" }
    }

    func loadApplications() {
        guard state == .idle, !isLoadingApplications else { return }
        isLoadingApplications = true
        errorMessage = nil
        appLoad = Task { [weak self] in
            do {
                let apps = try await MeetingAudioCapture.applications()
                guard let self, !Task.isCancelled else { return }
                self.applications = apps
                if self.meetingPID != 0 && !apps.contains(where: { $0.id == self.meetingPID }) { self.meetingPID = 0 }
                self.status = "Choose the app that will play the other person's voice."
                self.isLoadingApplications = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = "Could not load meeting apps. Allow Jump In in System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording), then quit and reopen Jump In. \(error.localizedDescription)"
                self.isLoadingApplications = false
            }
        }
    }

    func startPractice() {
        guard canStart, let input = selectedMicrophone, let output = selectedHeadphones else { return }
        errorMessage = nil
        generation.invalidate()
        let token = generation.value
        let processID = meetingPID
        activeRoute = output.route
        activeMicrophone = input
        state = .starting
        status = "Starting audio…"
        startup = Task { [weak self] in
            guard let self else { return }
            do {
                let allowed = await Self.requestMicrophoneAccess()
                try Task.checkCancellation()
                guard allowed else {
                    throw AudioFailure.message("Microphone access is off. Allow Jump In in System Settings → Privacy & Security → Microphone, then try again.")
                }
                guard AudioSafety.canContinue(expected: output.route,
                    current: AudioDevices.device(output.deviceID)?.route, confirmed: self.headphonesConfirmed) else {
                    throw AudioFailure.message("The headphones changed while starting. Select them again.")
                }
                let mic = MicrophoneCapture()
                self.microphone = mic
                try mic.start(device: input, level: { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.generation.accepts(token), self.state == .running else { return }
                        self.microphoneLevel = value
                        self.microphoneUpdatedAt = Date()
                    }
                }, interrupted: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation.accepts(token) else { return }
                        self.stopPractice(message: "The microphone format or connection changed. Start again when the device is ready.")
                    }
                })
                if processID != 0 {
                    let capture = MeetingAudioCapture(level: { [weak self] value in
                        Task { @MainActor in
                            guard let self, self.generation.accepts(token), self.state == .running else { return }
                            self.meetingLevel = value
                            self.meetingUpdatedAt = Date()
                        }
                    }, failed: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.generation.accepts(token) else { return }
                            self.stopPractice(message: message)
                        }
                    })
                    self.meeting = capture
                    try await capture.start(processID: processID)
                }
                try Task.checkCancellation()
                guard self.generation.accepts(token) else { return }
                self.state = .running
                self.status = processID == 0 ? "Microphone check is running." : "Practice call is running. Both audio meters are active."
            } catch {
                // Stop waits for this startup task before disposing the meeting stream.
                // A late permission result or late startCapture must never restart capture.
                guard self.generation.accepts(token) else { return }
                self.microphone?.stop()
                self.microphone = nil
                await self.meeting?.stop()
                self.meeting = nil
                guard self.generation.accepts(token) else { return }
                self.activeRoute = nil
                self.activeMicrophone = nil
                self.state = .idle
                self.status = "Audio did not start."
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func stopPractice(message: String? = nil) {
        voice.stop()
        isTestingVoice = false
        activeRoute = nil
        activeMicrophone = nil
        microphone?.stop()
        microphone = nil
        microphoneLevel = 0
        meetingLevel = 0
        if let message { errorMessage = message }
        guard state != .stopping else { return }
        generation.invalidate()
        let token = generation.value
        let starting = startup
        starting?.cancel()
        if state == .idle {
            status = "Stopped. Ready when you are."
            return
        }
        state = .stopping
        status = "Stopping audio…"
        Task { [weak self] in
            await starting?.value
            guard let self else { return }
            await self.meeting?.stop()
            self.meeting = nil
            self.startup = nil
            guard self.generation.accepts(token) else { return }
            self.state = .idle
            self.status = "Stopped. Ready when you are."
        }
    }

    func testVoice() {
        guard canTestVoice, let output = selectedHeadphones else { return }
        errorMessage = nil
        activeRoute = output.route
        isTestingVoice = true
        status = "Playing a short test through \(output.name)…"
        voice.playTest(route: output.route) { [weak self] message in
            guard let self else { return }
            self.isTestingVoice = false
            if self.state == .idle { self.activeRoute = nil }
            if let message {
                self.stopPractice(message: message)
                self.headphonesConfirmed = false
            } else {
                self.status = "Voice test finished. Confirm with your practice partner that they could not hear it."
            }
        }
    }

    func stopVoice() {
        voice.stop()
        isTestingVoice = false
        if state == .idle { activeRoute = nil }
        status = "Voice test stopped."
    }

    func openPrivacySettings(microphone: Bool) {
        let anchor = microphone ? "Privacy_Microphone" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func selectionChanged() {
        if isBusy || isTestingVoice { stopPractice(message: "Audio settings changed. Start again when ready.") }
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(microphoneUpdatedAt) > 0.3 { microphoneLevel = 0 }
        if now.timeIntervalSince(meetingUpdatedAt) > 0.3 { meetingLevel = 0 }
        if now.timeIntervalSince(lastHardwareCheck) > 1 {
            lastHardwareCheck = now
            refreshDevices() // Backup for hardware drivers that omit HAL notifications.
            if state == .running, meetingPID != 0,
               NSRunningApplication(processIdentifier: meetingPID)?.isTerminated != false {
                stopPractice(message: "The meeting app closed. Reopen it, reload the app list, and start again.")
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
