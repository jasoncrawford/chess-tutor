import XCTest
@testable import ChessTutor

final class CoachingGoldenTranscriptTests: XCTestCase {
    func testCorpusContainsEveryApprovedAnchor() {
        XCTAssertEqual(CoachingGoldenPosition.allCases.count, 15)
        XCTAssertEqual(Set(CoachingGoldenPosition.allCases.map(\.rawValue)).count, 15)
        XCTAssertEqual(CoachingGoldenCase.allCases.count, 47)
        XCTAssertEqual(Set(CoachingGoldenCase.allCases.map(\.rawValue)).count, 47)
    }

    func testSafeDangerAndProtectionBranchesUseBoardFacts() async throws {
        let t3Entry = try await goldenTurn(.t3Entry)
        let t4LowerPriorityPawn = try await goldenTurn(.t4LowerPriorityPawn)
        let t5PawnResolved = try await goldenTurn(.t5PawnResolved)
        let t5ProtectedTap = try await goldenTurn(.t5ProtectedTap)
        let t8AddsDefender = try await goldenTurn(.t8AddsDefender)

        XCTAssertEqual(
            t3Entry.ask,
            "One of your pieces is in danger. Which one?"
        )
        XCTAssertEqual(
            t4LowerPriorityPawn.response,
            "You found a threatened pawn. A knight is worth about three pawns, so losing the knight would cost more."
        )
        XCTAssertEqual(
            t4LowerPriorityPawn.ask,
            "Which piece should you help first?"
        )
        XCTAssertEqual(
            t5PawnResolved.ask,
            "Your pawn moved out of the bishop’s path. It is safe now."
        )
        XCTAssertEqual(
            t5ProtectedTap.response,
            "The pawn is attacked, but your other pawn protects it. If the knight takes it, your pawn can take the knight back. No piece needs help right now."
        )
        XCTAssertEqual(
            t8AddsDefender.ask,
            "Your other pawn now protects the threatened pawn. If the knight takes it, your pawn can take the knight back."
        )
    }

    func testSafeAndUnsafeCaptureBranchesUseConcreteExchangeFacts() async throws {
        let t6WrongSource = try await goldenTurn(.t6WrongSource)
        let t6Hint = try await goldenTurn(.t6Hint)
        let t6Capture = try await goldenTurn(.t6Capture)
        let t7UnsafeCapture = try await goldenTurn(.t7UnsafeCapture)
        let t7NoSafeCapture = try await goldenTurn(.t7NoSafeCapture)

        XCTAssertEqual(
            t6WrongSource.ask,
            "Can one of your pieces safely take a black piece?"
        )
        XCTAssertEqual(t6WrongSource.response, "That piece has no safe capture here.")
        XCTAssertEqual(t6Hint.response, "Your bishop has a safe capture.")
        XCTAssertEqual(t6Hint.instruction, "Tap the highlighted white piece.")
        XCTAssertEqual(
            t6Capture.ask,
            "Your bishop took a rook, and Black cannot take the bishop back."
        )
        XCTAssertEqual(
            t7UnsafeCapture.response,
            "Black’s king could take your bishop. You would lose a bishop to take one pawn."
        )
        XCTAssertEqual(
            t7NoSafeCapture.response,
            "Right—there is no safe capture here."
        )
        XCTAssertEqual(
            t7NoSafeCapture.ask,
            "I do not have a confident plan for this position yet."
        )
    }

