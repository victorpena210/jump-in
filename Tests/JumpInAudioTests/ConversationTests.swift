import XCTest
@testable import JumpInAudio

final class ConversationTests: XCTestCase {
    func testPartialUpdatesReplaceTheirOwnSourceAndFinalCannotRegress() {
        var ledger = TranscriptLedger()
        let now = Date(), id = UUID()
        ledger.update(TranscriptLine(id: id, speaker: .you, startedAt: now, text: "My rate", isFinal: false))
        ledger.update(TranscriptLine(id: UUID(), speaker: .meeting, startedAt: now.addingTimeInterval(1), text: "What is included?", isFinal: true))
        ledger.update(TranscriptLine(id: id, speaker: .you, startedAt: now, text: "My rate is hourly.", isFinal: true))
        ledger.update(TranscriptLine(id: id, speaker: .you, startedAt: now, text: "Old partial", isFinal: false))
        XCTAssertEqual(ledger.lines.count, 2)
        XCTAssertEqual(ledger.lines[0].text, "My rate is hourly.")
        XCTAssertEqual(ledger.lines[1].speaker, .meeting)
    }

    func testContextExcludesOldAndLowConfidenceTextAndIsBounded() {
        let now = Date()
        var ledger = TranscriptLedger()
        ledger.update(TranscriptLine(id: UUID(), speaker: .you, startedAt: now.addingTimeInterval(-181), text: "old", isFinal: true))
        ledger.update(TranscriptLine(id: UUID(), speaker: .meeting, startedAt: now, text: "uncertain", isFinal: true, confidence: 0.1))
        XCTAssertTrue(ledger.context(now: now).isEmpty)
        for i in 0..<200 {
            ledger.update(TranscriptLine(id: UUID(), speaker: .meeting, startedAt: now.addingTimeInterval(Double(i) / 100),
                                         text: String(repeating: "word ", count: 500), isFinal: true, confidence: 0.9))
        }
        XCTAssertEqual(ledger.lines.count, 150)
        let context = ledger.context(now: now)
        XCTAssertLessThanOrEqual(context.map(\.text).joined().count, 8_000)
        XCTAssertLessThanOrEqual(context.count, 20)
        ledger.clear()
        XCTAssertTrue(ledger.context(now: now).isEmpty)
    }

    func testAutomaticCoachingRequiresNewConversationSilenceAndCooldown() {
        let now = Date()
        var policy = CoachingPolicy()
        func allowed(paused: Bool = false, busy: Bool = false, silence: Double = 2, fingerprint: String = "new") -> Bool {
            policy.shouldRequest(now: now, interval: 45, running: true, enabled: true, paused: paused,
                                 busy: busy, lastSpeech: now.addingTimeInterval(-silence), fingerprint: fingerprint)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(paused: true))
        XCTAssertFalse(allowed(busy: true))
        XCTAssertFalse(allowed(silence: 0.2))
        XCTAssertFalse(allowed(silence: 90))
        XCTAssertFalse(allowed(fingerprint: ""))
        policy.attempted(now: now.addingTimeInterval(-10), fingerprint: "old")
        XCTAssertFalse(allowed())
        policy.attempted(now: now.addingTimeInterval(-60), fingerprint: "new")
        XCTAssertFalse(allowed())
        XCTAssertTrue(allowed(fingerprint: "new words"))
    }

    func testCredentialsCannotBeSentToInsecureRemoteHostOrEmbeddedURLCredentials() throws {
        XCTAssertNoThrow(try BackendAddress.validate("http://localhost:8080"))
        XCTAssertNoThrow(try BackendAddress.validate("https://coach.example.com"))
        for url in ["http://coach.example.com", "https://user:secret@example.com", "file:///etc/passwd", "https://example.com?token=secret", "https://example.com#fragment"] {
            XCTAssertThrowsError(try BackendAddress.validate(url))
        }
    }
}
