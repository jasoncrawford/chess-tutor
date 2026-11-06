import Foundation
import XCTest
@testable import ChessTutor

@MainActor
final class HostedGameSessionIntegrationTests: XCTestCase {
    func testCurrentCoachingGameIDIsHostedOnlyAndChangesForNewGame() {
        var identifiers = [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
        ]
        let hosted = GameSession(
            hostedCoachingProvider: ControlledHostedCoachingProvider(),
            coachingIdentifierFactory: { identifiers.removeFirst() }
        )
        let local = GameSession(
            coachingIdentifierFactory: {
                "33333333-3333-4333-8333-333333333333"
            }
        )

        XCTAssertEqual(
            "11111111-1111-4111-8111-111111111111",
            hosted.currentCoachingGameID
        )
        XCTAssertNil(local.currentCoachingGameID)

        hosted.newGame()

        XCTAssertEqual(
            "22222222-2222-4222-8222-222222222222",
            hosted.currentCoachingGameID
        )
        XCTAssertTrue(identifiers.isEmpty)
    }

    func testHostedCorrelationKeepsGameAndEpisodeLifetimesSeparate() async throws {
        let provider = ControlledHostedCoachingProvider()
        var identifiers = [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
            "33333333-3333-4333-8333-333333333333",
            "44444444-4444-4444-8444-444444444444",
            "55555555-5555-4555-8555-555555555555",
        ]
        let session = GameSession(
            hostedCoachingProvider: provider,
            coachingIdentifierFactory: { identifiers.removeFirst() }
        )

        session.startCoaching()
        let firstTask = Task { await session.resolvePendingCoachingAdvice() }
        let first = await provider.waitForOnlyCorrelation()
        await provider.succeed(
            requestID: "hosted-1",
            message: "What do you notice?",
            actions: ["hint"]
        )
        await firstTask.value

        XCTAssertNil(session.chooseCoachingAction(.hint))
        let followUpTask = Task { await session.resolvePendingCoachingAdvice() }
        let followUp = await provider.waitForCorrelation(id: "hosted-2")
        await provider.succeed(requestID: "hosted-2", message: "Look near the center.")
        await followUpTask.value
        XCTAssertEqual(first, followUp)

        session.stopCoaching()
        session.startCoaching()
        let reopenedTask = Task { await session.resolvePendingCoachingAdvice() }
        let reopened = await provider.waitForCorrelation(id: "hosted-3")
        await provider.succeed(requestID: "hosted-3", message: "What changed?")
        await reopenedTask.value
        XCTAssertEqual(first.gameID, reopened.gameID)
        XCTAssertNotEqual(first.episodeID, reopened.episodeID)

        session.newGame()
        session.startCoaching()
        let newGameTask = Task { await session.resolvePendingCoachingAdvice() }
        let newGame = await provider.waitForCorrelation(id: "hosted-4")
        await provider.succeed(requestID: "hosted-4", message: "New game.")
        await newGameTask.value
        XCTAssertNotEqual(first.gameID, newGame.gameID)
        XCTAssertNotEqual(reopened.episodeID, newGame.episodeID)
        XCTAssertTrue(identifiers.isEmpty)
    }

    func testHostedCorrelationUsesLowercaseCanonicalUUIDsByDefault() async {
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(hostedCoachingProvider: provider)

        session.startCoaching()
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let correlation = await provider.waitForOnlyCorrelation()
        await provider.fail(requestID: "hosted-1")
        await task.value

        for value in [correlation.gameID, correlation.episodeID] {
            XCTAssertEqual(value, value.lowercased())
            XCTAssertEqual(value, UUID(uuidString: value)?.uuidString.lowercased())
        }
    }

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
            focus: [],
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