    func testConstructiveWakeBranchesUseNamedEvidenceAndBoundedGrades() async throws {
        let t1Entry = try await goldenTurn(.t1Entry)
        let t1BlockedRook = try await goldenTurn(.t1BlockedRook)
        let t1FlankPawn = try await goldenTurn(.t1FlankPawn)
        let t1Hint = try await goldenTurn(.t1Hint)
        let t1KnightSelected = try await goldenTurn(.t1KnightSelected)
        let t1PreferredKnight = try await goldenTurn(.t1PreferredKnight)
        let t1EdgeKnight = try await goldenTurn(.t1EdgeKnight)
        let t1CenterPawn = try await goldenTurn(.t1CenterPawn)
        let t2Entry = try await goldenTurn(.t2Entry)
        let t2OneSquareKingMove = try await goldenTurn(.t2OneSquareKingMove)
        let t2KnightSwitch = try await goldenTurn(.t2KnightSwitch)
        let t2Castle = try await goldenTurn(.t2Castle)
        let t9Entry = try await goldenTurn(.t9Entry)
        let t9Hint = try await goldenTurn(.t9Hint)
        let t9Completed = try await goldenTurn(.t9Completed)
        let t10Entry = try await goldenTurn(.t10Entry)
        let t10Completed = try await goldenTurn(.t10Completed)

        XCTAssertEqual(
            t1Entry.ask,
            "A center pawn or knight is a simple way to start. Which would you like to move?"
        )
        XCTAssertEqual(
            t1BlockedRook.response,
            "Your pawn is blocking that rook. Choose a center pawn or knight."
        )
        XCTAssertEqual(
            t1FlankPawn.response,
            "That pawn can move, but it is not a center pawn. Choose a pawn in front of your king or queen, or choose a knight."
        )
        XCTAssertEqual(t1Hint.ask, "Here are the four pieces you can try.")
        XCTAssertEqual(t1Hint.instruction, "Tap a highlighted piece.")
        XCTAssertEqual(
            t1KnightSelected.ask,
            "You chose a knight. Moving it off its starting square is called developing it."
        )
        XCTAssertEqual(
            t1PreferredKnight.ask,
            "You developed your knight toward the center. From there it can reach more squares."
        )
        XCTAssertEqual(
            t1EdgeKnight.ask,
            "You developed your knight. A square closer to the center would usually give it more choices."
        )
        XCTAssertEqual(
            t1CenterPawn.ask,
            "Your center pawn moved forward and now helps control the center."
        )
        XCTAssertEqual(t2Entry.ask, "Your king is ready to castle.")
        XCTAssertEqual(
            t2Entry.instruction,
            "Move your king two squares toward the rook."
        )
        XCTAssertEqual(
            t2OneSquareKingMove.response,
            "That is a king move, but it is not castling. Castling moves the king two squares toward the rook."
        )
        XCTAssertEqual(
            t2KnightSwitch.ask,
            "That knight can also be developed."
        )
        XCTAssertEqual(
            t2KnightSwitch.instruction,
            "Move the knight off its starting square."
        )
        XCTAssertEqual(
            t2Castle.ask,
            "You castled. Your king moved toward safety, and your rook moved toward the center."
        )
        XCTAssertEqual(
            t9Entry.ask,
            "Your knight can move to a square where it attacks Black’s rook. Can you find the square?"
        )
        XCTAssertEqual(
            t9Hint.ask,
            "Both highlighted squares let the knight attack the rook."
        )
        XCTAssertEqual(
            t9Hint.instruction,
            "Move the knight to one of the highlighted squares."
        )
        XCTAssertEqual(
            t9Completed.ask,
            "Your knight now attacks the rook. Black may need to move or protect it."
        )
        XCTAssertEqual(t9Completed.emphasizedSquares, [sq("b3"), sq("d4")])
        XCTAssertEqual(t9Completed.candidateSquares, [])
        XCTAssertEqual(t9Completed.paths, [
            CoachFocusPath(
                source: sq("b3"),
                destination: sq("d4"),
                role: .attacker
            ),
        ])
        XCTAssertEqual(
            t10Entry.ask,
            "Your knight has very few choices in the corner. Can you move it closer to the center?"
        )
        XCTAssertEqual(
            t10Completed.ask,
            "From there your knight can reach six squares instead of two. That is why knights are often stronger near the center."
        )
    }

