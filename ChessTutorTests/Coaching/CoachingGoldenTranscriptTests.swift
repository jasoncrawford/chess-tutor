import XCTest
@testable import ChessTutor

final class CoachingGoldenTranscriptTests: XCTestCase {
    func testCorpusContainsEveryApprovedAnchor() {
        XCTAssertEqual(CoachingGoldenPosition.allCases.count, 15)
        XCTAssertEqual(Set(CoachingGoldenPosition.allCases.map(\.rawValue)).count, 15)
        XCTAssertEqual(CoachingGoldenCase.allCases.count, 46)
        XCTAssertEqual(Set(CoachingGoldenCase.allCases.map(\.rawValue)).count, 46)
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

    private func goldenTurn(_ branch: SafeGoldenBranch) async throws -> CoachingGoldenTurn {
        var session: CoachingSession
        switch branch {
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
        }

        let presentation = try XCTUnwrap(session.presentation)
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
        let interaction = snapshot()
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .start
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: position.state,
            tentativeMove: nil,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .start
        ))
        session.receive(advice, interaction: interaction)
        return session
    }

    private func complete(
        _ move: Move,
        origin: CoachingMoveOrigin,
        position: CoachingGoldenPosition,
        in session: inout CoachingSession
    ) async throws {
        let interaction = snapshot(selected: move.to, tentativeMove: move)
        session.handle(.interactionChanged(interaction))
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: position.state,
            tentativeMove: move,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: origin)
        ))
        session.receive(advice, interaction: interaction)
        session.handle(.actionChosen(.looksSafe))
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

private enum SafeGoldenBranch {
    case t3Entry
    case t4LowerPriorityPawn
    case t5PawnResolved
    case t5ProtectedTap
    case t8AddsDefender
}
