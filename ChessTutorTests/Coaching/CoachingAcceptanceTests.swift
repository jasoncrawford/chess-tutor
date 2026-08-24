import XCTest
@testable import ChessTutor

@MainActor
final class CoachingAcceptanceTests: XCTestCase {
    func testStartingPositionHelpDevelopsKnightAndWaitsForDone() async {
        let session = makeSession()
        let move = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )

        session.startCoaching()
        await session.resolvePendingCoachingAdvice()

        XCTAssertEqual(
            session.coachingPresentation?.boardTask,
            .move
        )
        XCTAssertEqual(
            session.coachingPresentation?.routine,
            [.safeCleared, .takeCleared, .wakeCurrent]
        )
        XCTAssertFalse(session.handleCoachingSquareTap(move.from))
        session.select(move.from)
        XCTAssertEqual(session.state, GameState.startingPosition())
        XCTAssertEqual(session.selectedSquare, move.from)

        XCTAssertEqual(session.moveSelectedPiece(to: move.to), .moved)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertTrue(session.canFinishTurn)
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.done, .keepLooking, .stop]
        )

        let committedMove = session.chooseCoachingAction(.done)
        XCTAssertEqual(committedMove, move)
        XCTAssertEqual(session.state.sideToMove, .black)
        XCTAssertEqual(session.state.moveHistory, [move])
        XCTAssertNil(session.chooseCoachingAction(.done))
        XCTAssertEqual(session.state.moveHistory, [move])
    }

    func testOpeningCenterPawnIsAcceptedAsAnotherPurposefulFirstMove() async {
        let session = makeSession()
        let move = Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .e, rank: 4)
        )

        await beginCoaching(in: session)
        XCTAssertFalse(session.handleCoachingSquareTap(move.from))
        session.select(move.from)
        XCTAssertEqual(session.selectedSquare, move.from)
        XCTAssertEqual(session.moveSelectedPiece(to: move.to), .moved)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your center pawn moved forward and helps control the center."
        )
        XCTAssertTrue(session.state.moveHistory.isEmpty)
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testReportedUnsafeBishopPathUsesExactPresentationWithoutCommitting() async {
        let state = CoachingGoldenPosition.openingBishopCanBeTaken.state
        let move = CoachingGoldenMoves.bishopToA6
        let session = makeSession(state: state)
        stage(move, in: session)

        await beginCoaching(in: session)

        XCTAssertEqual(session.coachingPresentation?.primaryMessage, "What could Black do next?")
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Tap the black piece that could win your bishop."
        )
        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.looksSafe, .hint, .stop]
        )
        XCTAssertTrue(session.handleCoachingSquareTap(sq("b7")))
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Black's pawn could take your bishop."
        )
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Try a different bishop move."
        )
        XCTAssertEqual(session.coachingPresentation?.focus.emphasizedSquares, [sq("a6"), sq("b7")])
        XCTAssertEqual(session.coachingPresentation?.focus.candidateSquares, [])
        XCTAssertEqual(session.coachingPresentation?.focus.paths, [CoachFocusPath(
            source: sq("b7"),
            destination: sq("a6"),
            role: .attacker
        )])
        XCTAssertEqual(session.state.moveHistory, [])
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testBenignCaptureHintRemainsAvailableAfterObservationClears() async {
        let session = makeSession(
            state: CoachingGoldenPosition.protectedPawnUnderBishopAttack.state
        )
        stage(CoachingGoldenMoves.blackPawnToE6, in: session)
        await beginCoaching(in: session)

        XCTAssertTrue(session.handleCoachingSquareTap(sq("c4")))
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "That bishop attacks your pawn, but the pawn is protected."
        )

        _ = session.chooseCoachingAction(.hint)

        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(session.coachingPresentation?.hint, .replyMarkers)
        XCTAssertEqual(session.coachingPresentation?.focus.pulseID, 1)
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.looksSafe, .stop]
        )
        XCTAssertEqual(session.state.moveHistory, [])
    }

    func testCheckTranscriptLetsChildFindCheckerResolveCheckAndCommitOnlyWithDone() async {
        let checkingRook = Square(file: .e, rank: 8)
        let resolvingBishop = Square(file: .b, rank: 5)
        let move = Move(from: resolvingBishop, to: checkingRook)
        let state = makeState(pieces: [
            Square(file: .e, rank: 1): white(.king),
            resolvingBishop: white(.bishop),
            checkingRook: black(.rook),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "What piece is checking your king?"
        )
        XCTAssertTrue(session.handleCoachingSquareTap(checkingRook))
        XCTAssertEqual(session.state, state)
        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)

        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertTrue(session.state.moveHistory.isEmpty)
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertEqual(session.coachingPresentation?.actions.map(\.action), [.done, .keepLooking, .stop])
        XCTAssertEqual(session.chooseCoachingAction(.done), move)
        XCTAssertEqual(session.state.moveHistory, [move])
    }

    func testSafeDangerCanBeResolvedByAddingADefender() async {
        let target = Square(file: .e, rank: 4)
        let knight = Square(file: .b, rank: 1)
        let move = Move(from: knight, to: Square(file: .c, rank: 3))
        let state = makeState(pieces: [
            Square(file: .a, rank: 1): white(.king),
            knight: white(.knight),
            target: white(.pawn),
            Square(file: .d, rank: 5): black(.pawn),
            Square(file: .c, rank: 6): black(.pawn),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertEqual(session.coachingPresentation?.routine, [.safeCurrent, .takePending, .wakePending])
        XCTAssertEqual(session.coachingPresentation?.primaryMessage, "Which of your pieces is in danger?")
        XCTAssertTrue(session.handleCoachingSquareTap(target))
        XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .d, rank: 5)))

        XCTAssertFalse(session.handleCoachingSquareTap(knight))
        session.select(knight)
        XCTAssertEqual(session.selectedSquare, knight)
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your knight now protects the pawn from the attacking pawn."
        )
        XCTAssertTrue(session.state.moveHistory.isEmpty)
    }

    func testDangerTranscriptIdentifiesTargetAttackerAndResolvesDanger() async {
        let target = Square(file: .d, rank: 4)
        let attacker = Square(file: .b, rank: 6)
        let move = Move(from: target, to: attacker)
        let state = makeState(pieces: [
            Square(file: .h, rank: 1): white(.king),
            target: white(.bishop),
            attacker: black(.bishop),
            Square(file: .a, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertTrue(session.handleCoachingSquareTap(target))
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "What black piece is attacking your bishop?"
        )
        XCTAssertEqual(session.coachingPresentation?.instruction, "Tap the black piece.")
        XCTAssertTrue(session.handleCoachingSquareTap(attacker))
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "The bishop attacks your bishop."
        )
        XCTAssertEqual(session.coachingPresentation?.instruction, "Move, protect, or trade your bishop.")

        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your bishop took the attacking bishop and is safe."
        )
        XCTAssertTrue(session.state.moveHistory.isEmpty)
    }

    func testDangerTranscriptNamesDifferentPieceThatCapturesAttacker() async {
        let target = Square(file: .f, rank: 3)
        let attacker = Square(file: .e, rank: 4)
        let capturer = Square(file: .e, rank: 2)
        let move = Move(from: capturer, to: attacker)
        let state = makeState(pieces: [
            Square(file: .a, rank: 1): white(.king),
            target: white(.knight),
            capturer: white(.rook),
            attacker: black(.bishop),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertTrue(session.handleCoachingSquareTap(target))
        XCTAssertTrue(session.handleCoachingSquareTap(attacker))

        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your rook took the attacking bishop, so your knight is safe."
        )
        XCTAssertTrue(session.state.moveHistory.isEmpty)
    }

    func testTakeTranscriptExplainsRecaptureThenAcceptsProfitableCapture() async throws {
        let losingBishop = Square(file: .b, rank: 1)
        let badCapture = Move(from: losingBishop, to: Square(file: .e, rank: 4))
        let profitableCapture = Move(
            from: Square(file: .f, rank: 4),
            to: Square(file: .h, rank: 5)
        )
        let state = makeState(pieces: [
            Square(file: .a, rank: 1): white(.king),
            Square(file: .d, rank: 1): white(.queen),
            losingBishop: white(.bishop),
            profitableCapture.from: white(.knight),
            badCapture.to: black(.pawn),
            Square(file: .f, rank: 5): black(.pawn),
            Square(file: .g, rank: 6): black(.bishop),
            profitableCapture.to: black(.rook),
            Square(file: .a, rank: 8): black(.king),
        ])
        let advisor = LocalCoachingAdvisor()
        let advice = try await advisor.advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: 0,
            context: .start
        ))
        let estimate = try XCTUnwrap(
            advice.evaluation.learnerCaptureEstimates.first { $0.move == profitableCapture }
        )
        XCTAssertEqual(estimate.netGainForMover, 2)
        XCTAssertEqual(
            estimate.immediateRecapture,
            Move(from: Square(file: .g, rank: 6), to: profitableCapture.to)
        )

        let badSession = makeSession(state: state)
        await beginCoaching(in: badSession)
        XCTAssertEqual(
            badSession.coachingPresentation?.primaryMessage,
            "Can one of your pieces safely take a black piece?"
        )
        stage(badCapture, in: badSession)
        await badSession.resolvePendingCoachingAdvice()
        XCTAssertEqual(
            badSession.coachingPresentation?.observation,
            "Black's pawn could take your bishop, so you would lose it for a pawn."
        )
        XCTAssertEqual(
            badSession.coachingPresentation?.primaryMessage,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertEqual(badSession.coachingPresentation?.boardTask, .move)

        let winningSession = makeSession(state: state)
        await beginCoaching(in: winningSession)
        stage(profitableCapture, in: winningSession)
        await winningSession.resolvePendingCoachingAdvice()
        _ = winningSession.chooseCoachingAction(.looksSafe)
        XCTAssertEqual(
            winningSession.coachingPresentation?.primaryMessage,
            "Your knight wins a rook even if Black's bishop takes it back."
        )
        XCTAssertTrue(winningSession.state.moveHistory.isEmpty)
    }

    func testSafeCanTeachAddingADefenderAgainstSlidingAttack() async {
        let knight = Square(file: .b, rank: 1)
        let target = Square(file: .e, rank: 4)
        let move = Move(from: knight, to: Square(file: .c, rank: 3))
        let state = makeState(pieces: [
            Square(file: .a, rank: 1): white(.king),
            knight: white(.knight),
            target: white(.pawn),
            Square(file: .b, rank: 7): black(.bishop),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertTrue(session.handleCoachingSquareTap(target))
        XCTAssertTrue(session.handleCoachingSquareTap(Square(file: .b, rank: 7)))
        XCTAssertFalse(session.handleCoachingSquareTap(knight))
        session.select(knight)
        XCTAssertEqual(session.selectedSquare, knight)
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)

        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your knight now protects the pawn from the attacking bishop."
        )
    }

    func testUnsupportedPositionFallsBackWithoutInventingAPurpose() async {
        let move = Move(
            from: Square(file: .a, rank: 2),
            to: Square(file: .a, rank: 3)
        )
        let state = makeState(pieces: [
            Square(file: .d, rank: 4): white(.king),
            move.from: white(.pawn),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertEqual(session.coachingPresentation?.routine, [])
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "What move would you like to try?"
        )

        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "That move seems safe."
        )
    }

    func testChildCanFindSeriousOpponentReplyAndTutorRequestsRevision() async {
        let move = Move(
            from: Square(file: .c, rank: 3),
            to: Square(file: .d, rank: 4)
        )
        let attacker = Square(file: .c, rank: 5)
        let state = makeState(pieces: [
            Square(file: .h, rank: 1): white(.king),
            move.from: white(.bishop),
            Square(file: .e, rank: 3): white(.pawn),
            attacker: black(.pawn),
            Square(file: .a, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        stage(move, in: session)
        await beginCoaching(in: session)
        XCTAssertEqual(
            session.coachingPresentation?.boardTask,
            .identify(allowsMoveRevision: true)
        )
        XCTAssertTrue(session.handleCoachingSquareTap(move.to))
        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "That piece cannot check or win a piece here."
        )
        XCTAssertEqual(
            session.coachingPresentation?.boardTask,
            .identify(allowsMoveRevision: true)
        )
        XCTAssertTrue(session.handleCoachingSquareTap(attacker))

        XCTAssertNil(session.coachingPresentation?.observation)
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Black's pawn could take your bishop."
        )
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Try a different bishop move."
        )
        XCTAssertEqual(
            session.coachingPresentation?.actions.map(\.action),
            [.hint, .stop]
        )
        XCTAssertEqual(session.coachingPresentation?.boardTask, .move)
        XCTAssertEqual(session.state.board[move.to], white(.bishop))
        XCTAssertTrue(session.state.moveHistory.isEmpty)
        XCTAssertEqual(session.state.sideToMove, .white)
    }

    func testChildCanIdentifyVisibleRookThatCouldGiveHarmlessCheckAndMoveIsAccepted() async {
        let move = Move(
            from: Square(file: .b, rank: 1),
            to: Square(file: .c, rank: 3)
        )
        let checkingRook = Square(file: .a, rank: 8)
        let state = makeState(pieces: [
            Square(file: .e, rank: 1): white(.king),
            move.from: white(.knight),
            checkingRook: black(.rook),
            Square(file: .h, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        stage(move, in: session)
        await beginCoaching(in: session)
        XCTAssertTrue(session.handleCoachingSquareTap(checkingRook))

        XCTAssertEqual(
            session.coachingPresentation?.observation,
            "That rook could check along your back row, but your knight move still works."
        )
        XCTAssertEqual(
            session.coachingPresentation?.primaryMessage,
            "Your knight moved closer to the center."
        )
        XCTAssertEqual(session.coachingPresentation?.actions.map(\.action), [.done, .keepLooking, .stop])
        XCTAssertTrue(session.state.moveHistory.isEmpty)
    }

    func testIncorrectTapsAndFiniteSemanticHintsProgressWithoutMovingAPiece() async {
        let target = Square(file: .d, rank: 4)
        let attacker = Square(file: .b, rank: 6)
        let whiteKing = Square(file: .h, rank: 1)
        let wrongAttacker = Square(file: .h, rank: 7)
        let state = makeState(pieces: [
            whiteKing: white(.king),
            target: white(.bishop),
            attacker: black(.bishop),
            wrongAttacker: black(.pawn),
            Square(file: .a, rank: 8): black(.king),
        ])
        let session = makeSession(state: state)

        await beginCoaching(in: session)
        XCTAssertTrue(session.handleCoachingSquareTap(target))
        let unchangedBoard = session.state.board

        XCTAssertTrue(session.handleCoachingSquareTap(wrongAttacker))
        XCTAssertTrue(session.handleCoachingSquareTap(wrongAttacker))
        XCTAssertEqual(session.state.board, unchangedBoard)
        XCTAssertEqual(
            session.coachingPresentation?.actions.first { $0.action == .hint }?.prominence,
            .primary
        )

        _ = session.chooseCoachingAction(.hint)
        XCTAssertEqual(
            session.coachingPresentation?.hint,
            .attackerRelationship
        )
        XCTAssertEqual(session.coachingPresentation?.focus.paths, [CoachFocusPath(
            source: attacker,
            destination: target,
            role: .attacker
        )])
        _ = session.chooseCoachingAction(.hint)
        XCTAssertEqual(session.coachingPresentation?.hint, .candidatePieces)
        XCTAssertEqual(session.coachingPresentation?.focus.candidateSquares, [attacker])
        XCTAssertFalse(session.coachingPresentation?.actions.map(\.action).contains(.hint) == true)
        XCTAssertEqual(
            session.coachingPresentation?.instruction,
            "Try one of the highlighted pieces."
        )
        XCTAssertEqual(session.state.board, unchangedBoard)
        XCTAssertTrue(session.state.moveHistory.isEmpty)
    }

    func testStopPreservesOrdinaryTentativeMoveAndNeverCommits() async {
        let session = makeSession()
        let move = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )

        await beginCoaching(in: session)
        XCTAssertFalse(session.handleCoachingSquareTap(move.from))
        session.select(move.from)
        XCTAssertEqual(session.selectedSquare, move.from)
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()

        XCTAssertNil(session.chooseCoachingAction(.stop))
        XCTAssertFalse(session.isCoachingActive)
        XCTAssertEqual(session.state.board[move.to], white(.knight))
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertTrue(session.state.moveHistory.isEmpty)
        XCTAssertTrue(session.canFinishTurn)
    }

    func testKeepLookingDiscardsAcceptedTentativeMoveAndRestartsCoaching() async {
        let session = makeSession()
        let freshSession = makeSession()
        let move = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )

        await completeStartingMove(move, in: session)
        let completedPresentation = session.coachingPresentation
        XCTAssertNil(session.chooseCoachingAction(.keepLooking))
        await beginCoaching(in: freshSession)

        XCTAssertTrue(session.isCoachingActive)
        XCTAssertEqual(session.state, .startingPosition())
        XCTAssertEqual(session.state.board[move.from], white(.knight))
        XCTAssertNil(session.state.board[move.to])
        XCTAssertEqual(session.state.sideToMove, .white)
        XCTAssertTrue(session.state.moveHistory.isEmpty)
        XCTAssertNil(session.selectedSquare)
        XCTAssertFalse(session.canFinishTurn)
        XCTAssertNotEqual(session.coachingPresentation, completedPresentation)
        XCTAssertEqual(session.coachingPresentation, freshSession.coachingPresentation)
    }

    func testSameTranscriptProducesIdenticalPresentationsAndHistoryVisibleOutputs() async {
        let first = await runDeterministicStartingTranscript()
        let second = await runDeterministicStartingTranscript()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.committedMove, Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        ))
        XCTAssertEqual(first.moveHistory, [first.committedMove])
        XCTAssertEqual(first.sideToMove, .black)
        XCTAssertEqual(first.publicEffects, [
            .squareTap(
                consumed: false,
                selectedSquare: Square(file: .g, rank: 1),
                moveHistory: []
            ),
            .moveStaged(
                result: .moved,
                selectedSquare: Square(file: .f, rank: 3),
                moveHistory: []
            ),
            .action(
                action: .looksSafe,
                returnedMove: nil,
                selectedSquare: Square(file: .f, rank: 3),
                moveHistory: []
            ),
            .action(
                action: .done,
                returnedMove: first.committedMove,
                selectedSquare: nil,
                moveHistory: [first.committedMove]
            ),
        ])
    }

    func testOpeningSelectionProjectionIsIndependentOfSelectionHistory() async {
        let blockedRook = Square(file: .a, rank: 1)
        let direct = await openingPresentation(afterSelecting: [blockedRook])
        let switched = await openingPresentation(afterSelecting: [
            CoachingTestFixtures.openingKnight,
            CoachingTestFixtures.alternateKnight,
            blockedRook,
        ])

        XCTAssertEqual(switched, direct)
        XCTAssertEqual(
            switched.observation,
            "Your pawn blocks that rook."
        )
        XCTAssertEqual(
            switched.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            switched.instruction,
            "Tap a center pawn or knight."
        )
        XCTAssertEqual(switched.boardTask, .move)
    }

    func testOpeningTapAndDragProjectionAreEquivalent() async {
        let tapped = await openingSession()
        let dragged = await openingSession()
        let source = CoachingTestFixtures.openingKnight

        XCTAssertFalse(tapped.handleCoachingSquareTap(source))
        tapped.select(source)
        XCTAssertFalse(dragged.handleCoachingSquareDragStart(source))
        XCTAssertEqual(dragged.prepareDrag(from: source), source)

        XCTAssertEqual(dragged.selectedSquare, tapped.selectedSquare)
        XCTAssertEqual(dragged.state.board, tapped.state.board)
        XCTAssertEqual(dragged.coachingPresentation, tapped.coachingPresentation)
        XCTAssertEqual(dragged.pendingCoachingRequestID, tapped.pendingCoachingRequestID)
    }

    func testSafeTargetProjectionIsIndependentOfIdentificationHistory() async {
        let direct = await dangerSession()
        let switched = await dangerSession()

        XCTAssertTrue(direct.handleCoachingSquareTap(CoachingTestFixtures.whiteRook))
        XCTAssertTrue(switched.handleCoachingSquareTap(CoachingTestFixtures.whiteQueen))
        XCTAssertTrue(switched.handleCoachingSquareTap(CoachingTestFixtures.whiteRook))

        XCTAssertEqual(switched.coachingPresentation, direct.coachingPresentation)
        XCTAssertEqual(
            switched.coachingPresentation?.focus.emphasizedSquares,
            []
        )
        XCTAssertEqual(switched.coachingPresentation?.focus.paths, [])
        XCTAssertEqual(switched.coachingPresentation?.boardTask, .identify(allowsMoveRevision: false))
    }

    func testSafeResolutionProjectionRetainsTargetAndAttackerAcrossSourceHistory() async {
        let direct = await safeResolutionSession()
        let switched = await safeResolutionSession()
        let finalSource = CoachingTestFixtures.alternateKnight

        direct.select(finalSource)
        switched.select(CoachingTestFixtures.openingKnight)
        switched.select(finalSource)

        XCTAssertEqual(switched.selectedSquare, direct.selectedSquare)
        XCTAssertEqual(switched.state.board, direct.state.board)
        XCTAssertEqual(switched.coachingPresentation, direct.coachingPresentation)
        XCTAssertEqual(
            switched.coachingPresentation?.focus.emphasizedSquares,
            [CoachingTestFixtures.whiteQueen, CoachingTestFixtures.blackBishop]
        )
        XCTAssertEqual(switched.coachingPresentation?.focus.paths, [CoachFocusPath(
            source: CoachingTestFixtures.blackBishop,
            destination: CoachingTestFixtures.whiteQueen,
            role: .attacker
        )])
        XCTAssertEqual(switched.coachingPresentation?.boardTask, .move)
        XCTAssertNil(switched.pendingCoachingRequestID)
    }

    private func makeSession(state: GameState = .startingPosition()) -> GameSession {
        GameSession(state: state, coachingAdvisor: LocalCoachingAdvisor())
    }

    private func beginCoaching(in session: GameSession) async {
        session.startCoaching()
        await session.resolvePendingCoachingAdvice()
    }

    private func openingSession() async -> GameSession {
        let session = GameSession(
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.startingPositionAdvice
            )
        )
        await beginCoaching(in: session)
        return session
    }

    private func openingPresentation(
        afterSelecting squares: [Square]
    ) async -> CoachingPresentation {
        let session = await openingSession()
        for square in squares {
            session.select(square)
        }
        return session.coachingPresentation!
    }

    private func dangerSession() async -> GameSession {
        let session = GameSession(
            state: CoachingTestFixtures.coachingState,
            coachingAdvisor: ImmediateCoachingAdvisor(
                advice: CoachingTestFixtures.multipleDangerAdvice
            )
        )
        await beginCoaching(in: session)
        return session
    }

    private func safeResolutionSession() async -> GameSession {
        let session = await dangerSession()
        XCTAssertTrue(session.handleCoachingSquareTap(CoachingTestFixtures.whiteQueen))
        XCTAssertTrue(session.handleCoachingSquareTap(CoachingTestFixtures.blackBishop))
        return session
    }

    private func stage(
        _ move: Move,
        in session: GameSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        session.select(move.from)
        XCTAssertEqual(
            session.moveSelectedPiece(to: move.to),
            .moved,
            file: file,
            line: line
        )
    }

    private func completeStartingMove(_ move: Move, in session: GameSession) async {
        await beginCoaching(in: session)
        XCTAssertFalse(session.handleCoachingSquareTap(move.from))
        session.select(move.from)
        XCTAssertEqual(session.selectedSquare, move.from)
        stage(move, in: session)
        await session.resolvePendingCoachingAdvice()
        _ = session.chooseCoachingAction(.looksSafe)
        XCTAssertEqual(session.coachingPresentation?.actions.map(\.action), [.done, .keepLooking, .stop])
    }

    private func runDeterministicStartingTranscript() async -> TranscriptResult {
        let session = makeSession()
        let move = Move(
            from: Square(file: .g, rank: 1),
            to: Square(file: .f, rank: 3)
        )
        var presentations: [CoachingPresentation] = []
        var publicEffects: [TranscriptPublicEffect] = []

        await beginCoaching(in: session)
        presentations.append(session.coachingPresentation!)
        let tapWasConsumed = session.handleCoachingSquareTap(move.from)
        session.select(move.from)
        publicEffects.append(.squareTap(
            consumed: tapWasConsumed,
            selectedSquare: session.selectedSquare,
            moveHistory: session.state.moveHistory
        ))
        presentations.append(session.coachingPresentation!)
        let moveResult = session.moveSelectedPiece(to: move.to)
        publicEffects.append(.moveStaged(
            result: moveResult,
            selectedSquare: session.selectedSquare,
            moveHistory: session.state.moveHistory
        ))
        await session.resolvePendingCoachingAdvice()
        presentations.append(session.coachingPresentation!)
        let looksSafeReturn = session.chooseCoachingAction(.looksSafe)
        publicEffects.append(.action(
            action: .looksSafe,
            returnedMove: looksSafeReturn,
            selectedSquare: session.selectedSquare,
            moveHistory: session.state.moveHistory
        ))
        presentations.append(session.coachingPresentation!)
        let committed = session.chooseCoachingAction(.done)!
        publicEffects.append(.action(
            action: .done,
            returnedMove: committed,
            selectedSquare: session.selectedSquare,
            moveHistory: session.state.moveHistory
        ))

        return TranscriptResult(
            presentations: presentations,
            publicEffects: publicEffects,
            committedMove: committed,
            moveHistory: session.state.moveHistory,
            sideToMove: session.state.sideToMove,
            finalBoard: session.state.board
        )
    }

    private func makeState(pieces: [Square: Piece]) -> GameState {
        GameState(board: Board(pieces: pieces), sideToMove: .white)
    }

    private func white(_ kind: Piece.Kind) -> Piece {
        Piece(kind: kind, color: .white)
    }

    private func black(_ kind: Piece.Kind) -> Piece {
        Piece(kind: kind, color: .black)
    }
}

private struct TranscriptResult: Equatable {
    let presentations: [CoachingPresentation]
    let publicEffects: [TranscriptPublicEffect]
    let committedMove: Move
    let moveHistory: [Move]
    let sideToMove: PieceColor
    let finalBoard: Board
}

private enum TranscriptPublicEffect: Equatable {
    case squareTap(consumed: Bool, selectedSquare: Square?, moveHistory: [Move])
    case moveStaged(result: MoveAttemptResult, selectedSquare: Square?, moveHistory: [Move])
    case action(
        action: CoachingAction,
        returnedMove: Move?,
        selectedSquare: Square?,
        moveHistory: [Move]
    )
}
