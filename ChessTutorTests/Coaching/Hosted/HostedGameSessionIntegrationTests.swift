import XCTest
@testable import ChessTutor

@MainActor
final class HostedGameSessionIntegrationTests: XCTestCase {
    func testHostedEpisodeKeepsThinkingVisibleAndRejectsAStaleResponse() async throws {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)

        session.startCoaching()

        let firstID = try XCTUnwrap(session.pendingCoachingRequestID)
        XCTAssertEqual("Thinking…", session.coachingPresentation?.primaryMessage)
        XCTAssertEqual([.stop], session.coachingPresentation?.actions.map(\.action))
        XCTAssertEqual(.none, session.authoritativeCoachingBoardTask)

        let firstTask = Task { await session.resolvePendingCoachingAdvice() }
        let firstRequest = await provider.waitForRequest(id: "hosted-\(firstID)")

        let knight = Square(file: .b, rank: 1)
        XCTAssertFalse(session.handleCoachingSquareTap(knight))
        session.select(knight)
        let secondID = try XCTUnwrap(session.pendingCoachingRequestID)
        XCTAssertGreaterThan(secondID, firstID)
        XCTAssertEqual("Thinking…", session.coachingPresentation?.primaryMessage)

        await provider.succeed(
            requestID: firstRequest.requestID,
            message: "This old answer must not appear."
        )
        await firstTask.value

        XCTAssertEqual(secondID, session.pendingCoachingRequestID)
        XCTAssertEqual("Thinking…", session.coachingPresentation?.primaryMessage)

        let secondTask = Task { await session.resolvePendingCoachingAdvice() }
        let secondRequest = await provider.waitForRequest(id: "hosted-\(secondID)")
        XCTAssertEqual(.pieceSelected, secondRequest.interaction.latestEvent.kind)
        XCTAssertEqual(["piece:white:knight:b1"], secondRequest.interaction.latestEvent.referencedIDs)
        await provider.succeed(
            requestID: secondRequest.requestID,
            message: "What useful square could this knight reach?",
            actions: ["hint"],
            focus: [.square("b1")]
        )
        await secondTask.value

        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(
            "What useful square could this knight reach?",
            session.coachingPresentation?.primaryMessage
        )
        XCTAssertEqual([.hint, .stop], session.coachingPresentation?.actions.map(\.action))
        XCTAssertEqual([knight], session.coachingPresentation?.focus.emphasizedSquares)
    }

    func testHostedEpisodeRecalculatesAfterMoveFailureRetryAndRemovalWithoutLocalFallback() async throws {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)
        session.startCoaching()

        let openingTask = Task { await session.resolvePendingCoachingAdvice() }
        let openingRequest = await provider.waitForOnlyRequest()
        await provider.succeed(
            requestID: openingRequest.requestID,
            message: "Which piece could help near the center?"
        )
        await openingTask.value

        let from = Square(file: .g, rank: 1)
        let to = Square(file: .f, rank: 3)
        session.select(from)
        XCTAssertEqual(.moved, session.moveSelectedPiece(to: to))
        let stagedID = try XCTUnwrap(session.pendingCoachingRequestID)
        let stagedTask = Task { await session.resolvePendingCoachingAdvice() }
        let stagedRequest = await provider.waitForRequest(id: "hosted-\(stagedID)")
        XCTAssertEqual(.moveStaged, stagedRequest.interaction.latestEvent.kind)
        XCTAssertEqual(["move:g1-f3"], stagedRequest.interaction.latestEvent.referencedIDs)

        await provider.fail(requestID: stagedRequest.requestID)
        await stagedTask.value
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual("I couldn't get help right now.", session.coachingPresentation?.primaryMessage)
        XCTAssertEqual([.hint, .stop], session.coachingPresentation?.actions.map(\.action))

        XCTAssertNil(session.chooseCoachingAction(.hint))
        let retryID = try XCTUnwrap(session.pendingCoachingRequestID)
        let retryTask = Task { await session.resolvePendingCoachingAdvice() }
        let retryRequest = await provider.waitForRequest(id: "hosted-\(retryID)")
        XCTAssertEqual(.helpReopened, retryRequest.interaction.latestEvent.kind)
        await provider.succeed(
            requestID: retryRequest.requestID,
            message: "How does your knight help from f3?",
            actions: ["playMove", "tryAnotherMove"],
            focus: [.move(from: "g1", to: "f3")]
        )
        await retryTask.value

        XCTAssertEqual([.done, .keepLooking, .stop], session.coachingPresentation?.actions.map(\.action))
        XCTAssertNil(session.chooseCoachingAction(.keepLooking))
        XCTAssertNil(session.state.board[to])
        XCTAssertNotNil(session.state.board[from])
        let removalID = try XCTUnwrap(session.pendingCoachingRequestID)
        let removalTask = Task { await session.resolvePendingCoachingAdvice() }
        let removalRequest = await provider.waitForRequest(id: "hosted-\(removalID)")
        XCTAssertEqual(.moveRemoved, removalRequest.interaction.latestEvent.kind)
        await provider.succeed(
            requestID: removalRequest.requestID,
            message: "What else could you try?"
        )
        await removalTask.value

        XCTAssertNil(session.chooseCoachingAction(.stop))
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertNil(session.coachingPresentation)
    }

    func testHostedPlayMoveUsesTheExistingFinishTurnPath() async throws {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)
        let move = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )
        session.select(move.from)
        XCTAssertEqual(.moved, session.moveSelectedPiece(to: move.to))
        session.startCoaching()

        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await provider.waitForOnlyRequest()
        await provider.succeed(
            requestID: request.requestID,
            message: "How does this move help your knight?",
            actions: ["playMove", "tryAnotherMove"]
        )
        await task.value

        XCTAssertEqual(move, session.chooseCoachingAction(.done))
        XCTAssertEqual(.black, session.state.sideToMove)
        XCTAssertEqual(1, session.state.moveHistory.count)
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertNil(session.pendingCoachingRequestID)
    }
}

