import SwiftUI
import XCTest
@testable import ChessTutor

final class CoachFocusOverlayTests: XCTestCase {
    func testOpponentReplyHintUsesFullHypotheticalReplyPaths() async throws {
        let queenLoss = try await hintedOpponentReply(
            position: .exposedQueen,
            move: CoachingGoldenMoves.exposesQueen
        )
        let harmlessCheck = try await hintedOpponentReply(
            position: .harmlessCheck,
            move: CoachingGoldenMoves.developsKnight
        )

        XCTAssertEqual(queenLoss.focus.candidateSquares, [sq("d8")])
        XCTAssertEqual(queenLoss.focus.paths, [CoachFocusPath(
            source: sq("d8"),
            destination: sq("d4"),
            role: .attacker
        )])
        XCTAssertEqual(harmlessCheck.focus.candidateSquares, [sq("a8")])
        XCTAssertEqual(harmlessCheck.focus.paths, [CoachFocusPath(
            source: sq("a8"),
            destination: sq("a1"),
            role: .attacker
        )])
    }

    func testCandidatePathUsesReadableBoardGeometry() {
        let source = Square(file: .b, rank: 1)
        let destination = Square(file: .c, rank: 3)
        let geometry = BoardGuidanceGeometry(
            side: 640,
            origin: .zero,
            viewingAngle: .clockwiseQuarterTurn
        )

        let layout = CoachFocusPathLayout.make(
            from: source,
            to: destination,
            geometry: geometry
        )

        XCTAssertEqual(layout.start, geometry.center(of: source))
        XCTAssertEqual(layout.end, geometry.center(of: destination))
    }

    func testCandidatePathUsesBoardGeometryForEveryTabletopOrientation() {
        let source = Square(file: .a, rank: 8)
        let destination = Square(file: .h, rank: 1)

        for viewingAngle in [
            BoardViewingAngle.normal,
            .clockwiseQuarterTurn,
            .halfTurn,
            .counterclockwiseQuarterTurn,
        ] {
            let geometry = BoardGuidanceGeometry(
                side: 640,
                origin: CGPoint(x: 12, y: 20),
                viewingAngle: viewingAngle
            )

            let layout = CoachFocusPathLayout.make(
                from: source,
                to: destination,
                geometry: geometry
            )

            XCTAssertEqual(layout.start, geometry.center(of: source))
            XCTAssertEqual(layout.end, geometry.center(of: destination))
        }
    }

    func testReducedMotionDisablesCoachPulse() {
        XCTAssertEqual(CoachFocusMotionPolicy(reducesMotion: true).pulseScale, 1)
        XCTAssertGreaterThan(CoachFocusMotionPolicy(reducesMotion: false).pulseScale, 1)
    }

    func testCandidateHintUsesLargeContrastingKeylinedRing() {
        let style = CoachFocusStyle.current

        XCTAssertEqual(style.candidateRingScale, 0.80, accuracy: 0.001)
        XCTAssertEqual(style.candidateRingLineWidthInCells, 0.036, accuracy: 0.001)
        XCTAssertEqual(style.candidateRingKeylineWidthInCells, 0.072, accuracy: 0.001)
        XCTAssertGreaterThan(
            style.candidateRingKeylineWidthInCells,
            style.candidateRingLineWidthInCells
        )
        XCTAssertTrue(style.pathDash(for: .attacker).isEmpty)
        XCTAssertFalse(style.pathDash(for: .candidate).isEmpty)
        XCTAssertLessThan(style.pathLineWidthInCells, BoardGuidanceStyle.current.pathLineWidthInCells)
    }

    func testIdentificationInstructionBecomesBoardAccessibilityContextOnlyWhileIdentifying() {
        let identify = coachingPresentation(
            instruction: "Tap the piece that could capture it.",
            boardTask: .identify(allowsMoveRevision: false)
        )
        let move = coachingPresentation(
            instruction: "Make a move on the board.",
            boardTask: .move
        )

        XCTAssertEqual(
            CoachBoardAccessibilityContext.instruction(for: identify),
            "Tap the piece that could capture it."
        )
        XCTAssertNil(CoachBoardAccessibilityContext.instruction(for: move))
        XCTAssertNil(CoachBoardAccessibilityContext.instruction(for: nil))
    }

    private func coachingPresentation(
        instruction: String,
        boardTask: CoachingBoardTask
    ) -> CoachingPresentation {
        CoachingPresentation(
            primaryMessage: "What do you notice?",
            instruction: instruction,
            observation: nil,
            hint: nil,
            routine: [],
            actions: [],
            boardTask: boardTask,
            focus: .empty
        )
    }

    private func hintedOpponentReply(
        position: CoachingGoldenPosition,
        move: Move
    ) async throws -> CoachingPresentation {
        let interaction = CoachingInteractionSnapshot(
            selectedSquare: move.to,
            tentativeMove: move,
            positionRevision: 1
        )
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .tentativeMove(origin: .fallback)
        )
        let advice = try await LocalCoachingAdvisor().advice(for: CoachingRequest(
            committedState: position.state,
            tentativeMove: move,
            learner: .white,
            positionRevision: interaction.positionRevision,
            context: .tentativeMove(origin: .fallback)
        ))
        session.receive(advice, interaction: interaction)
        session.handle(.actionChosen(.hint))
        return try XCTUnwrap(session.presentation)
    }
}
