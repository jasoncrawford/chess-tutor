import XCTest
@testable import ChessTutor

@MainActor
final class GameSessionCoachingTests: XCTestCase {
    func testPendingAdviceShowsCloseHelpAndStaleCompletionCannotReopenIt() async {
        let advisor = ControllableCoachingAdvisor()
        let session = GameSession(coachingAdvisor: advisor)

        session.startCoaching()
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await waitForOnlyPendingRequest(advisor)

        XCTAssertEqual(session.coachingPresentation?.primaryMessage, "I'm checking the board.")
        XCTAssertNil(session.coachingPresentation?.instruction)
        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(session.coachingPresentation?.actions.map(\.action), [.stop])
        XCTAssertEqual(session.coachingPresentation?.boardTask, CoachingBoardTask.none)
        XCTAssertEqual(session.coachingPresentation?.focus, .empty)

        XCTAssertNil(session.chooseCoachingAction(.stop))
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertNil(session.coachingPresentation)

        await advisor.resolve(
            request: request,
            with: CoachingTestFixtures.startingPositionAdvice.replacingRequest(with: request)
        )
        await task.value

        XCTAssertFalse(session.isCoachingActive)
        XCTAssertNil(session.coachingPresentation)
        XCTAssertNil(session.pendingCoachingRequestID)
    }

    func testHelpAvailabilityRequiresOngoingUnlockedLocalTurnWithoutPromotionOrEpisode() {
        let session = GameSession()
        XCTAssertTrue(session.canRequestCoaching)

        session.startCoaching()
        XCTAssertFalse(session.canRequestCoaching)
        session.stopCoaching()

        session.whitePlayer = .remote(playerID: "maya")
        XCTAssertFalse(session.canRequestCoaching)
        session.whitePlayer = .humanLocal

        session.endRemoteGame(message: "Maya ended this game.")
        XCTAssertFalse(session.canRequestCoaching)
        session.newGame()

        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        let promotionSession = GameSession(state: promotionState())
        promotionSession.select(promotionFrom)
        XCTAssertEqual(
            promotionSession.moveSelectedPiece(to: promotionTo),
            .needsPromotion(from: promotionFrom, to: promotionTo)
        )
        XCTAssertTrue(promotionSession.isAwaitingPromotionChoice)
        XCTAssertFalse(promotionSession.canRequestCoaching)
        promotionSession.cancelPromotionChoice()
        XCTAssertFalse(promotionSession.isAwaitingPromotionChoice)
        XCTAssertTrue(promotionSession.canRequestCoaching)
    }

    func testHelpUnavailableForCheckmateAndStalemate() {
        let checkmate = GameSession(state: terminalState(result: .checkmate(winner: .black)))
        let stalemate = GameSession(state: terminalState(result: .stalemate))

        XCTAssertFalse(checkmate.canRequestCoaching)
        XCTAssertFalse(stalemate.canRequestCoaching)
    }