private actor ControlledHostedCoachingProvider: HostedCoachingTurning {
    private struct PendingCall {
        let request: ModelCoachingNeutralRequest
        let continuation: CheckedContinuation<HostedCoachingResponse, Error>
    }

    private var pending: [String: PendingCall] = [:]

    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract
    ) async throws -> HostedCoachingResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.requestID] = PendingCall(
                request: request,
                continuation: continuation
            )
        }
    }

    func waitForOnlyRequest() async -> ModelCoachingNeutralRequest {
        for _ in 0..<1_000 {
            if let request = pending.values.first?.request {
                return request
            }
            await Task.yield()
        }
        fatalError("Hosted provider did not receive a request")
    }

    func waitForRequest(id: String) async -> ModelCoachingNeutralRequest {
        for _ in 0..<1_000 {
            if let request = pending[id]?.request {
                return request
            }
            await Task.yield()
        }
        fatalError("Hosted provider did not receive request \(id)")
    }

    func succeed(
        requestID: String,
        message: String,
        actions: [String] = [],
        focus: [ModelCoachingChessNativeFocus] = []
    ) {
        guard let call = pending.removeValue(forKey: requestID) else {
            fatalError("Missing hosted request \(requestID)")
        }
        call.continuation.resume(
            returning: HostedCoachingResponse(
                schemaVersion: "hosted-coaching-turn.v1",
                requestID: call.request.requestID,
                positionRevision: call.request.positionRevision,
                promptVersion: "tutor-v6",
                turn: ModelCoachingChessNativeTurn(
                    message: message,
                    actions: actions,
                    focus: focus
                ),
                metrics: HostedCoachingMetrics(
                    inputTokens: 100,
                    outputTokens: 20,
                    reasoningTokens: 5,
                    totalTokens: 120,
                    latencyMilliseconds: 50
                )
            )
        )
    }

    func fail(requestID: String) {
        guard let call = pending.removeValue(forKey: requestID) else {
            fatalError("Missing hosted request \(requestID)")
        }
        call.continuation.resume(throwing: HostedCoachingTransportError.serverUnavailable)
    }
}
