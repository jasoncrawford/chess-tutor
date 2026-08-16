import SwiftUI
import XCTest
@testable import ChessTutor

final class CoachFocusOverlayTests: XCTestCase {
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

    func testFocusStyleMakesCandidatesQuieterAndCandidatePathsDashed() {
        let style = CoachFocusStyle.current

        XCTAssertLessThan(style.candidateRingScale, style.emphasizedRingScale)
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
            headline: "What do you notice?",
            instruction: instruction,
            hint: nil,
            routine: [],
            actions: [],
            boardTask: boardTask,
            focus: .empty
        )
    }
}