    func testStartingFromQuietLegalTentativeMoveGoesDirectlyToCompletion() async {
        let move = CoachingTestFixtures.openingKnightMove
        let advice = tentativeAdvice(for: move, isLegal: true)
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(advice: advice)
        )
        stage(move, in: session)

        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.isCoachingActive)
        XCTAssertEqual(session.coachingPresentation?.boardTask, CoachingBoardTask.none)
        XCTAssertEqual(session.state.board[move.to], Piece(kind: .knight, color: .white))
    }

    func testStartingFromCheckIllegalTentativeMovePreservesItAndRequestsRevision() async {
        let move = Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .f, rank: 2)
        )
        let session = GameSession(
            state: pinnedRookState(),
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(for: move, isLegal: false)
            )
        )
        stage(move, in: session)
        XCTAssertFalse(session.canFinishTurn)

        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
        XCTAssertEqual(session.coachingPresentation?.primaryMessage, "That move leaves your king in check.")
        XCTAssertEqual(session.coachingPresentation?.instruction, "Try another move.")
        XCTAssertEqual(session.state.board[move.to], Piece(kind: .rook, color: .white))
    }

    func testIdentificationConsumesIncorrectTapWithoutSelectingOrClearingTentativeMove() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issueSquare = Square(file: .a, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare, move.to]
        )
        let advice = tentativeAdvice(
            for: move,
            isLegal: true,
            issues: [issue],
            opponentActivities: [CoachingTestFixtures.opponentActivity(
                reply: issue.reply,
                opponentPiece: .pawn,
                capturedSquare: move.to,
                capturedPiece: .knight,
                netGainForOpponent: 3
            )]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(advice: advice)
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        let selection = session.selectedSquare
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        let consumed = session.handleCoachingSquareTap(Square(file: .b, rank: 7))

        XCTAssertTrue(consumed)
        XCTAssertEqual(session.state.board, tentativeBoard)
        XCTAssertEqual(session.selectedSquare, selection)
    }

    func testIdentificationConsumesCorrectAndIncorrectTapsWithoutChangingOrdinarySelection() async {
        let session = GameSession(
            state: CoachingTestFixtures.coachingState,
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.multipleDangerAdvice
            )
        )
        session.select(CoachingTestFixtures.whiteRook)
        let selectedBeforeCoaching = session.selectedSquare
        let boardBeforeCoaching = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .a, rank: 2)))
        XCTAssertEqual(session.selectedSquare, selectedBeforeCoaching)
        XCTAssertEqual(session.state.board, boardBeforeCoaching)

        XCTAssertTrue(session.handleCoachingSquareTap(CoachingTestFixtures.whiteQueen))
        XCTAssertEqual(session.selectedSquare, selectedBeforeCoaching)
        XCTAssertEqual(session.state.board, boardBeforeCoaching)
    }

    func testAbsenceIsAnsweredByPanelActionRatherThanBoardTap() async {
        let session = GameSession(
            state: CoachingTestFixtures.coachingState,
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.nontrivialSafeClearAdvice
            )
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
        let originalHeadline = session.coachingPresentation?.primaryMessage
        let originalRoutine = session.coachingPresentation?.routine

        XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .c, rank: 3)))
        XCTAssertEqual(session.coachingPresentation?.routine, originalRoutine)

        _ = session.chooseCoachingAction(.noAnswer)
        XCTAssertNotEqual(session.coachingPresentation?.primaryMessage, originalHeadline)
        XCTAssertNotEqual(session.coachingPresentation?.routine, originalRoutine)
    }

    func testTruthfulNoSafeCaptureAfterUnsafeCandidateClearsCandidateAndAdvances() async {
        let originalState = CoachingGoldenPosition.losingCapture.state
        let move = CoachingGoldenMoves.bishopTakesPawn
        let session = GameSession(
            state: originalState,
            coachingAdvisor: LocalCoachingAdvisor()
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "Black's king could take your bishop, so you would lose it for a pawn."
        )
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.noAnswer, .stop]
        )

        _ = session.chooseCoachingAction(.noAnswer)

        XCTAssertEqual(session.state, originalState)
        XCTAssertNil(session.selectedSquare)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "There is no safe capture here."
        )
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "What move would you like to try?"
        )
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.stop]
        )
    }

    func testMoveTaskAlwaysPassesBoardTapThroughToOrdinaryHandling() async {
        let session = GameSession(
            state: CoachingTestFixtures.coachingState,
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.fallbackAdvice
            )
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
        XCTAssertFalse(session.handleCoachingSquareTap(CoachingTestFixtures.whiteQueen))
    }

    func testAcceptedOpponentIssueTapIsConsumedBeforeMoveRevisionRouting() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: CoachingTestFixtures.blackBishop, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [move.to]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .knight,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareTap(issue.reply.from))
        XCTAssertEqual(session.state.board, tentativeBoard)
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
    }

    func testAcceptedOpponentIssueDragStartIsConsumedBeforeMoveRevisionRouting() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: CoachingTestFixtures.blackBishop, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [move.to]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .knight,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareDragStart(issue.reply.from))
        XCTAssertEqual(session.state.board, tentativeBoard)
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
    }

    func testOpponentCheckConsumesTapOnStagedPieceWhenItIsNotAnAcceptedAnswer() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issueSquare = Square(file: .a, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .pawn,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareTap(move.to))
        XCTAssertEqual(session.state.board, tentativeBoard)
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertEqual(
            session.coachingPresentation?.boardTask,
            .identify(allowsMoveRevision: true)
        )
    }

    func testOpponentCheckPassesDragFromStagedPieceToOrdinaryRevisionHandling() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issueSquare = Square(file: .a, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .pawn,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertFalse(session.handleCoachingSquareDragStart(move.to))
        XCTAssertEqual(session.prepareDrag(from: move.to), move.from)
        XCTAssertEqual(
            session.state.board[move.from],
            Piece(kind: .knight, color: .white)
        )
        XCTAssertNil(session.state.board[move.to])
        XCTAssertEqual(session.selectedSquare, move.from)
        assertAwaitingAdvice(session)
        XCTAssertNotNil(session.pendingCoachingRequestID)
    }

    func testOpponentCheckPassesActionableRevisionSourceToOrdinaryBoardHandling() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issueSquare = Square(file: .a, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare, move.to]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .pawn,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertFalse(session.handleCoachingSquareTap(CoachingTestFixtures.alternateKnight))

        session.select(CoachingTestFixtures.alternateKnight)
        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.alternateKnight)
        XCTAssertEqual(
            session.state.board[move.from],
            Piece(kind: .knight, color: .white)
        )
        XCTAssertNil(session.state.board[move.to])
        assertAwaitingAdvice(session)
        XCTAssertNotNil(session.pendingCoachingRequestID)
    }

    func testOpponentCheckPassesActionableReplacementDestinationToExistingStagingPath() async {
        let move = CoachingTestFixtures.openingKnightMove
        let replacementDestination = Square(file: .a, rank: 3)
        let issueSquare = Square(file: .a, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare, move.to]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .pawn,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertFalse(session.handleCoachingSquareTap(replacementDestination))
        XCTAssertEqual(session.tapEmptySquare(at: replacementDestination), .moved)
        XCTAssertEqual(
            session.state.board[replacementDestination],
            Piece(kind: .knight, color: .white)
        )
    }

    func testOpponentCheckConsumesNonactionableNonanswerTap() async {
        let move = CoachingTestFixtures.openingKnightMove
        let issueSquare = Square(file: .a, rank: 7)
        let unrelatedOpponentPiece = Square(file: .b, rank: 7)
        let issue = CoachingTestFixtures.issue(
            reply: Move(from: issueSquare, to: move.to),
            kind: .materialLoss(points: 3),
            severity: .reviseMove,
            answers: [issueSquare, move.to]
        )
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(
                    for: move,
                    isLegal: true,
                    issues: [issue],
                    opponentActivities: [CoachingTestFixtures.opponentActivity(
                        reply: issue.reply,
                        opponentPiece: .pawn,
                        capturedSquare: move.to,
                        capturedPiece: .knight,
                        netGainForOpponent: 3
                    )]
                )
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareTap(unrelatedOpponentPiece))
        XCTAssertEqual(session.state.board, tentativeBoard)
        XCTAssertEqual(session.selectedSquare, move.to)
    }

    func testWakeTapFallsThroughToExistingSelectionPath() async {
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.startingPositionAdvice
            )
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertFalse(session.handleCoachingSquareTap(CoachingTestFixtures.openingKnight))
        session.select(CoachingTestFixtures.openingKnight)
        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.openingKnight)
        XCTAssertTrue(session.legalDestinations.contains(CoachingTestFixtures.openingKnightMove.to))
        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
    }

    func testOpeningCoachRecalculatesWhenSelectionChangesFromKnightToBlockedRook() async {
        let session = await makeOpeningSession()

        session.select(CoachingTestFixtures.openingKnight)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")

        let blockedRook = Square(file: .a, rank: 1)
        session.select(blockedRook)

        XCTAssertEqual(session.selectedSquare, blockedRook)
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "Your pawn blocks that rook."
        )
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Tap a center pawn or knight."
        )
        XCTAssertNil(session.pendingCoachingRequestID)
    }

    func testBlockedRookHintClearsResponseAndRestoresCurrentAskWithoutChangingSelection() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        await beginOpeningCoaching(in: session)
        let blockedRook = Square(file: .a, rank: 1)
        session.select(blockedRook)
        let boardBeforeHint = session.state.board
        let destinationsBeforeHint = session.legalDestinations

        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "Your pawn blocks that rook."
        )

        _ = session.chooseCoachingAction(.hint)

        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Here are the four pieces you can try."
        )
        XCTAssertEqual(session.coachingPresentation?.instruction, "Tap a highlighted piece.")
        XCTAssertEqual(
            session.coachingPresentation?.focus.candidateSquares,
            [
                Square(file: .b, rank: 1),
                Square(file: .d, rank: 2),
                Square(file: .e, rank: 2),
                Square(file: .g, rank: 1),
            ]
        )
        XCTAssertEqual(session.selectedSquare, blockedRook)
        XCTAssertEqual(session.legalDestinations, destinationsBeforeHint)
        XCTAssertEqual(session.state.board, boardBeforeHint)
    }

    func testOpeningHintClearsPriorMissButStillShowsANewMiss() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        await beginOpeningCoaching(in: session)
        session.select(Square(file: .a, rank: 1))
        XCTAssertNotNil(session.coachingPresentation?.observation)

        _ = session.chooseCoachingAction(.hint)
        XCTAssertNil(session.coachingPresentation?.observation)

        session.select(Square(file: .a, rank: 7))

        XCTAssertEqual(session.coachingPresentation?.observation, "That is not one of your pieces.")
    }

    func testOpeningBlockedRookPresentationDoesNotDependOnPriorKnightSelection() async {
        let direct = await makeOpeningSession()
        let switched = await makeOpeningSession()
        let blockedRook = Square(file: .a, rank: 1)

        direct.select(blockedRook)
        switched.select(CoachingTestFixtures.openingKnight)
        switched.select(blockedRook)

        XCTAssertEqual(switched.selectedSquare, blockedRook)
        XCTAssertEqual(switched.coachingPresentation, direct.coachingPresentation)
    }

    func testOpeningCandidateSwitchAndEmptyTapFollowCurrentSelection() async {
        let directAlternate = await makeOpeningSession()
        directAlternate.select(CoachingTestFixtures.alternateKnight)

        let switched = await makeOpeningSession()
        let sourceChoice = switched.coachingPresentation
        switched.select(CoachingTestFixtures.openingKnight)
        switched.select(CoachingTestFixtures.alternateKnight)

        XCTAssertEqual(switched.selectedSquare, CoachingTestFixtures.alternateKnight)
        XCTAssertEqual(switched.coachingPresentation, directAlternate.coachingPresentation)
        XCTAssertNil(switched.pendingCoachingRequestID)

        XCTAssertNil(switched.tapEmptySquare(at: Square(file: .e, rank: 4)))
        XCTAssertNil(switched.selectedSquare)
        XCTAssertEqual(switched.coachingPresentation, sourceChoice)
        XCTAssertNil(switched.pendingCoachingRequestID)
    }

    func testTentativeMoveReplacementProjectionMatchesDirectCurrentMove() async {
        let currentMove = CoachingTestFixtures.alternateKnightMove
        let direct = await makeOpeningSession()
        stage(currentMove, in: direct)
        await direct.resolvePendingCoachingAdvice()

        let historyRich = await makeOpeningSession()
        stage(CoachingTestFixtures.openingKnightMove, in: historyRich)
        await historyRich.resolvePendingCoachingAdvice()
        historyRich.select(currentMove.from)
        stage(currentMove, in: historyRich)
        await historyRich.resolvePendingCoachingAdvice()

        XCTAssertEqual(historyRich.selectedSquare, direct.selectedSquare)
        XCTAssertEqual(historyRich.state.board, direct.state.board)
        XCTAssertEqual(historyRich.coachingPresentation, direct.coachingPresentation)
        XCTAssertEqual(historyRich.pendingCoachingRequestID, direct.pendingCoachingRequestID)
    }

    func testOutsidePawnMatchesDirectDerivationAfterFullReportedInteractionHistory() async {
        let move = CoachingGoldenMoves.outsidePawn
        let direct = await makeOpeningSession()
        stage(move, in: direct)
        await direct.resolvePendingCoachingAdvice()

        let historyRich = await makeOpeningSession()
        historyRich.select(CoachingTestFixtures.openingKnight)
        historyRich.select(Square(file: .a, rank: 1))
        historyRich.select(Square(file: .a, rank: 2))
        historyRich.select(Square(file: .a, rank: 7))
        XCTAssertNil(historyRich.tapEmptySquare(at: Square(file: .e, rank: 4)))
        _ = historyRich.chooseCoachingAction(.hint)
        stage(CoachingTestFixtures.openingKnightMove, in: historyRich)
        await historyRich.resolvePendingCoachingAdvice()
        stage(move, in: historyRich)
        await historyRich.resolvePendingCoachingAdvice()

        XCTAssertEqual(historyRich.selectedSquare, direct.selectedSquare)
        XCTAssertEqual(historyRich.state.board, direct.state.board)
        XCTAssertEqual(historyRich.coachingPresentation, direct.coachingPresentation)
        XCTAssertEqual(historyRich.coachingPresentation?.focus, direct.coachingPresentation?.focus)
        XCTAssertEqual(historyRich.state.moveHistory, [])
        XCTAssertEqual(historyRich.state.moveHistory, direct.state.moveHistory)
        XCTAssertEqual(historyRich.pendingCoachingRequestID, direct.pendingCoachingRequestID)
    }

    func testOpeningSourceFeedbackTracksPawnRookEmptyAndEnemySwitches() async {
        let session = await makeOpeningSession()

        session.select(CoachingTestFixtures.openingKnight)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")

        session.select(Square(file: .a, rank: 2))
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "That pawn is outside the center."
        )
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )

        session.select(Square(file: .a, rank: 1))
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "Your pawn blocks that rook."
        )

        session.select(Square(file: .e, rank: 4))
        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )

        session.select(Square(file: .a, rank: 7))
        XCTAssertEqual(session.selectedSquare, Square(file: .a, rank: 7))
        XCTAssertEqual(session.coachingPresentation?.observation, "That is not one of your pieces.")
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Tap a center pawn or knight."
        )
        XCTAssertNil(session.pendingCoachingRequestID)
    }

    func testConcreteWakeEntriesFlowThroughGameSession() async {
        let cases: [(
            position: CoachingGoldenPosition,
            ask: String,
            instruction: String
        )] = [
            (
                .createRookThreat,
                "Your knight can attack Black's rook.",
                "Move the knight to attack the rook."
            ),
            (
                .cornerKnight,
                "Your knight has only two moves in this corner.",
                "Move it closer to the center."
            ),
        ]

        for testCase in cases {
            let session = GameSession(
                state: testCase.position.state,
                coachingAdvisor: LocalCoachingAdvisor()
            )
            session.startCoaching()
            await session.resolvePendingCoachingAdvice()

            XCTAssertEqual(session.coachingPresentation?.primaryMessage, testCase.ask)
            XCTAssertEqual(session.coachingPresentation?.instruction, testCase.instruction)
        }
    }

    func testCanonicalCastleEntryFollowsSafeAndTakeAbsenceChecks() async {
        let session = GameSession(
            state: CoachingGoldenPosition.readyToCastle.state,
            coachingAdvisor: LocalCoachingAdvisor()
        )
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Which of your pieces is in danger?"
        )

        _ = session.chooseCoachingAction(.noAnswer)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Can one of your pieces safely take a black piece?"
        )

        _ = session.chooseCoachingAction(.noAnswer)
        XCTAssertEqual(session.coachingPresentation?.primaryMessage, "Your king is ready to castle.")
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Move your king two squares toward the rook."
        )
    }

    func testOpeningTapAndDragSourceSelectionProduceTheSameCoachingResult() async {
        let tapped = await makeOpeningSession()
        let dragged = await makeOpeningSession()
        let source = CoachingTestFixtures.openingKnight

        XCTAssertFalse(tapped.handleCoachingSquareTap(source))
        tapped.select(source)

        XCTAssertFalse(dragged.handleCoachingSquareDragStart(source))
        XCTAssertEqual(dragged.prepareDrag(from: source), source)

        XCTAssertEqual(dragged.selectedSquare, source)
        XCTAssertEqual(dragged.coachingPresentation, tapped.coachingPresentation)
        XCTAssertNil(tapped.pendingCoachingRequestID)
        XCTAssertNil(dragged.pendingCoachingRequestID)
    }

    func testSelectionOnlyPathsQueueNoAdviceAndNewlyStagedMoveQueuesExactlyOneRequest() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        session.startCoaching()
        let initialRequestID = session.pendingCoachingRequestID
        await session.resolvePendingCoachingAdvice()

        session.select(CoachingTestFixtures.openingKnight)
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")

        XCTAssertNil(session.tapEmptySquare(at: Square(file: .e, rank: 4)))
        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.pendingCoachingRequestID)

        XCTAssertEqual(
            session.prepareDrag(from: CoachingTestFixtures.alternateKnight),
            CoachingTestFixtures.alternateKnight
        )
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")

        XCTAssertEqual(
            session.moveSelectedPiece(to: CoachingTestFixtures.alternateKnightMove.to),
            .moved
        )
        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.alternateKnightMove.to)
        XCTAssertEqual(session.pendingCoachingRequestID, initialRequestID.map { $0 + 1 })
    }

    func testTentativeSelectionReplacementSynchronizesOnlyTheFinalRestoredSource() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        stage(CoachingTestFixtures.openingKnightMove, in: session)
        session.select(CoachingTestFixtures.alternateKnight)
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.alternateKnight)
        XCTAssertNil(session.state.board[CoachingTestFixtures.openingKnightMove.to])
        XCTAssertEqual(
            session.state.board[CoachingTestFixtures.openingKnightMove.from],
            Piece(kind: .knight, color: .white)
        )
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")
    }

    func testTentativeDragRestorationSynchronizesOnlyTheFinalRestoredSource() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
        let move = CoachingTestFixtures.openingKnightMove

        stage(move, in: session)
        XCTAssertEqual(session.prepareDrag(from: move.to), move.from)
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(session.selectedSquare, move.from)
        XCTAssertNil(session.state.board[move.to])
        XCTAssertEqual(session.state.board[move.from], Piece(kind: .knight, color: .white))
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move the knight.")
    }

    func testTentativeReplacementRestorationAndPromotionPublishFinalBoardFacts() async {
        let replacementSession = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        replacementSession.startCoaching()
        await replacementSession.resolvePendingCoachingAdvice()
        stage(CoachingTestFixtures.openingKnightMove, in: replacementSession)

        let replacement = Move(
            from: CoachingTestFixtures.openingKnight,
            to: Square(file: .a, rank: 3)
        )
        XCTAssertEqual(replacementSession.tapEmptySquare(at: replacement.to), .moved)
        XCTAssertEqual(replacementSession.selectedSquare, replacement.to)
        XCTAssertEqual(
            replacementSession.state.board[replacement.to],
            Piece(kind: .knight, color: .white)
        )
        await replacementSession.resolvePendingCoachingAdvice()
        XCTAssertEqual(
            replacementSession.coachingPresentation?.boardTask,
            CoachingBoardTask.none
        )

        _ = replacementSession.moveSelectedPiece(to: replacement.from)
        XCTAssertNil(replacementSession.selectedSquare)
        XCTAssertNil(replacementSession.state.board[replacement.to])
        await replacementSession.resolvePendingCoachingAdvice()
        XCTAssertEqual(
            replacementSession.coachingPresentation?.instruction,
            "Tap a center pawn or knight."
        )

        let promotionFrom = Square(file: .e, rank: 7)
        let promotionTo = Square(file: .e, rank: 8)
        let promotionSession = GameSession(
            state: promotionState(),
            coachingAdvisor: LocalCoachingAdvisor()
        )
        promotionSession.startCoaching()
        await promotionSession.resolvePendingCoachingAdvice()
        promotionSession.select(promotionFrom)
        XCTAssertEqual(
            promotionSession.moveSelectedPiece(to: promotionTo),
            .needsPromotion(from: promotionFrom, to: promotionTo)
        )
        XCTAssertNil(promotionSession.pendingCoachingRequestID)

        promotionSession.promote(from: promotionFrom, to: promotionTo, to: .queen)

        XCTAssertEqual(promotionSession.selectedSquare, promotionTo)
        XCTAssertEqual(
            promotionSession.state.board[promotionTo],
            Piece(kind: .queen, color: .white)
        )
        XCTAssertNotNil(promotionSession.pendingCoachingRequestID)
    }

    func testCloseHelpStopsCoachingAndPreservesTentativeMove() async {
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(for: move, isLegal: true)
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertNil(session.chooseCoachingAction(.stop))
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertEqual(session.state.board[move.to], Piece(kind: .knight, color: .white))
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertTrue(session.canFinishTurn)
    }

    func testTryAnotherMoveKeepsCoachingAndRederivesFromCommittedPosition() async {
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        await beginOpeningCoaching(in: session)
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.done, .keepLooking, .stop]
        )

        XCTAssertNil(session.chooseCoachingAction(.keepLooking))

        let fresh = await makeOpeningSession()
        XCTAssertTrue(session.isCoachingActive)
        XCTAssertEqual(session.state, .startingPosition())
        XCTAssertNil(session.selectedSquare)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.coachingPresentation, fresh.coachingPresentation)
    }

    func testCoachingDoneReturnsExactMoveFromExistingFinishPath() async {
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(for: move, isLegal: true)
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(session.chooseCoachingAction(.done), move)
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertEqual(session.state.sideToMove, .black)
    }

    func testCurrentFailureEntersFallbackAndCancellationIsSilent() async {
        let failing = GameSession(coachingAdvisor: FailingCoachingAdvisor())
        failing.startCoaching()
        await failing.resolvePendingCoachingAdvice()
        XCTAssertTrue(failing.isCoachingActive)
        XCTAssertEqual(failing.coachingPresentation?.boardTask, .move)

        let cancelling = GameSession(coachingAdvisor: CancellingCoachingAdvisor())
        cancelling.startCoaching()
        let pendingID = cancelling.pendingCoachingRequestID
        await cancelling.resolvePendingCoachingAdvice()
        XCTAssertTrue(cancelling.isCoachingActive)
        assertAwaitingAdvice(cancelling)
        XCTAssertEqual(cancelling.pendingCoachingRequestID, pendingID)
    }

    func testLateSuccessAndFailureForReplacedMoveLeaveExactCurrentRequestUnchanged() async throws {
        for oldRequestFails in [false, true] {
            let advisor = ControllableCoachingAdvisor()
            let session = GameSession(coachingAdvisor: advisor)
            await resolveOpeningAdvice(in: session, using: advisor)

            let firstMove = CoachingTestFixtures.openingKnightMove
            stage(firstMove, in: session)
            let firstID = try XCTUnwrap(session.pendingCoachingRequestID)
            let firstTask = Task { await session.resolvePendingCoachingAdvice() }
            let firstRequest = await waitForOnlyPendingRequest(advisor)
            XCTAssertEqual(firstRequest.tentativeMove, firstMove)
            XCTAssertEqual(firstRequest.context, .tentativeMove(origin: .wake))

            let replacement = Move(
                from: firstMove.from,
                to: Square(file: .a, rank: 3)
            )
            XCTAssertEqual(session.tapEmptySquare(at: replacement.to), .moved)
            let replacementID = try XCTUnwrap(session.pendingCoachingRequestID)
            XCTAssertGreaterThan(replacementID, firstID)
            let replacementTask = Task { await session.resolvePendingCoachingAdvice() }
            let pendingRequests = await waitForPendingRequestCount(advisor, count: 2)
            let replacementRequest = try XCTUnwrap(
                pendingRequests.first(where: { $0.tentativeMove == replacement })
            )

            XCTAssertEqual(firstRequest.positionRevision, replacementRequest.positionRevision)
            XCTAssertEqual(replacementRequest.context, .tentativeMove(origin: .wake))
            XCTAssertEqual(session.selectedSquare, replacement.to)
            XCTAssertEqual(
                session.state.board[replacement.to],
                Piece(kind: .knight, color: .white)
            )
            assertAwaitingAdvice(session)

            if oldRequestFails {
                await advisor.fail(request: firstRequest)
            } else {
                await advisor.resolve(
                    request: firstRequest,
                    with: tentativeAdvice(
                        for: firstMove,
                        isLegal: true,
                        origin: .wake
                    ).replacingRequest(with: firstRequest)
                )
            }
            await firstTask.value

            let requestsAfterLateResponse = await advisor.pendingRequests()
            XCTAssertEqual(session.pendingCoachingRequestID, replacementID)
            XCTAssertEqual(requestsAfterLateResponse, [replacementRequest])
            XCTAssertEqual(session.selectedSquare, replacement.to)
            XCTAssertEqual(
                session.state.board[replacement.to],
                Piece(kind: .knight, color: .white)
            )
            assertAwaitingAdvice(session)

            await advisor.resolve(
                request: replacementRequest,
                with: tentativeAdvice(
                    for: replacement,
                    isLegal: true,
                    origin: .wake
                ).replacingRequest(with: replacementRequest)
            )
            await replacementTask.value
            XCTAssertNil(session.pendingCoachingRequestID)
            XCTAssertEqual(
                session.coachingPresentation?.boardTask,
                CoachingBoardTask.none
            )
        }
    }

    func testRemovingCompletedCoachedMoveImmediatelyRederivesRetainedOpeningAdvice() async {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        await beginOpeningCoaching(in: session)
        stage(CoachingTestFixtures.openingKnightMove, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.done, .keepLooking, .stop]
        )

        session.select(CoachingTestFixtures.alternateKnight)

        let expected = await makeOpeningSession()
        expected.select(CoachingTestFixtures.alternateKnight)
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.alternateKnight)
        XCTAssertNil(session.state.board[CoachingTestFixtures.openingKnightMove.to])
        XCTAssertEqual(
            session.state.board[CoachingTestFixtures.openingKnightMove.from],
            Piece(kind: .knight, color: .white)
        )
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            expected.coachingPresentation?.primaryMessage
        )
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            expected.coachingPresentation?.instruction
        )
        XCTAssertEqual(
            session.coachingPresentation?.actions,
            expected.coachingPresentation?.actions
        )
        XCTAssertEqual(
            session.coachingPresentation?.focus,
            expected.coachingPresentation?.focus
        )
        XCTAssertFalse(
            session.coachingPresentation?.actions.map(\.action).contains(.done) == true
        )
    }

    func testRemovingPreexistingMoveQueuesOneExactStartRequest() async throws {
        let advisor = ControllableCoachingAdvisor()
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(coachingAdvisor: advisor)
        stage(move, in: session)
        session.startCoaching()
        let moveTask = Task { await session.resolvePendingCoachingAdvice() }
        let moveRequest = await waitForOnlyPendingRequest(advisor)
        XCTAssertEqual(moveRequest.tentativeMove, move)
        XCTAssertEqual(moveRequest.context, .tentativeMove(origin: .preexisting))
        await advisor.resolve(
            request: moveRequest,
            with: tentativeAdvice(for: move, isLegal: true)
                .replacingRequest(with: moveRequest)
        )
        await moveTask.value

        let completedPresentation = session.coachingPresentation
        session.select(CoachingTestFixtures.alternateKnight)
        let startID = try XCTUnwrap(session.pendingCoachingRequestID)
        let startTask = Task { await session.resolvePendingCoachingAdvice() }
        let startRequest = await waitForOnlyPendingRequest(advisor)

        XCTAssertEqual(startRequest.committedState, .startingPosition())
        XCTAssertNil(startRequest.tentativeMove)
        XCTAssertEqual(startRequest.context, .start)
        XCTAssertEqual(startRequest.positionRevision, moveRequest.positionRevision)
        XCTAssertEqual(session.selectedSquare, CoachingTestFixtures.alternateKnight)
        XCTAssertNil(session.state.board[move.to])
        assertAwaitingAdvice(session)
        XCTAssertNotEqual(session.coachingPresentation, completedPresentation)

        session.select(CoachingTestFixtures.alternateKnight)
        session.select(CoachingTestFixtures.alternateKnight)
        let pendingAfterRepeatedSnapshots = await advisor.pendingRequests()
        let receivedAfterRepeatedSnapshots = await advisor.requestsReceived()
        XCTAssertEqual(session.pendingCoachingRequestID, startID)
        XCTAssertEqual(pendingAfterRepeatedSnapshots, [startRequest])
        XCTAssertEqual(receivedAfterRepeatedSnapshots, [moveRequest, startRequest])

        await advisor.resolve(
            request: startRequest,
            with: CoachingTestFixtures.startingPositionAdvice
                .replacingRequest(with: startRequest)
        )
        await startTask.value
    }

    func testMoveAdviceWithDifferentOriginIsIgnoredAndExactRequestIsRequeued() async throws {
        let advisor = ControllableCoachingAdvisor()
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(coachingAdvisor: advisor)
        stage(move, in: session)
        session.startCoaching()
        let originalID = try XCTUnwrap(session.pendingCoachingRequestID)
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await waitForOnlyPendingRequest(advisor)
        let wrongRequest = CoachingRequest(
            committedState: request.committedState,
            tentativeMove: move,
            learner: request.learner,
            positionRevision: request.positionRevision,
            context: .tentativeMove(origin: .wake)
        )

        await advisor.resolve(
            request: request,
            with: tentativeAdvice(for: move, isLegal: true, origin: .wake)
                .replacingRequest(with: wrongRequest)
        )
        await task.value

        let retryID = try XCTUnwrap(session.pendingCoachingRequestID)
        XCTAssertGreaterThan(retryID, originalID)
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertEqual(session.state.board[move.to], Piece(kind: .knight, color: .white))
        assertAwaitingAdvice(session)

        let retryTask = Task { await session.resolvePendingCoachingAdvice() }
        let retryRequest = await waitForOnlyPendingRequest(advisor)
        let receivedRequests = await advisor.requestsReceived()
        XCTAssertEqual(retryRequest, request)
        XCTAssertEqual(receivedRequests, [request, request])
        await advisor.resolve(
            request: retryRequest,
            with: tentativeAdvice(for: move, isLegal: true)
                .replacingRequest(with: retryRequest)
        )
        await retryTask.value
    }

    func testAdviceForDifferentCommittedStateIsIgnoredAndExactRequestIsRequeued() async throws {
        let advisor = ControllableCoachingAdvisor()
        let session = GameSession(coachingAdvisor: advisor)
        session.startCoaching()
        let originalID = try XCTUnwrap(session.pendingCoachingRequestID)
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await waitForOnlyPendingRequest(advisor)
        let wrongRequest = CoachingRequest(
            committedState: CoachingTestFixtures.coachingState,
            tentativeMove: nil,
            learner: request.learner,
            positionRevision: request.positionRevision,
            context: .start
        )

        await advisor.resolve(
            request: request,
            with: CoachingTestFixtures.startingPositionAdvice
                .replacingRequest(with: wrongRequest)
        )
        await task.value

        let retryID = try XCTUnwrap(session.pendingCoachingRequestID)
        XCTAssertGreaterThan(retryID, originalID)
        XCTAssertNil(session.selectedSquare)
        XCTAssertEqual(session.state, .startingPosition())
        assertAwaitingAdvice(session)

        let retryTask = Task { await session.resolvePendingCoachingAdvice() }
        let retryRequest = await waitForOnlyPendingRequest(advisor)
        let receivedRequests = await advisor.requestsReceived()
        XCTAssertEqual(retryRequest, request)
        XCTAssertEqual(receivedRequests, [request, request])
        await advisor.resolve(
            request: retryRequest,
            with: CoachingTestFixtures.startingPositionAdvice
                .replacingRequest(with: retryRequest)
        )
        await retryTask.value
    }

    func testIdenticalSnapshotsWhileMoveAdviceIsPendingDoNotDuplicateExactRequest() async throws {
        let advisor = ControllableCoachingAdvisor()
        let session = GameSession(coachingAdvisor: advisor)
        await resolveOpeningAdvice(in: session, using: advisor)
        let move = CoachingTestFixtures.openingKnightMove
        stage(move, in: session)
        let pendingID = try XCTUnwrap(session.pendingCoachingRequestID)
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await waitForOnlyPendingRequest(advisor)

        session.select(move.to)
        session.select(move.to)

        let pendingRequests = await advisor.pendingRequests()
        let exactRequestCount = await advisor.requestsReceived().filter { $0 == request }.count
        XCTAssertEqual(session.pendingCoachingRequestID, pendingID)
        XCTAssertEqual(session.selectedSquare, move.to)
        XCTAssertEqual(session.state.board[move.to], Piece(kind: .knight, color: .white))
        XCTAssertEqual(pendingRequests, [request])
        XCTAssertEqual(exactRequestCount, 1)
        assertAwaitingAdvice(session)

        await advisor.resolve(
            request: request,
            with: tentativeAdvice(for: move, isLegal: true, origin: .wake)
                .replacingRequest(with: request)
        )
        await task.value
    }

    func testExplicitStopDiscardsStaleSuccessAndFailure() async {
        for shouldFail in [false, true] {
            let advisor = ControllableCoachingAdvisor()
            let session = GameSession(coachingAdvisor: advisor)
            session.startCoaching()
            let task = Task { await session.resolvePendingCoachingAdvice() }
            let request = await waitForOnlyPendingRequest(advisor)

            session.stopCoaching()
            if shouldFail {
                await advisor.fail(request: request)
            } else {
                await advisor.resolve(
                    request: request,
                    with: CoachingTestFixtures.startingPositionAdvice
                        .replacingRequest(with: request)
                )
            }
            await task.value

            XCTAssertFalse(session.isCoachingActive)
            XCTAssertNil(session.coachingPresentation)
            XCTAssertNil(session.pendingCoachingRequestID)
        }
    }

    func testLifecycleMutationsDiscardPendingAdvice() async {
        enum Mutation: CaseIterable {
            case localCommit, remoteCommit, newGame, remoteEnd, remoteLockTransition, debugMutation
        }

        for mutation in Mutation.allCases {
            let advisor = ControllableCoachingAdvisor()
            let session = GameSession(coachingAdvisor: advisor)
            let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
            if mutation == .localCommit || mutation == .remoteCommit {
                stage(move, in: session)
            }
            session.startCoaching()
            let task = Task { await session.resolvePendingCoachingAdvice() }
            let request = await waitForOnlyPendingRequest(advisor)

            switch mutation {
            case .localCommit:
                XCTAssertEqual(session.finishTurn(), move)
            case .remoteCommit:
                session.whitePlayer = .remote(playerID: "maya")
                XCTAssertTrue(session.commitRemoteMove(move))
            case .newGame:
                session.newGame()
            case .remoteEnd:
                session.endRemoteGame(message: "Maya ended this game.")
            case .remoteLockTransition:
                session.whitePlayer = .remote(playerID: "maya")
            case .debugMutation:
                session.captureForTesting(at: Square(file: .a, rank: 2))
            }

            await advisor.resolve(
                request: request,
                with: CoachingTestFixtures.startingPositionAdvice
                    .replacingRequest(with: request)
            )
            await task.value
            XCTAssertFalse(session.isCoachingActive, "mutation: \(mutation)")
            XCTAssertNil(session.pendingCoachingRequestID, "mutation: \(mutation)")
        }
    }

    func testChangingNoncurrentRemoteSeatDoesNotStopCoachingButChangingCurrentSeatDoes() {
        let session = GameSession()
        session.startCoaching()

        session.blackPlayer = .remote(playerID: "maya")
        XCTAssertTrue(session.isCoachingActive)

        session.whitePlayer = .remote(playerID: "jason")
        XCTAssertFalse(session.isCoachingActive)
    }

    func testPromotionQueuesAdviceOnlyAfterConcreteChoiceAndDismissalClearsAvailabilityBlock() async {
        let advisor = ControllableCoachingAdvisor()
        let session = GameSession(state: promotionState(), coachingAdvisor: advisor)
        session.startCoaching()
        let startTask = Task { await session.resolvePendingCoachingAdvice() }
        let startRequest = await waitForOnlyPendingRequest(advisor)
        await advisor.resolve(
            request: startRequest,
            with: CoachingTestFixtures.fallbackAdvice.replacingRequest(with: startRequest)
        )
        await startTask.value

        let from = Square(file: .e, rank: 7)
        let to = Square(file: .e, rank: 8)
        session.select(from)
        XCTAssertEqual(session.moveSelectedPiece(to: to), .needsPromotion(from: from, to: to))
        XCTAssertTrue(session.isAwaitingPromotionChoice)
        XCTAssertNil(session.pendingCoachingRequestID)

        session.promote(from: from, to: to, to: .queen)
        XCTAssertFalse(session.isAwaitingPromotionChoice)
        XCTAssertNotNil(session.pendingCoachingRequestID)

        session.cancelPromotionChoice()
        XCTAssertFalse(session.isAwaitingPromotionChoice)
    }

    func testRemoteCommitClearsPendingPromotionChoice() {
        let from = Square(file: .e, rank: 7)
        let to = Square(file: .e, rank: 8)
        let session = GameSession(state: promotionState())
        session.select(from)
        _ = session.moveSelectedPiece(to: to)
        session.whitePlayer = .remote(playerID: "maya")

        XCTAssertTrue(
            session.commitRemoteMove(
                Move(from: from, to: to, special: .promotion(.queen))
            )
        )
        XCTAssertFalse(session.isAwaitingPromotionChoice)
    }

    private func waitForOnlyPendingRequest(
        _ advisor: ControllableCoachingAdvisor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> CoachingRequest {
        let requests = await waitForPendingRequestCount(
            advisor,
            count: 1,
            file: file,
            line: line
        )
        guard let request = requests.first else {
            fatalError("Missing pending request after recorded XCTest failure")
        }
        return request
    }

    private func waitForPendingRequestCount(
        _ advisor: ControllableCoachingAdvisor,
        count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> [CoachingRequest] {
        for _ in 0..<1_000 {
            let requests = await advisor.pendingRequests()
            if requests.count == count { return requests }
            await Task.yield()
        }
        XCTFail("Advisor never received \(count) pending requests", file: file, line: line)
        return await advisor.pendingRequests()
    }

    private func resolveOpeningAdvice(
        in session: GameSession,
        using advisor: ControllableCoachingAdvisor
    ) async {
        session.startCoaching()
        let task = Task { await session.resolvePendingCoachingAdvice() }
        let request = await waitForOnlyPendingRequest(advisor)
        XCTAssertEqual(request.context, .start)
        XCTAssertNil(request.tentativeMove)
        await advisor.resolve(
            request: request,
            with: CoachingTestFixtures.startingPositionAdvice
                .replacingRequest(with: request)
        )
        await task.value
    }

    private func beginOpeningCoaching(in session: GameSession) async {
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
    }

    private func assertAwaitingAdvice(
        _ session: GameSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "I'm checking the board.",
            file: file,
            line: line
        )
        XCTAssertNil(session.coachingPresentation?.instruction, file: file, line: line)
        XCTAssertNil(session.coachingPresentation?.observation, file: file, line: line)
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.stop],
            file: file,
            line: line
        )
        XCTAssertEqual(
            session.coachingPresentation?.boardTask,
            CoachingBoardTask.none,
            file: file,
            line: line
        )
        XCTAssertEqual(session.coachingPresentation?.focus, .empty, file: file, line: line)
    }

    private func makeOpeningSession() async -> GameSession {
        let session = GameSession(coachingAdvisor: LocalCoachingAdvisor())
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
        return session
    }

    private func stage(_ move: Move, in session: GameSession) {
        session.select(move.from)
        XCTAssertEqual(session.moveSelectedPiece(to: move.to), .moved)
    }

    private func tentativeAdvice(
        for move: Move,
        isLegal: Bool,
        positionRevision: Int? = nil,
        origin: CoachingMoveOrigin = .preexisting
    ) -> CoachingAdvice {
        tentativeAdvice(
            for: move,
            isLegal: isLegal,
            issues: [],
            opponentActivities: [],
            positionRevision: positionRevision,
            origin: origin
        )
    }

    private func tentativeAdvice(
        for move: Move,
        isLegal: Bool,
        issues: [CoachingOpponentIssue],
        opponentActivities: [CoachingOpponentActivity],
        positionRevision: Int? = nil,
        origin: CoachingMoveOrigin = .preexisting
    ) -> CoachingAdvice {
        precondition(issues.isEmpty || issues.allSatisfy { issue in
            opponentActivities.contains { activity in
                guard activity.reply == issue.reply else { return false }
                switch issue.kind {
                case .check:
                    return activity.isCheck
                case .mateInOne:
                    return activity.isMate
                case .materialLoss:
                    return activity.canWinPiece
                        && activity.capturedSquare == issue.affectedSquare
                        && activity.capturedPiece != nil
                }
            }
        })
        let assessment = CoachingMoveAssessment(
            move: move,
            isLegal: isLegal,
            resolvesRequiredDanger: true,
            opponentIssues: issues,
            opponentActivities: opponentActivities,
            concepts: [.developsKnightOrBishop],
            isTacticallyAcceptable: isLegal
                && !issues.contains(where: { $0.severity == .reviseMove })
        )
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: origin,
            assessment: assessment
        )
        guard let positionRevision else { return advice }
        return advice.replacingRequest(with: CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: move,
            learner: .white,
            positionRevision: positionRevision,
            context: .tentativeMove(origin: origin)
        ))
    }

    private func promotionState() -> GameState {
        CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                Square(file: .e, rank: 7): Piece(kind: .pawn, color: .white),
            ]
        )
    }

    private func pinnedRookState() -> GameState {
        CoachingTestFixtures.state(
            sideToMove: .white,
            pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 2): Piece(kind: .rook, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
            ]
        )
    }

    private func terminalState(result: GameResult) -> GameState {
        GameState(
            board: Board(pieces: [
                Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
            ]),
            sideToMove: .white,
            result: result
        )
    }
}
