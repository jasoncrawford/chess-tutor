import Foundation
import XCTest
@testable import ChessTutor

@MainActor
final class HostedCoachingDebounceTests: XCTestCase {
    private let b1 = Square(file: .b, rank: 1)
    private let g1 = Square(file: .g, rank: 1)

    func testTrailingDeadlineUsesFinalAnswerAndLogsCombinedRequests() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .selectPiece)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(b1))
        let identity = fixture.session.coachingRequestIdentity
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        await eventually { fixture.clock.sleepCount == 1 }
        fixture.clock.advance(by: 0.2)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(g1))
        XCTAssertEqual(fixture.session.coachingRequestIdentity, identity)
        XCTAssertEqual(fixture.session.selectedSquare, g1)
        fixture.clock.advance(by: 0.2)
        await eventually { fixture.clock.sleepCount == 2 }
        fixture.clock.advance(by: 0.199)
        await settle()
        await assertCallCount(fixture.provider, 1)
        fixture.clock.advance(by: 0.0011)
        let request = try await fixture.provider.request(at: 1)
        XCTAssertEqual(request.interaction.latestEvent.referencedIDs, ["piece:white:knight:g1"])
        await fixture.provider.succeed(at: 1, message: "Final knight.")
        await worker.value
        XCTAssertEqual(fixture.session.coachingPresentation?.primaryMessage, "Final knight.")
        let dispatched = try XCTUnwrap(fixture.events.snapshot.last { $0.name == "request_dispatched" })
        XCTAssertEqual(dispatched.fields["coalesced_count"], "1")
        XCTAssertEqual(dispatched.fields["debounce_ms"], "400")
        XCTAssertEqual(dispatched.fields["debounce_wait_ms"], "400")
        XCTAssertEqual(dispatched.fields["in_flight_wait_ms"], "0")
        XCTAssertEqual(dispatched.fields["request_id"], request.requestID)
        let applied = try XCTUnwrap(fixture.events.snapshot.last { $0.name == "response_applied" })
        XCTAssertEqual(applied.fields["interaction_to_advice_ms"], "400")
    }

    func testSlowRequestKeepsOnlyLatestMoveAndDiscardsUnseenContinuation() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 0)
        let identity = fixture.session.coachingRequestIdentity
        fixture.session.select(g1)
        XCTAssertEqual(fixture.session.moveSelectedPiece(to: Square(file: .h, rank: 3)), .moved)
        fixture.clock.advance(by: 0.1)
        XCTAssertEqual(fixture.session.tapEmptySquare(at: Square(file: .f, rank: 3)), .moved)
        XCTAssertEqual(fixture.session.coachingRequestIdentity, identity)
        let duplicateWorker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        fixture.clock.advance(by: 1.9)
        await settle()
        await assertCallCount(fixture.provider, 1)
        await fixture.provider.succeed(at: 0, message: "Obsolete opening.")
        let finalRequest = try await fixture.provider.request(at: 1)
        XCTAssertEqual(finalRequest.interaction.tentativeMove?.canonicalMove, "g1f3")
        let continuation = await fixture.provider.continuation(at: 1)
        XCTAssertNil(continuation)
        XCTAssertNotEqual(fixture.session.coachingPresentation?.primaryMessage, "Obsolete opening.")
        let maximumConcurrent = await fixture.provider.maximumConcurrentCalls()
        XCTAssertEqual(maximumConcurrent, 1)
        await fixture.provider.succeed(at: 1, message: "Current move.")
        await worker.value
        await duplicateWorker.value
        await assertCallCount(fixture.provider, 2)
        XCTAssertEqual(fixture.session.coachingPresentation?.primaryMessage, "Current move.")
        let dispatched = try XCTUnwrap(fixture.events.snapshot.last { $0.name == "request_dispatched" })
        XCTAssertEqual(dispatched.fields["in_flight_wait_ms"], "1500")
        XCTAssertEqual(dispatched.fields["staged_move"], "g1f3")
        XCTAssertTrue(fixture.events.snapshot.contains { $0.name == "response_discarded" })
    }

    func testMoveSupersedesSelectionQuestionAndDeadlineWithoutBlockingBoard() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .selectPiece)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(g1))
        fixture.clock.advance(by: 0.1)
        XCTAssertEqual(fixture.session.moveSelectedPiece(to: Square(file: .f, rank: 3)), .moved)
        XCTAssertTrue(fixture.session.canFinishTurn)
        XCTAssertFalse(fixture.session.handleCoachingSquareTap(b1), "A stale selection question must not consume taps after a move")
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        await eventually { fixture.clock.sleepCount == 1 }
        fixture.clock.advance(by: 0.4)
        let request = try await fixture.provider.request(at: 1)
        XCTAssertEqual(request.interaction.latestEvent.kind, .moveStaged)
        XCTAssertEqual(request.interaction.tentativeMove?.canonicalMove, "g1f3")
        await fixture.provider.succeed(at: 1, message: "Consider the move.")
        await worker.value
    }

    func testCloseBeforeDeadlineSendsNothingAndCancellationIsLogged() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .selectPiece)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(b1))
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        await eventually { fixture.clock.sleepCount == 1 }
        fixture.session.stopCoaching()
        worker.cancel() // Matches SwiftUI's task identity cancellation.
        await worker.value
        fixture.clock.advance(by: 1)
        await assertCallCount(fixture.provider, 1)
        XCTAssertNil(fixture.session.coachingPresentation)
        XCTAssertTrue(fixture.events.snapshot.contains { $0.name == "request_cancelled" && $0.fields["reason"] == "help_closed" })
    }

    func testReopeningWaitsForOldResolverAndDoesNotApplyItsFailure() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let oldWorker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 0)
        fixture.session.stopCoaching()
        oldWorker.cancel()
        fixture.session.startCoaching()
        let newWorker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        await settle()
        await assertCallCount(fixture.provider, 1)
        await fixture.provider.fail(at: 0)
        _ = try await fixture.provider.request(at: 1)
        XCTAssertEqual(fixture.session.coachingPresentation?.primaryMessage, "Thinking…")
        await fixture.provider.succeed(at: 1, message: "Reopened.")
        await oldWorker.value
        await newWorker.value
        XCTAssertEqual(fixture.session.coachingPresentation?.primaryMessage, "Reopened.")
    }

    func testExplicitHintIsImmediateAndLocalSelectionsAreLoggedWithoutRequests() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .stageMove)
        XCTAssertFalse(fixture.session.handleCoachingSquareTap(b1))
        fixture.session.select(b1)
        XCTAssertNil(fixture.session.pendingCoachingRequestID)
        fixture.session.chooseCoachingAction(.hint)
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        let request = try await fixture.provider.request(at: 1)
        XCTAssertEqual(fixture.clock.sleepCount, 0)
        XCTAssertEqual(request.interaction.latestEvent.referencedIDs, ["action:hint"])
        await fixture.provider.succeed(at: 1, message: "A hint.")
        await worker.value
        XCTAssertTrue(fixture.events.snapshot.contains { $0.name == "board_input" && $0.fields["disposition"] == "local" })
    }

    func testExportContainsCompactCorrelatedEventsNotAdviceOrContinuation() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .stageMove)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticsLog(directoryURL: directory)
        for event in fixture.events.snapshot {
            await log.append(category: event.category, event.name, fields: event.fields, timestamp: event.timestamp)
        }
        let exported = await log.exportText()
        XCTAssertTrue(exported.contains("coaching.request_dispatched"))
        XCTAssertTrue(exported.contains("coaching.response_applied"))
        XCTAssertTrue(exported.contains("game_id="))
        XCTAssertTrue(exported.contains("episode_id="))
        XCTAssertTrue(exported.contains("request_id=hosted-1"))
        XCTAssertTrue(exported.contains("event_sequence="))
        XCTAssertTrue(exported.contains("uptime_ms="))
        XCTAssertFalse(exported.contains("secret-continuation"))
        XCTAssertFalse(exported.contains("Private coaching prose"))
        XCTAssertFalse(exported.contains("legalMoves"))
        let sequence = fixture.events.snapshot.compactMap { Int($0.fields["event_sequence"] ?? "") }
        XCTAssertEqual(sequence, Array(1...sequence.count))
    }

    func testTryAnotherMoveControlDoesNotWaitForBoardDebounce() async throws {
        let fixture = Fixture()
        fixture.session.select(g1)
        XCTAssertEqual(fixture.session.moveSelectedPiece(to: Square(file: .f, rank: 3)), .moved)
        try await fixture.open(expects: .chooseWhetherToPlay)
        fixture.session.chooseCoachingAction(.keepLooking)
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        defer { worker.cancel() }
        let request = try await fixture.provider.request(at: 1)
        XCTAssertEqual(request.interaction.latestEvent.kind, .moveRemoved)
        XCTAssertEqual(fixture.clock.sleepCount, 0)
        await fixture.provider.succeed(at: 1, message: "Choose another piece.")
        await worker.value
    }

    func testPendingQuestionStillRoutesRealBoardContactsAsAnswers() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .selectPiece)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(b1))
        XCTAssertEqual(fixture.session.authoritativeCoachingBoardTask, .identify(allowsMoveRevision: false))
        fixture.session.select(g1)
        fixture.session.moveSelectedPiece(to: Square(file: .f, rank: 3))
        XCTAssertEqual(fixture.session.authoritativeCoachingBoardTask, .none)
        fixture.session.stopCoaching()
    }

    func testCancelledSentRequestIsNotRepeatedByWaitingResolver() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 0)
        let duplicate = Task { await fixture.session.resolvePendingCoachingAdvice() }
        await settle()
        worker.cancel()
        await fixture.provider.fail(at: 0)
        await worker.value
        await settle()
        await assertCallCount(fixture.provider, 1)
        XCTAssertNil(fixture.session.pendingCoachingRequestID)
        XCTAssertTrue(fixture.session.coachingPresentation?.actions.contains { $0.action == .hint } == true)
        duplicate.cancel()
        await fixture.provider.failAll()
        await duplicate.value
    }

    func testCancellationWakesNewerMoveWithFreshTaskIdentity() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 0)
        fixture.session.select(g1)
        fixture.session.moveSelectedPiece(to: Square(file: .f, rank: 3))
        let oldIdentity = fixture.session.coachingRequestIdentity
        worker.cancel()
        await fixture.provider.fail(at: 0)
        await worker.value
        XCTAssertNotEqual(fixture.session.coachingRequestIdentity, oldIdentity)
        fixture.clock.advance(by: 0.4)
        let replacement = Task { await fixture.session.resolvePendingCoachingAdvice() }
        let latest = try await fixture.provider.request(at: 1)
        XCTAssertEqual(latest.interaction.tentativeMove?.canonicalMove, "g1f3")
        await fixture.provider.succeed(at: 1, message: "New move after cancellation.")
        await replacement.value
    }

    func testProviderCancellationDoesNotStrandNewerMove() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        defer { worker.cancel() }
        _ = try await fixture.provider.request(at: 0)
        fixture.session.select(g1)
        fixture.session.moveSelectedPiece(to: Square(file: .f, rank: 3))
        fixture.clock.advance(by: 0.4)
        await fixture.provider.failAll() // CancellationError, but parent task is still live.
        let latest = try await fixture.provider.request(at: 1)
        XCTAssertEqual(latest.interaction.tentativeMove?.canonicalMove, "g1f3")
        await fixture.provider.succeed(at: 1, message: "After transport cancellation.")
        await worker.value
    }

    func testInvalidReplyDoesNotAutomaticallyResendSameRequest() async throws {
        let fixture = Fixture()
        fixture.session.startCoaching()
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 0)
        await fixture.provider.succeed(at: 0, message: "Wrong ID.", requestIDOverride: "wrong-request")
        await settle()
        await assertCallCount(fixture.provider, 1)
        worker.cancel()
        await fixture.provider.failAll()
        await worker.value
        XCTAssertNotEqual(fixture.session.coachingPresentation?.primaryMessage, "Wrong ID.")
    }

    func testReturnToEarlierChoiceStillDiscardsAnEarlierInFlightAnswer() async throws {
        let fixture = Fixture()
        try await fixture.open(expects: .selectPiece)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(b1))
        fixture.clock.advance(by: 0.4)
        let worker = Task { await fixture.session.resolvePendingCoachingAdvice() }
        _ = try await fixture.provider.request(at: 1)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(g1))
        fixture.clock.advance(by: 0.1)
        XCTAssertTrue(fixture.session.handleCoachingSquareTap(b1))
        fixture.clock.advance(by: 0.4)
        await fixture.provider.succeed(at: 1, message: "Obsolete answer.")
        let latest = try await fixture.provider.request(at: 2)
        XCTAssertEqual(latest.interaction.latestEvent.referencedIDs, ["piece:white:knight:b1"])
        XCTAssertNotEqual(fixture.session.coachingPresentation?.primaryMessage, "Obsolete answer.")
        await fixture.provider.succeed(at: 2, message: "Latest answer.")
        await worker.value
        XCTAssertEqual(fixture.session.coachingPresentation?.primaryMessage, "Latest answer.")
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition was not reached", file: file, line: line)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func assertCallCount(_ provider: DebounceProvider, _ expected: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let count = await provider.callCount()
        XCTAssertEqual(count, expected, file: file, line: line)
    }

    @MainActor
    private struct Fixture {
        let clock = ManualCoachingClock()
        let provider = DebounceProvider()
        let events = CoachingEventCapture()
        let session: GameSession

        init() {
            let clock = clock, events = events
            session = GameSession(
                hostedCoachingProvider: provider,
                hostedCoachingTiming: HostedCoachingTiming(now: { clock.now }, sleep: { try await clock.sleep($0) }),
                coachingDiagnosticSink: { events.record($0) }
            )
        }

        func open(expects: ModelCoachingChessNativeExpectedResponse) async throws {
            session.startCoaching()
            let worker = Task { await session.resolvePendingCoachingAdvice() }
            _ = try await provider.request(at: 0)
            await provider.succeed(at: 0, message: "Private coaching prose", expects: expects)
            await worker.value
        }
    }
}

