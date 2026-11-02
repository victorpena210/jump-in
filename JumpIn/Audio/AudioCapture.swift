import AVFoundation
import AudioToolbox
import ScreenCaptureKit

enum BufferMeter {
    static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        var sum: Double = 0
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channel in 0..<channelCount {
            for frame in 0..<frames {
                let value = Double(channels[channel][frame * buffer.stride])
                if value.isFinite { sum += value * value }
            }
        }
        return AudioLevel.normalized(sumOfSquares: sum, sampleCount: frames * channelCount)
    }
}

final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var installedTap = false
    private var observer: NSObjectProtocol?

    func start(device: AudioDevice, level: @escaping (Double) -> Void,
               interrupted: @escaping () -> Void) throws {
        guard let current = AudioDevices.device(device.deviceID), current.uid == device.uid,
              current.inputChannels > 0 else { throw AudioFailure.message("The selected microphone disconnected.") }
        let input = engine.inputNode
        guard let unit = input.audioUnit else { throw AudioFailure.message("This microphone cannot be opened.") }
        var id = device.deviceID
        try AudioDevices.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)), "Selecting microphone")
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw AudioFailure.message("The microphone has no usable audio format. Reconnect it and try again.")
        }
        var lastUpdate = 0.0 // Accessed only by this tap's serial audio callback.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let now = Date.timeIntervalSinceReferenceDate
            guard now - lastUpdate >= 0.05 else { return }
            lastUpdate = now
            level(BufferMeter.level(buffer))
        }
        installedTap = true
        // No connection from the input node to the output: never monitor the microphone.
        engine.prepare()
        try engine.start()
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { _ in interrupted() }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0) }
        installedTap = false
    }

    deinit { stop() }
}

struct MeetingApplication: Identifiable {
    let id: Int32
    let name: String
}

/// ScreenCaptureKit supplies the chosen app's audio. No video output is attached.
final class MeetingAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "technology.renatus.JumpIn.meeting-audio")
    private let level: (Double) -> Void
    private let failed: (String) -> Void
    private var lastUpdate = 0.0

    init(level: @escaping (Double) -> Void, failed: @escaping (String) -> Void) {
        self.level = level
        self.failed = failed
    }

    static func applications() async throws -> [MeetingApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.applications
            .filter { $0.processID != ProcessInfo.processInfo.processIdentifier && !$0.applicationName.isEmpty }
            .map { MeetingApplication(id: $0.processID, name: $0.applicationName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start(processID: Int32) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard processID != ProcessInfo.processInfo.processIdentifier,
              let app = content.applications.first(where: { $0.processID == processID }) else {
            throw AudioFailure.message("The selected meeting app closed. Open it and reload the app list.")
        }
        guard let display = content.displays.first else { throw AudioFailure.message("No display is available for meeting-audio capture.") }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = capture
        try await capture.startCapture()
    }

    func stop() async {
        let previous = stream
        stream = nil
        try? await previous?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastUpdate >= 0.05 else { return }
        lastUpdate = now
        // The no-copy PCM buffer is consumed inside this closure, before its backing
        // CMBlockBuffer is released. Neither stream is retained or written to disk.
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                             channels: description.mChannelsPerFrame),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer)
            else { return }
            level(BufferMeter.level(buffer))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failed("Meeting audio stopped: \(error.localizedDescription)")
    }
}
