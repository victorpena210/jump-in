import AVFoundation
import AudioToolbox

/// Speech is rendered into memory, then sent through an engine bound to one HAL
/// device. Never use synthesizer.speak(), which follows the system default output.
@MainActor
final class HeadphonePlayer {
    private let synthesizer = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?
    private var generation = RunGeneration()
    private var buffers: [AVAudioPCMBuffer] = []
    private var completion: ((String?) -> Void)?

    func playTest(route: AudioRoute, finished: @escaping (String?) -> Void) {
        stop()
        completion = finished
        let token = generation.value
        guard AudioSafety.canContinue(expected: route, current: AudioDevices.device(route.deviceID)?.route,
                                      confirmed: true) else {
            finish("Your headphone connection changed. Select the headphones again.")
            return
        }
        let utterance = AVSpeechUtterance(string: "Jump In audio test. You should hear this only in your headphones.")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.write(utterance) { [weak self] buffer in
            let pcm = buffer as? AVAudioPCMBuffer
            let ended = pcm?.frameLength == 0
            let copy = pcm.flatMap { $0.frameLength > 0 ? Self.copy($0) : nil }
            DispatchQueue.main.async {
                guard let self, self.generation.accepts(token) else { return }
                if ended {
                    self.startPlayback(route: route, token: token)
                } else if let copy {
                    self.buffers.append(copy)
                } else {
                    self.finish("The Mac's voice could not generate audio. Check that a system voice is installed.")
                }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
            guard let self, self.generation.accepts(token) else { return }
            self.finish("The voice test timed out. Try again or check the Mac's installed voices.")
        }
    }

    func stop() {
        generation.invalidate()
        timeout?.cancel()
        timeout = nil
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        buffers.removeAll()
    }

    private func finish(_ message: String?) {
        let callback = completion
        stop()
        callback?(message)
    }

    private func startPlayback(route: AudioRoute, token: UUID) {
        guard let first = buffers.first else {
            finish("No voice audio was generated. Check the Mac's installed voices.")
            return
        }
        guard AudioSafety.canContinue(expected: route, current: AudioDevices.device(route.deviceID)?.route,
                                      confirmed: true) else {
            finish("The headphones disconnected or changed. Playback was stopped.")
            return
        }
        do {
            let audioEngine = AVAudioEngine()
            engine = audioEngine // Retain before any throwing operation so finish cleans up.
            guard let unit = audioEngine.outputNode.audioUnit else {
                throw AudioFailure.message("The selected headphones cannot be opened.")
            }
            var id = route.deviceID
            try AudioDevices.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)), "Selecting headphones")
            let node = AVAudioPlayerNode()
            player = node
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: first.format)
            node.volume = 0.35
            for (index, buffer) in buffers.enumerated() {
                guard buffer.format == first.format else {
                    throw AudioFailure.message("The system voice changed audio format. Please retry the test.")
                }
                if index == buffers.count - 1 {
                    node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        DispatchQueue.main.async {
                            guard let self, self.generation.accepts(token) else { return }
                            self.finish(nil)
                        }
                    }
                } else {
                    node.scheduleBuffer(buffer)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            var actual: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            try AudioDevices.check(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &actual, &size), "Checking headphone output")
            guard actual == route.deviceID,
                  AudioDevices.device(actual)?.route == route else {
                throw AudioFailure.message("The audio output changed. Playback was stopped.")
            }
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: audioEngine, queue: .main) { [weak self] _ in
                    // Explicit hop also works with SDKs that mark this callback Sendable.
                    Task { @MainActor in
                        guard let self, self.generation.accepts(token) else { return }
                        self.finish("The audio connection changed. Playback was stopped; reconnect and test again.")
                    }
                }
            node.play()
        } catch {
            finish(error.localizedDescription)
        }
    }

    nonisolated private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        result.frameLength = source.frameLength
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let output = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        guard input.count == output.count else { return nil }
        for index in input.indices {
            guard let from = input[index].mData, let to = output[index].mData,
                  output[index].mDataByteSize >= input[index].mDataByteSize else { return nil }
            memcpy(to, from, Int(input[index].mDataByteSize))
        }
        return result
    }
}
