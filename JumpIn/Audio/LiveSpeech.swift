import AVFoundation
import Speech

/// Each source has its own recognizer and serial queue. Audio callbacks never
/// send buffers to the UI, and queued audio is bounded if recognition stalls.
final class SpeechStream {
    private final class Segment {
        let id = UUID()
        let startedAt = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        var task: SFSpeechRecognitionTask?
        var text = ""
        var confidence: Double?
        var lastSpeech = Date()
    }

    private let queue = DispatchQueue(label: "technology.renatus.JumpIn.speech.\(UUID().uuidString)")
    private let slots = DispatchSemaphore(value: 24)
    private let recognizer: SFSpeechRecognizer
    private let speaker: Speaker
    private let localOnly: Bool
    private let update: (TranscriptLine) -> Void
    private let failed: (String) -> Void
    private var current: Segment?
    private var draining: [UUID: Segment] = [:]
    private var active = true
    private var failures = 0
    private var timer: DispatchSourceTimer?

    init(speaker: Speaker, locale: Locale, localOnly: Bool,
         update: @escaping (TranscriptLine) -> Void, failed: @escaping (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AudioFailure.message("Speech recognition is unavailable for \(locale.identifier). Check macOS Dictation language settings and try again.")
        }
        guard !localOnly || recognizer.supportsOnDeviceRecognition else {
            throw AudioFailure.message("On-device speech is unavailable for \(locale.identifier) on this Mac. Enable Dictation for that language, or turn off ‘Keep speech recognition on this Mac’ to allow Apple's speech service.")
        }
        self.recognizer = recognizer; self.speaker = speaker; self.localOnly = localOnly
        self.update = update; self.failed = failed
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard slots.wait(timeout: .now()) == .success else { return }
        guard let copy = HeadphonePlayer.copy(buffer) else { slots.signal(); return }
        queue.async { [weak self, slots] in
            defer { slots.signal() }
            guard let self, self.active else { return }
            let audible = BufferMeter.level(copy) > 0.08
            // Do not spend recognition sessions on indefinite silence.
            if self.current == nil {
                guard audible else { return }
                self.beginSegment()
            }
            if audible { self.current?.lastSpeech = Date() }
            self.current?.request.append(copy)
        }
    }

    func stop() {
        queue.sync {
            active = false
            timer?.cancel(); timer = nil
            current?.request.endAudio(); current?.task?.cancel(); current = nil
            for segment in draining.values { segment.task?.cancel() }
            draining.removeAll()
        }
    }

    private func beginSegment() {
        let segment = Segment()
        segment.request.shouldReportPartialResults = true
        segment.request.requiresOnDeviceRecognition = localOnly
        segment.request.taskHint = .dictation
        segment.request.addsPunctuation = true
        current = segment
        segment.task = recognizer.recognitionTask(with: segment.request) { [weak self, weak segment] result, error in
            guard let self, let segment else { return }
            self.queue.async { [weak self] in
                guard let self, self.active,
                      self.current?.id == segment.id || self.draining[segment.id] != nil else { return }
                if let result {
                    self.failures = 0
                    segment.text = result.bestTranscription.formattedString
                    let scores = result.bestTranscription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
                    segment.confidence = result.isFinal && !scores.isEmpty ? scores.reduce(0, +) / Double(scores.count) : nil
                    self.publish(segment, final: result.isFinal)
                    if result.isFinal { self.retire(segment) }
                }
                if let error {
                    self.publish(segment, final: true)
                    self.retire(segment)
                    let code = (error as NSError).code
                    if code != 1110 && code != 216 && code != 301 { self.failures += 1 }
                    if self.failures >= 3 {
                        self.active = false
                        self.failed("\(self.speaker.title) transcription stopped. Check Speech Recognition permissions and the selected language, then restart the session.")
                    }
                }
            }
        }
    }

    private func tick() {
        guard active, let segment = current else { return }
        let now = Date()
        if now.timeIntervalSince(segment.startedAt) >= 45 || now.timeIntervalSince(segment.lastSpeech) >= 1.2 {
            current = nil
            draining[segment.id] = segment
            segment.request.endAudio()
            segment.task?.finish()
            queue.asyncAfter(deadline: .now() + 3) { [weak self, weak segment] in
                guard let self, let segment, self.active, self.draining[segment.id] != nil else { return }
                self.publish(segment, final: true)
                segment.task?.cancel()
                self.draining.removeValue(forKey: segment.id)
            }
        }
    }

    private func publish(_ segment: Segment, final: Bool) {
        guard !segment.text.isEmpty else { return }
        update(TranscriptLine(id: segment.id, speaker: speaker, startedAt: segment.startedAt,
                              text: segment.text, isFinal: final, confidence: segment.confidence))
    }
    private func retire(_ segment: Segment) {
        if current?.id == segment.id { current = nil }
        draining.removeValue(forKey: segment.id)
    }
}