    func testCanonicalT2ClearsSafeAndTakeBeforeWake() async throws {
        var session = try await preparedSession(for: .readyToCastle)

        XCTAssertEqual(
            session.presentation?.headline,
            "One of your pieces is in danger. Which one?"
        )

        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(
            session.presentation?.headline,
            "Can one of your pieces safely take a black piece?"
        )

        session.handle(.actionChosen(.noAnswer))

        XCTAssertEqual(session.presentation?.headline, "Your king is ready to castle.")
        XCTAssertEqual(
            session.presentation?.instruction,
            "Move your king two squares toward the rook."
        )
    }

    private func goldenTurn(_ branch: CoachingGoldenCase) async throws -> CoachingGoldenTurn {
        var session: CoachingSession
        switch branch {
        case .t1Entry:
            session = try await preparedSession(for: .starting)

        case .t1BlockedRook:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("a1"))))

        case .t1FlankPawn:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("a2"))))

        case .t1Hint:
            session = try await preparedSession(for: .starting)
            session.handle(.actionChosen(.hint))

        case .t1KnightSelected:
            session = try await preparedSession(for: .starting)
            session.handle(.interactionChanged(snapshot(selected: sq("b1"))))

        case .t1PreferredKnight:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("g1"), to: sq("f3")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t1EdgeKnight:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("g1"), to: sq("h3")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t1CenterPawn:
            session = try await preparedSession(for: .starting)
            try await complete(
                Move(from: sq("e2"), to: sq("e4")),
                origin: .wake,
                position: .starting,
                in: &session
            )

        case .t2Entry:
            session = try await preparedT2WakeSession()

        case .t2OneSquareKingMove:
            session = try await preparedT2WakeSession()
            try await stage(
                Move(from: sq("e1"), to: sq("f1")),
                origin: .wake,
                position: .readyToCastle,
                in: &session
            )

        case .t2KnightSwitch:
            session = try await preparedT2WakeSession()
            session.handle(.interactionChanged(snapshot(selected: sq("b1"))))

        case .t2Castle:
            session = try await preparedT2WakeSession()
            try await stage(
                CoachingGoldenMoves.castle,
                origin: .wake,
                position: .readyToCastle,
                in: &session
            )
            XCTAssertEqual(
                session.presentation?.headline,
                "Could Black check your king or win one of your pieces?"
            )
            session.handle(.actionChosen(.looksSafe))

        case .t3Entry:
            session = try await preparedSession(for: .endangeredKnight)

        case .t4LowerPriorityPawn:
            session = try await preparedSession(for: .twoDangerPriorities)
            session.handle(.identificationTapped(sq("a3")))

        case .t5PawnResolved:
            session = try await preparedSession(for: .endangeredPawn)
            session.handle(.identificationTapped(sq("e3")))
            session.handle(.identificationTapped(sq("b6")))
            try await complete(
                CoachingGoldenMoves.pawnEscapes,
                origin: .safe,
                position: .endangeredPawn,
                in: &session
            )

        case .t5ProtectedTap:
            session = try await preparedSession(for: .protectedPawn)
            session.handle(.identificationTapped(sq("g4")))

        case .t6WrongSource:
            session = try await preparedSession(for: .winningCapture)
            session.handle(.interactionChanged(snapshot(selected: sq("g1"))))

        case .t6Hint:
            session = try await preparedSession(for: .winningCapture)
            session.handle(.actionChosen(.hint))

        case .t6Capture:
            session = try await preparedSession(for: .winningCapture)
            try await complete(
                CoachingGoldenMoves.bishopWinsRook,
                origin: .take,
                position: .winningCapture,
                in: &session
            )

        case .t7UnsafeCapture:
            session = try await preparedSession(for: .losingCapture)
            try await stage(
                CoachingGoldenMoves.bishopTakesPawn,
                origin: .take,
                position: .losingCapture,
                in: &session
            )

        case .t7NoSafeCapture:
            session = try await preparedSession(for: .losingCapture)
            session.handle(.actionChosen(.noAnswer))

        case .t8AddsDefender:
            session = try await preparedSession(for: .protectPawn)
            session.handle(.identificationTapped(sq("g4")))
            session.handle(.identificationTapped(sq("f6")))
            try await complete(
                CoachingGoldenMoves.addsPawnDefender,
                origin: .safe,
                position: .protectPawn,
                in: &session
            )

        case .t9Entry:
            session = try await preparedSession(for: .createRookThreat)

        case .t9Hint:
            session = try await preparedSession(for: .createRookThreat)
            session.handle(.actionChosen(.hint))

        case .t9Completed:
            session = try await preparedSession(for: .createRookThreat)
            try await stage(
                CoachingGoldenMoves.knightThreatB3,
                origin: .wake,
                position: .createRookThreat,
                in: &session
            )
            session.handle(.identificationTapped(sq("d4")))

        case .t10Entry:
            session = try await preparedSession(for: .cornerKnight)

        case .t10Completed:
            session = try await preparedSession(for: .cornerKnight)
            try await complete(
                CoachingGoldenMoves.knightThreatB3,
                origin: .wake,
                position: .cornerKnight,
                in: &session
            )

        default:
            preconditionFailure("No golden turn implementation for \(branch.rawValue)")
        }

        let presentation = try XCTUnwrap(
            session.presentation,
            "Missing presentation for \(branch.rawValue)"
        )
        return CoachingGoldenTurn(
            response: presentation.response,
            ask: presentation.headline,
            instruction: presentation.instruction,
            actions: presentation.actions.map(\.action),
            actionTitles: presentation.actions.map(\.title),
            boardTask: presentation.boardTask,
            routine: presentation.routine,
            emphasizedSquares: presentation.focus.emphasizedSquares,
            candidateSquares: presentation.focus.candidateSquares,
            paths: presentation.focus.paths
        )
    }

    private func preparedSession(
        for position: CoachingGoldenPosition
    ) async throws -> CoachingSession {
        try await preparedSession(for: position.state)
    }

    private func preparedSession(for state: GameState) async throws -> CoachingSession {
        let interaction = snapshot()
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .start
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .start
        ))
        session.receive(advice, interaction: interaction)
        return session
    }

    private func preparedT2WakeSession() async throws -> CoachingSession {
        var session = try await preparedSession(for: .readyToCastle)
        session.handle(.actionChosen(.noAnswer))
        session.handle(.actionChosen(.noAnswer))
        return session
    }

    private func complete(
        _ move: Move,
        origin: CoachingMoveOrigin,
        position: CoachingGoldenPosition,
        in session: inout CoachingSession
    ) async throws {
        try await complete(
            move,
            origin: origin,
            state: position.state,
            in: &session
        )
    }

    private func complete(
        _ move: Move,
        origin: CoachingMoveOrigin,
        state: GameState,
        in session: inout CoachingSession
    ) async throws {
        try await stage(move, origin: origin, state: state, in: &session)
        session.handle(.actionChosen(.looksSafe))
    }

    private func stage(
        _ move: Move,
        origin: CoachingMoveOrigin,
        position: CoachingGoldenPosition,
        in session: inout CoachingSession
    ) async throws {
        try await stage(
            move,
            origin: origin,
            state: position.state,
            in: &session
        )
    }

    private func stage(
        _ move: Move,
        origin: CoachingMoveOrigin,
        state: GameState,
        in session: inout CoachingSession
    ) async throws {
        let interaction = snapshot(selected: move.to, tentativeMove: move)
        session.handle(.interactionChanged(interaction))
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: state,
            tentativeMove: move,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: origin)
        ))
        session.receive(advice, interaction: interaction)
    }

    private func snapshot(
        selected: Square? = nil,
        tentativeMove: Move? = nil
    ) -> CoachingInteractionSnapshot {
        CoachingInteractionSnapshot(
            selectedSquare: selected,
            tentativeMove: tentativeMove,
            positionRevision: 1
        )
    }
}