    func testHostedIdentificationAllowsTapCaptureAfterSelectingMover() async throws {
        let state = try middlegamePlaythroughState()
        let from = Square(file: .c, rank: 4)
        let to = Square(file: .e, rank: 6)
        for expects in [ModelCoachingChessNativeExpectedResponse.findEndangeredPiece, .findSafeCapture] {
            for showsMoves in [true, false] {
                let provider = ControlledHostedCoachingProvider()
                let session = GameSession(state: state, hostedCoachingProvider: provider)
                session.assistSettings.showLegalMovesOnSelection = showsMoves
                session.startCoaching()
                await answerPending(session, using: provider, expects: expects)

                XCTAssertTrue(session.handleCoachingSquareTap(from))
                await answerPending(session, using: provider, expects: expects)

                // Follow the board's real routing: only attempt movement if coaching
                // did not consume the tap as an identification answer.
                if !session.handleCoachingSquareTap(to) {
                    XCTAssertEqual(.moved, session.moveSelectedPiece(to: to))
                }
                XCTAssertTrue(session.canFinishTurn)
                XCTAssertEqual(Piece(kind: .bishop, color: .white), session.state.board[to])
                let task = Task { await session.resolvePendingCoachingAdvice() }
                let request = await provider.waitForOnlyRequest()
                XCTAssertEqual(.moveStaged, request.interaction.latestEvent.kind)
                XCTAssertEqual("c4e6", request.interaction.tentativeMove?.canonicalMove)
                XCTAssertEqual(["move:c4-e6"], request.interaction.latestEvent.referencedIDs)
                // The real request carries the possible pawn recapture, not an
                // invented claim that winning the queen also saves the bishop.
                XCTAssertTrue(request.tentativeReplies.contains { $0.canonicalMove == "f7e6" })
                await provider.succeed(
                    requestID: request.requestID,
                    message: "Keep this trade?",
                    expects: .chooseWhetherToPlay
                )
                await task.value
                XCTAssertEqual([.done, .keepLooking, .stop], session.coachingPresentation?.actions.map(\.action))
            }
        }
    }

    func testHostedIdentificationStillAcceptsTapsWithoutAnActionableDestination() async throws {
        let state = try middlegamePlaythroughState()
        let bishop = Square(file: .c, rank: 4)
        let whiteQueen = Square(file: .g, rank: 4)
        let blackQueen = Square(file: .e, rank: 6)
        let blackKnight = Square(file: .c, rank: 6)
        let selections: [(Square?, Square, String)] = [
            (nil, blackQueen, "piece:black:queen:e6"),
            (bishop, whiteQueen, "piece:white:queen:g4"),
            (bishop, blackKnight, "piece:black:knight:c6"),
            (blackQueen, bishop, "piece:white:bishop:c4"),
        ]
        for (selected, tapped, reference) in selections {
            let provider = ControlledHostedCoachingProvider()
            let session = GameSession(state: state, hostedCoachingProvider: provider)
            if let selected { session.select(selected) }
            session.startCoaching()
            await answerPending(session, using: provider, expects: .findEndangeredPiece)
            XCTAssertTrue(session.handleCoachingSquareTap(tapped))
            XCTAssertEqual(state.board, session.state.board)
            let task = Task { await session.resolvePendingCoachingAdvice() }
            let request = await provider.waitForOnlyRequest()
            XCTAssertEqual(.pieceSelected, request.interaction.latestEvent.kind)
            XCTAssertEqual([reference], request.interaction.latestEvent.referencedIDs)
            XCTAssertNil(request.interaction.tentativeMove)
            await provider.succeed(requestID: request.requestID, message: "Try a move.", expects: .stageMove)
            await task.value
        }
    }

