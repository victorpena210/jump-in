import Foundation

enum AudioFailure: LocalizedError {
    case message(String)
    case system(String, Int32)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .system(let operation, let code): return "\(operation) failed (audio error \(code)). Reconnect the device and try again."
        }
    }
}

/// A device ID alone is insufficient: a headphone jack can become speakers without
/// changing the device ID. Keep the data source and stream terminals in the identity.
struct AudioRoute: Equatable {
    let deviceID: UInt32
    let uid: String
    let signature: String
    let allowsPrivatePlayback: Bool
}

enum AudioSafety {
    static func canContinue(expected: AudioRoute, current: AudioRoute?, confirmed: Bool) -> Bool {
        confirmed && expected.allowsPrivatePlayback && current == expected
    }

    static func allowsOutput(isBuiltIn: Bool, isHeadphoneTerminal: Bool,
                             isExplicitlyUnsupported: Bool) -> Bool {
        !isExplicitlyUnsupported && (!isBuiltIn || isHeadphoneTerminal)
    }
}

enum AudioLevel {
    /// Linear RMS mapped from -60...0 dB to 0...1. Never propagate NaN to SwiftUI.
    static func normalized(sumOfSquares: Double, sampleCount: Int) -> Double {
        guard sampleCount > 0, sumOfSquares.isFinite, sumOfSquares > 0 else { return 0 }
        let rms = sqrt(sumOfSquares / Double(sampleCount))
        return min(1, max(0, (20 * log10(rms) + 60) / 60))
    }
}

/// Allows an async callback to be discarded after Stop, a failed start, or a new run.
struct RunGeneration {
    private(set) var value = UUID()
    mutating func invalidate() { value = UUID() }
    func accepts(_ candidate: UUID) -> Bool { candidate == value }
}
