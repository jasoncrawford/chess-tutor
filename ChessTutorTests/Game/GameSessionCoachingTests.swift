import XCTest
@testable import ChessTutor

@MainActor
final class GameSessionCoachingTests: XCTestCase {
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

    func testStartingFromLegalTentativeMoveGoesDirectlyToReplyCheck() async {
        let move = CoachingTestFixtures.openingKnightMove
        let advice = tentativeAdvice(for: move, isLegal: true)
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(advice: advice)
        )
        stage(move, in: session)

        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.isCoachingActive)
        XCTAssertEqual(session.coachingPresentation?.boardTask, .identify(allowsMoveRevision: true))
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
        XCTAssertEqual(session.coachingPresentation?.headline, "This move leaves your king in check. Try another move.")
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
        let advice = tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
        let originalHeadline = session.coachingPresentation?.headline
        let originalRoutine = session.coachingPresentation?.routine

        XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .c, rank: 3)))
        XCTAssertEqual(session.coachingPresentation?.routine, originalRoutine)

        _ = session.chooseCoachingAction(.noAnswer)
        XCTAssertNotEqual(session.coachingPresentation?.headline, originalHeadline)
        XCTAssertNotEqual(session.coachingPresentation?.routine, originalRoutine)
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareTap(move.to))
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
            )
        )
        stage(move, in: session)
        let tentativeBoard = session.state.board
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertTrue(session.handleCoachingSquareDragStart(move.to))
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
        XCTAssertNil(session.coachingPresentation)
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
        XCTAssertNil(session.coachingPresentation)
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
                advice: tentativeAdvice(for: move, isLegal: true, issues: [issue])
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
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")

        let blockedRook = Square(file: .a, rank: 1)
        session.select(blockedRook)

        XCTAssertEqual(session.selectedSquare, blockedRook)
        XCTAssertEqual(
            session.coachingPresentation?.headline,
            "That rook can’t come out yet because other pieces are in the way."
        )
        XCTAssertEqual(session.coachingPresentation?.instruction, "Tap the piece you want to move.")
        XCTAssertNil(session.pendingCoachingRequestID)
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

    func testOpeningSourceFeedbackTracksPawnRookEmptyAndEnemySwitches() async {
        let session = await makeOpeningSession()

        session.select(CoachingTestFixtures.openingKnight)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")

        session.select(Square(file: .e, rank: 2))
        XCTAssertEqual(
            session.coachingPresentation?.headline,
            "That pawn can move, but it doesn’t bring a new piece into the game."
        )

        session.select(Square(file: .a, rank: 1))
        XCTAssertEqual(
            session.coachingPresentation?.headline,
            "That rook can’t come out yet because other pieces are in the way."
        )

        session.select(Square(file: .e, rank: 4))
        XCTAssertNil(session.selectedSquare)
        XCTAssertEqual(
            session.coachingPresentation?.headline,
            "A good first step is to move a center pawn or bring out a knight. Which would you like to try?"
        )

        session.select(Square(file: .a, rank: 7))
        XCTAssertEqual(session.selectedSquare, Square(file: .a, rank: 7))
        XCTAssertEqual(session.coachingPresentation?.headline, "Tap one of your pieces.")
        XCTAssertEqual(session.coachingPresentation?.instruction, "Tap the piece you want to move.")
        XCTAssertNil(session.pendingCoachingRequestID)
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
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")

        XCTAssertNil(session.tapEmptySquare(at: Square(file: .e, rank: 4)))
        XCTAssertNil(session.selectedSquare)
        XCTAssertNil(session.pendingCoachingRequestID)

        XCTAssertEqual(
            session.prepareDrag(from: CoachingTestFixtures.alternateKnight),
            CoachingTestFixtures.alternateKnight
        )
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")

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
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")
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
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move it on the board.")
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
            .identify(allowsMoveRevision: true)
        )

        _ = replacementSession.moveSelectedPiece(to: replacement.from)
        XCTAssertNil(replacementSession.selectedSquare)
        XCTAssertNil(replacementSession.state.board[replacement.to])
        await replacementSession.resolvePendingCoachingAdvice()
        XCTAssertEqual(
            replacementSession.coachingPresentation?.instruction,
            "Tap the piece you want to move."
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

    func testStopAndKeepLookingPreserveTentativeMove() async {
        for action in [CoachingAction.stop, .keepLooking] {
            let move = CoachingTestFixtures.openingKnightMove
            let session = GameSession(
                coachingAdvisor: ImmediateCoachingAdvisor(
                    advice: tentativeAdvice(for: move, isLegal: true)
                )
            )
            stage(move, in: session)
            session.startCoaching()
            await session.resolvePendingCoachingAdvice()
            if action == .keepLooking {
                _ = session.chooseCoachingAction(.looksSafe)
            }

            XCTAssertNil(session.chooseCoachingAction(action))
            XCTAssertFalse(session.isCoachingActive)
            XCTAssertEqual(session.state.board[move.to], Piece(kind: .knight, color: .white))
            XCTAssertTrue(session.canFinishTurn)
        }
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
        XCTAssertNil(cancelling.coachingPresentation)
        XCTAssertEqual(cancelling.pendingCoachingRequestID, pendingID)
    }

    func testSupersedingTentativeRequestDiscardsOlderSuccess() async {
        let advisor = ControllableCoachingAdvisor()
        let firstMove = Move(from: Square(file: .b, rank: 1), to: Square(file: .c, rank: 3))
        let replacement = Move(from: Square(file: .g, rank: 1), to: Square(file: .f, rank: 3))
        let session = GameSession(coachingAdvisor: advisor)
        stage(firstMove, in: session)
        let oldRevision = session.analysisRevision
        session.startCoaching()
        let oldTask = Task { await session.resolvePendingCoachingAdvice() }
        await waitForPending(advisor, revision: oldRevision)

        session.select(replacement.from)
        _ = session.moveSelectedPiece(to: replacement.to)
        let newRevision = session.analysisRevision
        let newID = session.pendingCoachingRequestID
        XCTAssertNotEqual(oldRevision, newRevision)
        let newTask = Task { await session.resolvePendingCoachingAdvice() }
        await waitForPending(advisor, revision: newRevision)

        await advisor.resolve(
            revision: oldRevision,
            with: tentativeAdvice(for: firstMove, isLegal: true)
        )
        await oldTask.value
        XCTAssertEqual(session.pendingCoachingRequestID, newID)
        XCTAssertNil(session.coachingPresentation)

        await advisor.resolve(
            revision: newRevision,
            with: tentativeAdvice(
                for: replacement,
                isLegal: true,
                positionRevision: newRevision
            )
        )
        await newTask.value
        XCTAssertNil(session.pendingCoachingRequestID)
        XCTAssertEqual(session.coachingPresentation?.boardTask, .identify(allowsMoveRevision: true))
    }

    func testExplicitStopDiscardsStaleSuccessAndFailure() async {
        for shouldFail in [false, true] {
            let advisor = ControllableCoachingAdvisor()
            let session = GameSession(coachingAdvisor: advisor)
            let revision = session.analysisRevision
            session.startCoaching()
            let task = Task { await session.resolvePendingCoachingAdvice() }
            await waitForPending(advisor, revision: revision)

            session.stopCoaching()
            if shouldFail {
                await advisor.fail(revision: revision)
            } else {
                await advisor.resolve(revision: revision, with: CoachingTestFixtures.startingPositionAdvice)
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
            let revision = session.analysisRevision
            session.startCoaching()
            let task = Task { await session.resolvePendingCoachingAdvice() }
            await waitForPending(advisor, revision: revision)

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

            await advisor.resolve(revision: revision, with: CoachingTestFixtures.startingPositionAdvice)
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
        let startRevision = session.analysisRevision
        let startTask = Task { await session.resolvePendingCoachingAdvice() }
        await waitForPending(advisor, revision: startRevision)
        await advisor.resolve(revision: startRevision, with: CoachingTestFixtures.fallbackAdvice)
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

    func testRemovingPreexistingTentativeMoveRequestsCurrentPositionAdviceWithoutChangingBoardInputRules() async {
        let move = CoachingTestFixtures.openingKnightMove
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: tentativeAdvice(for: move, isLegal: true)
            )
        )
        stage(move, in: session)
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        session.select(Square(file: .g, rank: 1))

        XCTAssertNil(session.state.board[move.to])
        XCTAssertEqual(session.state.board[move.from], Piece(kind: .knight, color: .white))
        XCTAssertEqual(session.selectedSquare, Square(file: .g, rank: 1))
        XCTAssertNil(session.coachingPresentation)
        XCTAssertNotNil(session.pendingCoachingRequestID)
    }

    private func waitForPending(
        _ advisor: ControllableCoachingAdvisor,
        revision: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if await advisor.hasPending(revision: revision) { return }
            await Task.yield()
        }
        XCTFail("Advisor never received revision \(revision)", file: file, line: line)
    }

    private func makeOpeningSession() async -> GameSession {
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.startingPositionAdvice
            )
        )
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
        issues: [CoachingOpponentIssue] = [],
        positionRevision: Int? = nil
    ) -> CoachingAdvice {
        let assessment = CoachingMoveAssessment(
            move: move,
            isLegal: isLegal,
            resolvesRequiredDanger: true,
            opponentIssues: issues,
            concepts: [.developsKnightOrBishop],
            isAcceptable: isLegal && !issues.contains(where: { $0.severity == .reviseMove })
        )
        let advice = CoachingTestFixtures.adviceForTentativeMove(
            move,
            origin: .preexisting,
            assessment: assessment
        )
        guard let positionRevision else { return advice }
        return advice.replacingRequest(with: CoachingRequest(
            committedState: .startingPosition(),
            tentativeMove: move,
            learner: .white,
            positionRevision: positionRevision,
            context: .tentativeMove(origin: .preexisting)
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
