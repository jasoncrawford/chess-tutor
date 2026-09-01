import XCTest
@testable import ChessTutor

@MainActor
final class HostedGameSessionIntegrationTests: XCTestCase {
    func testHostedSelectionQuestionAcceptsPieceTapAndNegativeAnswerAsFastFollowUps() async throws {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)
        session.startCoaching()

        let openingTask = Task { await session.resolvePendingCoachingAdvice() }
        let openingRequest = await provider.waitForOnlyRequest()
        await provider.succeed(
            requestID: openingRequest.requestID,
            message: "Can you find the pawn in danger?",
            actions: ["hint"],
            focus: [.square("f2")],
            expects: .findEndangeredPiece
        )
        await openingTask.value

        XCTAssertEqual(
            .identify(allowsMoveRevision: false),
            session.authoritativeCoachingBoardTask
        )
        XCTAssertEqual(
            ["No piece needs help", "Hint", "Close help"],
            session.coachingPresentation?.actions.map(\.title)
        )

        let pawn = Square(file: .f, rank: 2)
        XCTAssertTrue(session.handleCoachingSquareTap(pawn))
        let selectionID = try XCTUnwrap(session.pendingCoachingRequestID)
        let selectionTask = Task { await session.resolvePendingCoachingAdvice() }
        let selectionRequest = await provider.waitForRequest(id: "hosted-\(selectionID)")
        XCTAssertEqual(.pieceSelected, selectionRequest.interaction.latestEvent.kind)
        XCTAssertEqual(["piece:white:pawn:f2"], selectionRequest.interaction.latestEvent.referencedIDs)

        await provider.succeed(
            requestID: selectionRequest.requestID,
            message: "Now can you find a safe capture?",
            expects: .findSafeCapture
        )
        await selectionTask.value

        XCTAssertEqual(
            ["No safe capture", "Close help"],
            session.coachingPresentation?.actions.map(\.title)
        )

        XCTAssertNil(session.chooseCoachingAction(.noAnswer))
        let absenceID = try XCTUnwrap(session.pendingCoachingRequestID)
        let absenceTask = Task { await session.resolvePendingCoachingAdvice() }
        let absenceRequest = await provider.waitForRequest(id: "hosted-\(absenceID)")
        XCTAssertEqual(.actionChosen, absenceRequest.interaction.latestEvent.kind)
        XCTAssertEqual(["action:noSafeCapture"], absenceRequest.interaction.latestEvent.referencedIDs)
        await provider.succeed(
            requestID: absenceRequest.requestID,
            message: "Good check. Now look for a useful capture."
        )
        await absenceTask.value
    }

    func testHostedEpisodeKeepsCurrentAdviceWhilePieceSelectionStaysLocal() async throws {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)

        session.startCoaching()

        let firstID = try XCTUnwrap(session.pendingCoachingRequestID)
        XCTAssertEqual("Thinking…", session.coachingPresentation?.primaryMessage)
        XCTAssertEqual([.stop], session.coachingPresentation?.actions.map(\.action))
        XCTAssertEqual(.none, session.authoritativeCoachingBoardTask)

        let firstTask = Task { await session.resolvePendingCoachingAdvice() }
        let firstRequest = await provider.waitForRequest(id: "hosted-\(firstID)")
        let firstContinuation = await provider.waitForContinuation(id: firstRequest.requestID)
        XCTAssertNil(firstContinuation)

        let knight = Square(file: .b, rank: 1)
        XCTAssertFalse(session.handleCoachingSquareTap(knight))
        session.select(knight)
        XCTAssertEqual(firstID, session.pendingCoachingRequestID)
        XCTAssertEqual("Thinking…", session.coachingPresentation?.primaryMessage)

        await provider.succeed(
            requestID: firstRequest.requestID,
            message: "What could you notice near the center?",
            continuationID: "resp_opening-123"
        )
        await firstTask.value

        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(
            "What could you notice near the center?",
            session.coachingPresentation?.primaryMessage
        )

        session.select(Square(file: .g, rank: 1))
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(
            "What could you notice near the center?",
            session.coachingPresentation?.primaryMessage
        )
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
        let stagedContinuation = await provider.waitForContinuation(id: stagedRequest.requestID)
        XCTAssertEqual(
            "resp_\(openingRequest.requestID)",
            stagedContinuation
        )
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
        let continuationID: String?
        let continuation: CheckedContinuation<HostedCoachingResponse, Error>
    }

    private var pending: [String: PendingCall] = [:]

    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?
    ) async throws -> HostedCoachingResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.requestID] = PendingCall(
                request: request,
                continuationID: continuationID,
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

    func waitForContinuation(id: String) async -> String? {
        for _ in 0..<1_000 {
            if let call = pending[id] {
                return call.continuationID
            }
            await Task.yield()
        }
        fatalError("Hosted provider did not receive request \(id)")
    }

    func succeed(
        requestID: String,
        message: String,
        actions: [String] = [],
        focus: [ModelCoachingChessNativeFocus] = [],
        expects: ModelCoachingChessNativeExpectedResponse = .none,
        continuationID: String? = nil
    ) {
        guard let call = pending.removeValue(forKey: requestID) else {
            fatalError("Missing hosted request \(requestID)")
        }
        call.continuation.resume(
            returning: HostedCoachingResponse(
                schemaVersion: "hosted-coaching-turn.v3",
                requestID: call.request.requestID,
                positionRevision: call.request.positionRevision,
                promptVersion: "tutor-v11",
                continuationID: continuationID ?? "resp_\(requestID)",
                turn: ModelCoachingChessNativeTurn(
                    message: message,
                    actions: actions,
                    focus: focus,
                    expects: expects
                ),
                metrics: HostedCoachingMetrics(
                    inputTokens: 100,
                    cachedInputTokens: 0,
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
