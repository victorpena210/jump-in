import Foundation

enum CoachingMode: String, CaseIterable, Identifiable, Codable {
    case upwork, interview
    var id: String { rawValue }
    var title: String { self == .upwork ? "Upwork clients" : "Job interviews" }
    var description: String {
        self == .upwork ? "Discuss scope, pricing, timelines, and next steps." : "Practice clear answers using your actual experience."
    }
}

enum Speaker: String, Codable { case you, meeting
    var title: String { self == .you ? "You" : "Meeting" }
}

struct TranscriptLine: Identifiable, Equatable {
    let id: UUID
    let speaker: Speaker
    let startedAt: Date
    var text: String
    var isFinal: Bool
    var confidence: Double?
}

struct TranscriptLedger {
    private(set) var lines: [TranscriptLine] = []
    mutating func update(_ line: TranscriptLine) {
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var bounded = line
        bounded.text = String(line.text.prefix(2_000))
        if let index = lines.firstIndex(where: { $0.id == line.id }) {
            guard !lines[index].isFinal || line.isFinal else { return }
            lines[index] = bounded
        } else { lines.append(bounded) }
        lines.sort { $0.startedAt < $1.startedAt }
        if lines.count > 150 { lines.removeFirst(lines.count - 150) }
    }
    mutating func clear() { lines.removeAll() }
    func context(now: Date) -> [CoachTurn] {
        var remaining = 8_000
        var result: [CoachTurn] = []
        for line in lines.reversed() where now.timeIntervalSince(line.startedAt) < 180 {
            // Final recognition confidence is useful; partial estimates are often zero.
            if line.isFinal, let confidence = line.confidence, confidence < 0.35 { continue }
            let text = String(line.text.suffix(min(2_000, remaining)))
            guard !text.isEmpty else { break }
            result.append(CoachTurn(speaker: line.speaker.rawValue, text: text))
            remaining -= text.count
            if remaining == 0 || result.count == 20 { break }
        }
        return Array(result.reversed())
    }
}

struct CoachTurn: Codable, Equatable { let speaker: String; let text: String }
struct CoachRequest: Encodable {
    let mode: CoachingMode
    let context: String
    let turns: [CoachTurn]
    let previousSuggestion: String
}
struct CoachReply: Decodable { let suggestion: String }

/// One decision point shared by the timer and tests. Never queue overlapping requests.
struct CoachingPolicy {
    var lastAttempt = Date.distantPast
    var lastFingerprint = ""
    func shouldRequest(now: Date, interval: TimeInterval, running: Bool, enabled: Bool,
                       paused: Bool, busy: Bool, lastSpeech: Date, fingerprint: String) -> Bool {
        running && enabled && !paused && !busy && !fingerprint.isEmpty &&
        fingerprint != lastFingerprint && now.timeIntervalSince(lastAttempt) >= interval &&
        now.timeIntervalSince(lastSpeech) >= 1.5 && now.timeIntervalSince(lastSpeech) < 45
    }
    mutating func attempted(now: Date, fingerprint: String) {
        lastAttempt = now; lastFingerprint = fingerprint
    }
}

enum BackendAddress {
    static func validate(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host))
        else { throw AudioFailure.message("Use an HTTPS backend address, or http://localhost:8080 for this Mac.") }
        return url
    }
}