private final class ManualCoachingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var count = 0
    private var waiters: [UUID: (TimeInterval, CheckedContinuation<Void, Error>)] = [:]
    var now: TimeInterval { lock.withLock { time } }
    var sleepCount: Int { lock.withLock { count } }

    func sleep(_ seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    count += 1
                    waiters[id] = (time + seconds, continuation)
                }
            }
        } onCancel: {
            let waiter = self.lock.withLock { self.waiters.removeValue(forKey: id) }
            waiter?.1.resume(throwing: CancellationError())
        }
    }

    func advance(by seconds: TimeInterval) {
        let ready = lock.withLock {
            time += seconds
            let ready = waiters.filter { $0.value.0 <= time + 0.0000001 }
            for id in ready.keys { waiters.removeValue(forKey: id) }
            return ready.values.map(\.1)
        }
        for continuation in ready { continuation.resume() }
    }
}

private final class CoachingEventCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DiagnosticsEvent] = []
    var snapshot: [DiagnosticsEvent] { lock.withLock { events } }
    func record(_ event: DiagnosticsEvent) { lock.withLock { events.append(event) } }
}

private actor DebounceProvider: HostedCoachingTurning {
    private var requests: [ModelCoachingNeutralRequest] = []
    private var continuations: [String?] = []
    private var pending: [Int: CheckedContinuation<HostedCoachingResponse, Error>] = [:]
    private var maximumConcurrent = 0

    func turn(for request: ModelCoachingNeutralRequest, contract: ModelCoachingChessNativeResponseContract,
              continuationID: String?, correlation: HostedCoachingCorrelation) async throws -> HostedCoachingResponse {
        let index = requests.count
        requests.append(request)
        continuations.append(continuationID)
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            maximumConcurrent = max(maximumConcurrent, pending.count)
        }
    }

    func request(at index: Int) async throws -> ModelCoachingNeutralRequest {
        for _ in 0..<2000 {
            if requests.indices.contains(index) { return requests[index] }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw NSError(domain: "Expected request was not dispatched", code: index)
    }
    func callCount() -> Int { requests.count }
    func maximumConcurrentCalls() -> Int { maximumConcurrent }
    func continuation(at index: Int) -> String? { continuations[index] }
    func fail(at index: Int) { pending.removeValue(forKey: index)?.resume(throwing: HostedCoachingTransportError.timedOut) }
    func failAll() {
        let calls = pending
        pending = [:]
        for call in calls.values { call.resume(throwing: CancellationError()) }
    }
    func succeed(at index: Int, message: String, expects: ModelCoachingChessNativeExpectedResponse = .stageMove, requestIDOverride: String? = nil) {
        let request = requests[index]
        pending.removeValue(forKey: index)?.resume(returning: HostedCoachingResponse(
            schemaVersion: "hosted-coaching-turn.v3", requestID: requestIDOverride ?? request.requestID,
            positionRevision: request.positionRevision, promptVersion: "tutor-v13",
            continuationID: "secret-continuation", turn: ModelCoachingChessNativeTurn(
                message: message, actions: ["hint"], focus: [], expects: expects
            ), metrics: HostedCoachingMetrics(inputTokens: 10, cachedInputTokens: 0, outputTokens: 5,
                reasoningTokens: 0, totalTokens: 15, latencyMilliseconds: 20)
        ))
    }
}