    func testHostedIdentificationAllowsPinnedCaptureToStageButNotCommit() async throws {
        let from = Square(file: .e, rank: 2)
        let to = Square(file: .d, rank: 2)
        let state = GameState(board: Board(pieces: [
            Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
            from: Piece(kind: .rook, color: .white),
            Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
            to: Piece(kind: .knight, color: .black),
        ]), sideToMove: .white)
        let provider = ControlledHostedCoachingProvider()
        let session = GameSession(state: state, hostedCoachingProvider: provider)
        session.select(from)
        session.startCoaching()
        await answerPending(session, using: provider, expects: .findSafeCapture)
        if !session.handleCoachingSquareTap(to) {
            XCTAssertEqual(.moved, session.moveSelectedPiece(to: to))
        }
        XCTAssertEqual(Piece(kind: .rook, color: .white), session.state.board[to])
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.finishTurn())
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await provider.waitForOnlyRequest()
        XCTAssertEqual(.moveStaged, request.interaction.latestEvent.kind)
        XCTAssertEqual(false, request.interaction.tentativeMove?.isLegal)
        await provider.succeed(requestID: request.requestID, message: "Your king needs help.", expects: .judgeMoveSafety)
        await task.value
    }

    private func middlegamePlaythroughState() throws -> GameState {
        let history = [
            "e4", "e5", "Bc4", "Nf6", "d3", "Nc6", "Nf3", "d6", "O-O", "Be7", "Nc3", "O-O",
            "Bg5", "h6", "Bxf6", "Bxf6", "Nd5", "Qd7", "Nxf6+", "gxf6", "Nh4", "Kh7",
            "Qh5", "f5", "exf5", "Qe7", "f6", "Qxf6", "Nf3", "Bg4", "Qxg4", "Qe6",
        ]
        var state = GameState.startingPosition()
        for san in history {
            let move = try XCTUnwrap(LegalMoveGenerator.allLegalMoves(in: state).first {
                MoveHistoryFormatter.notation(for: $0, in: state) == san
            }, "Every recorded playthrough move must be legal: \(san)")
            state.apply(move)
        }
        XCTAssertEqual(
            "r4r2/ppp2p1k/2npq2p/4p3/2B3Q1/3P1N2/PPP2PPP/R4RK1 w - - 1 17",
            ModelCoachingPositionEncoder.fen(for: state)
        )
        return state
    }

    private func answerPending(
        _ session: GameSession,
        using provider: ControlledHostedCoachingProvider,
        expects: ModelCoachingChessNativeExpectedResponse
    ) async {
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await provider.waitForOnlyRequest()
        await provider.succeed(requestID: request.requestID, message: "Which piece?", expects: expects)
        await task.value
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
        let correlation: HostedCoachingCorrelation
        let continuation: CheckedContinuation<HostedCoachingResponse, Error>
    }

    private var pending: [String: PendingCall] = [:]

    func turn(
        for request: ModelCoachingNeutralRequest,
        contract: ModelCoachingChessNativeResponseContract,
        continuationID: String?,
        correlation: HostedCoachingCorrelation
    ) async throws -> HostedCoachingResponse {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.requestID] = PendingCall(
                request: request,
                continuationID: continuationID,
                correlation: correlation,
                continuation: continuation
            )
        }
    }

    func waitForOnlyRequest() async -> ModelCoachingNeutralRequest {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let request = pending.values.first?.request {
                return request
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Hosted provider did not receive a request")
    }

    func waitForRequest(id: String) async -> ModelCoachingNeutralRequest {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let request = pending[id]?.request {
                return request
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Hosted provider did not receive request \(id)")
    }

    func waitForContinuation(id: String) async -> String? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let call = pending[id] {
                return call.continuationID
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Hosted provider did not receive request \(id)")
    }

    func waitForOnlyCorrelation() async -> HostedCoachingCorrelation {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let correlation = pending.values.first?.correlation {
                return correlation
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Hosted provider did not receive a correlation")
    }

    func waitForCorrelation(id: String) async -> HostedCoachingCorrelation {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let correlation = pending[id]?.correlation {
                return correlation
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Hosted provider did not receive correlation for \(id)")
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
                promptVersion: "tutor-v13",
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
