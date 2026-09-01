import XCTest
@testable import ChessTutor

final class HostedCoachingPresentationProjectorTests: XCTestCase {
    func testDangerQuestionDerivesMatchingBoardTaskAndNegativeAnswer() {
        let turn = ModelCoachingChessNativeTurn(
            message: "Can you find the pawn in danger?",
            actions: ["hint"],
            focus: [.square("f2")],
            expects: .findEndangeredPiece
        )

        let presentation = HostedCoachingPresentationProjector().presentation(
            for: .ready(turn),
            pulseID: 3
        )

        XCTAssertEqual(.identify(allowsMoveRevision: false), presentation.boardTask)
        XCTAssertEqual([.noAnswer, .hint, .stop], presentation.actions.map(\.action))
        XCTAssertEqual(
            ["No piece needs help", "Hint", "Close help"],
            presentation.actions.map(\.title)
        )
    }

    func testCaptureQuestionDerivesDistinctNegativeAnswer() {
        let turn = ModelCoachingChessNativeTurn(
            message: "Can you find a safe capture?",
            actions: [],
            focus: [],
            expects: .findSafeCapture
        )

        let presentation = HostedCoachingPresentationProjector().presentation(
            for: .ready(turn),
            pulseID: 4
        )

        XCTAssertEqual(.identify(allowsMoveRevision: false), presentation.boardTask)
        XCTAssertEqual([.noAnswer, .stop], presentation.actions.map(\.action))
        XCTAssertEqual(["No safe capture", "Close help"], presentation.actions.map(\.title))
    }

    func testStagedMoveResponseTypesDeriveMutuallyCoherentControls() {
        let projector = HostedCoachingPresentationProjector()
        let judgment = projector.presentation(
            for: .ready(
                ModelCoachingChessNativeTurn(
                    message: "What could your opponent do next? Does this look safe?",
                    actions: ["hint"],
                    focus: [],
                    expects: .judgeMoveSafety
                )
            ),
            pulseID: 4
        )
        let decision = projector.presentation(
            for: .ready(
                ModelCoachingChessNativeTurn(
                    message: "That move looks safe. Would you like to keep it?",
                    actions: ["hint"],
                    focus: [],
                    expects: .chooseWhetherToPlay
                )
            ),
            pulseID: 5
        )

        XCTAssertEqual(.none, judgment.boardTask)
        XCTAssertEqual(
            [.looksSafe, .keepLooking, .hint, .stop],
            judgment.actions.map(\.action)
        )
        XCTAssertEqual(
            ["Looks safe", "Try another move", "Hint", "Close help"],
            judgment.actions.map(\.title)
        )
        XCTAssertEqual(.none, decision.boardTask)
        XCTAssertEqual([.done, .keepLooking, .hint, .stop], decision.actions.map(\.action))
        XCTAssertEqual(
            ["Play this move", "Try another move", "Hint", "Close help"],
            decision.actions.map(\.title)
        )
    }

    func testThinkingAndFailureRemainVisibleWithOnlyUsefulActions() {
        let projector = HostedCoachingPresentationProjector()

        let thinking = projector.presentation(for: .thinking, pulseID: 1)
        XCTAssertEqual("Thinking…", thinking.primaryMessage)
        XCTAssertEqual([.stop], thinking.actions.map(\.action))
        XCTAssertEqual(.none, thinking.boardTask)

        let failed = projector.presentation(for: .failed, pulseID: 2)
        XCTAssertEqual("I couldn't get help right now.", failed.primaryMessage)
        XCTAssertEqual([.hint, .stop], failed.actions.map(\.action))
        XCTAssertEqual(["Try again", "Close help"], failed.actions.map(\.title))
    }

    func testReadyTurnMapsSemanticActionsAndBoardFocusDirectly() {
        let turn = ModelCoachingChessNativeTurn(
            message: "What could this knight help near the center?",
            actions: ["hint", "playMove", "tryAnotherMove"],
            focus: [
                .square("b1"),
                .move(from: "b1", to: "c3"),
            ]
        )

        let presentation = HostedCoachingPresentationProjector().presentation(
            for: .ready(turn),
            pulseID: 9
        )

        XCTAssertEqual(turn.message, presentation.primaryMessage)
        XCTAssertNil(presentation.instruction)
        XCTAssertNil(presentation.observation)
        XCTAssertEqual([], presentation.routine)
        XCTAssertEqual([.hint, .done, .keepLooking, .stop], presentation.actions.map(\.action))
        XCTAssertEqual(["Hint", "Play this move", "Try another move", "Close help"], presentation.actions.map(\.title))
        XCTAssertEqual(.none, presentation.boardTask)
        XCTAssertEqual(
            Set([Square(file: .b, rank: 1)]),
            presentation.focus.emphasizedSquares
        )
        XCTAssertEqual(
            Set([Square(file: .c, rank: 3)]),
            presentation.focus.candidateSquares
        )
        XCTAssertEqual(
            Set([
                CoachFocusPath(
                    source: Square(file: .b, rank: 1),
                    destination: Square(file: .c, rank: 3),
                    role: .candidate
                ),
            ]),
            presentation.focus.paths
        )
        XCTAssertEqual(9, presentation.focus.pulseID)
    }
}
