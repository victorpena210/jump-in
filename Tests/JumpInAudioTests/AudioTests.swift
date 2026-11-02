import AVFoundation
import XCTest
@testable import JumpInAudio

final class AudioTests: XCTestCase {
    private let headphones = AudioRoute(deviceID: 42, uid: "usb-headphones", signature: "headphones:48000", allowsPrivatePlayback: true)

    func testDisconnectedHeadphonesCannotFallBackToAnotherOutput() {
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: nil, confirmed: true))
        let speakers = AudioRoute(deviceID: 1, uid: "speakers", signature: "speaker:48000", allowsPrivatePlayback: false)
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: speakers, confirmed: true))
        let otherHeadset = AudioRoute(deviceID: 43, uid: "other-headset", signature: "headphones:48000", allowsPrivatePlayback: true)
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: otherHeadset, confirmed: true))
    }

    func testSameHardwareIDDoesNotHideHeadphoneJackOrSampleRateChanges() {
        let changed = AudioRoute(deviceID: 42, uid: "usb-headphones", signature: "speaker:48000", allowsPrivatePlayback: false)
        let newFormat = AudioRoute(deviceID: 42, uid: "usb-headphones", signature: "headphones:16000", allowsPrivatePlayback: true)
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: changed, confirmed: true))
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: newFormat, confirmed: true))
    }

    func testExactRouteRequiresExplicitHeadphoneConfirmation() {
        XCTAssertTrue(AudioSafety.canContinue(expected: headphones, current: headphones, confirmed: true))
        XCTAssertFalse(AudioSafety.canContinue(expected: headphones, current: headphones, confirmed: false))
    }

    func testBuiltInSpeakersAndVirtualOutputsAreNotHeadphoneCandidates() {
        XCTAssertFalse(AudioSafety.allowsOutput(isBuiltIn: true, isHeadphoneTerminal: false, isExplicitlyUnsupported: false))
        XCTAssertTrue(AudioSafety.allowsOutput(isBuiltIn: true, isHeadphoneTerminal: true, isExplicitlyUnsupported: false))
        XCTAssertFalse(AudioSafety.allowsOutput(isBuiltIn: false, isHeadphoneTerminal: true, isExplicitlyUnsupported: true))
        XCTAssertTrue(AudioSafety.allowsOutput(isBuiltIn: false, isHeadphoneTerminal: false, isExplicitlyUnsupported: false))
    }

    func testStopAndRestartRejectLateCallbacks() {
        var generation = RunGeneration()
        let starting = generation.value
        XCTAssertTrue(generation.accepts(starting))
        generation.invalidate() // Stop during a permissions prompt or SCStream.startCapture.
        XCTAssertFalse(generation.accepts(starting))
        let next = generation.value
        generation.invalidate() // Another start must not accept old meter/speech callbacks.
        XCTAssertFalse(generation.accepts(next))
        XCTAssertFalse(generation.accepts(starting))
    }

    func testMeterHandlesSilenceClippingAndInvalidSamples() {
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: 0, sampleCount: 10), 0)
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: .nan, sampleCount: 10), 0)
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: .infinity, sampleCount: 10), 0)
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: 1, sampleCount: 0), 0)
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: 400, sampleCount: 100), 1)
        XCTAssertEqual(AudioLevel.normalized(sumOfSquares: 0.1, sampleCount: 100), 0.5, accuracy: 0.00001)
    }

    func testMeterReadsBothChannelsOfAnActualPCMBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<480 {
            channels[0][frame] = 0
            channels[1][frame] = 0.5
        }
        let expected = AudioLevel.normalized(sumOfSquares: 120, sampleCount: 960)
        XCTAssertEqual(BufferMeter.level(buffer), expected, accuracy: 0.00001)
    }
}
