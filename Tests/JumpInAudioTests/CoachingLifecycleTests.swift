import XCTest
@testable import JumpInAudio

private actor DelayedReply {
    var pending: CheckedContinuation<String, Never>?
    var requested: CheckedContinuation<Void, Never>?
    var started = false
    func reply() async -> String {
        started = true; requested?.resume(); requested = nil
        return await withCheckedContinuation { pending = $0 }
    }
    func waitUntilRequested() async {
        if started { return }
        await withCheckedContinuation { requested = $0 }
    }
    func finish() { pending?.resume(returning: "Ask about the project timeline."); pending = nil }
}

private struct DelayedClient: CoachingService {
    let gate: DelayedReply
    func suggest(_ request: CoachRequest, baseURL: URL, token: String) async throws -> String { await gate.reply() }
    func check(baseURL: URL, token: String) async throws {}
}

final class CoachingLifecycleTests: XCTestCase {
    @MainActor
    private func session(_ gate: DelayedReply) -> ConversationSession {
        let session = ConversationSession(client: DelayedClient(gate: gate), loadSettings: false)
        session.accessToken = "test-only-backend-token"
        session.aiEnabled = true
        session.audioDidStart()
        session.receive(TranscriptLine(id: UUID(), speaker: .meeting, startedAt: Date(),
                                       text: "When can you finish the website?", isFinal: true, confidence: 0.9))
        return session
    }

    @MainActor
    func testStopRejectsReplyEvenWhenNetworkIgnoresCancellation() async {
        let gate = DelayedReply(), coach = session(gate)
        let playback = expectation(description: "No late playback"); playback.isInverted = true
        coach.play = { _, _ in playback.fulfill() }
        coach.requestSuggestion()
        await gate.waitUntilRequested()
        coach.stop()
        await gate.finish()
        await fulfillment(of: [playback], timeout: 0.1)
        XCTAssertEqual(coach.suggestion, "")
        XCTAssertFalse(coach.requesting)
    }

    @MainActor
    func testPauseAndConsentWithdrawalRejectPendingReplies() async {
        for withdrawConsent in [false, true] {
            let gate = DelayedReply(), coach = session(gate)
            let playback = expectation(description: "No paused or disabled playback"); playback.isInverted = true
            coach.play = { _, _ in playback.fulfill() }
            coach.requestSuggestion()
            await gate.waitUntilRequested()
            if withdrawConsent { coach.aiEnabled = false } else { coach.paused = true }
            await gate.finish()
            await fulfillment(of: [playback], timeout: 0.1)
            XCTAssertEqual(coach.suggestion, "")
            coach.stop()
        }
    }

    @MainActor
    func testNewSpeechCancelsAnAutomaticSuggestion() async {
        let gate = DelayedReply(), coach = session(gate)
        let playback = expectation(description: "No automatic interruption"); playback.isInverted = true
        coach.play = { _, _ in playback.fulfill() }
        coach.requestSuggestion(automaticRequest: true)
        await gate.waitUntilRequested()
        coach.noteSpeech(level: 0.4)
        await gate.finish()
        await fulfillment(of: [playback], timeout: 0.1)
        XCTAssertEqual(coach.suggestion, "")
        coach.stop()
    }

    @MainActor
    func testRequestedSuggestionReachesPlaybackAndCompletes() async {
        let gate = DelayedReply(), coach = session(gate)
        let playback = expectation(description: "Play one suggestion")
        coach.play = { text, finished in
            XCTAssertEqual(text, "Ask about the project timeline.")
            finished(nil); playback.fulfill()
        }
        coach.requestSuggestion()
        XCTAssertFalse(coach.canRequest)
        await gate.waitUntilRequested()
        await gate.finish()
        await fulfillment(of: [playback], timeout: 1)
        XCTAssertFalse(coach.requesting)
        XCTAssertFalse(coach.speaking)
        XCTAssertTrue(coach.canRequest)
        coach.stop()
    }
}
