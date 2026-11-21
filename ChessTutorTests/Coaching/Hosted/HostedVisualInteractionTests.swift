import XCTest
@testable import ChessTutor

final class HostedVisualInteractionTests: XCTestCase {
    func testReferenceAndReplayAreLocalAndDoNotChangeConversation() {
        var session = HostedCoachingSession(learner: .white)
        session.openHelp(selectedSquare: nil, tentativeMove: nil)
        session.receive(.init(message: "Your knight", actions: [], focus: [], expects: .stageMove,
            visualContent: .init(runs: [.piece(text: "Your knight", square: "g1")],
                                 visuals: [.move(from: "g1", to: "f3")])), continuationID: "resp_one")
        let events = session.events
        session.replayReference(at: 0)
        XCTAssertEqual("g1", session.referenceSquare)
        let pulse = session.pulseID
        let oldReplay = session.referenceReplayID
        session.replayReference(at: 0)
        XCTAssertGreaterThan(session.pulseID, pulse)
        session.expireReference(replayID: oldReplay)
        XCTAssertEqual("g1", session.referenceSquare, "Old animation expiry cannot clear a newer tap")
        session.expireReference(replayID: session.referenceReplayID)
        XCTAssertNil(session.referenceSquare)
        session.replayVisual()
        XCTAssertNil(session.referenceSquare)
        XCTAssertEqual(events, session.events)
        XCTAssertEqual("resp_one", session.continuationID)
    }

    func testRepeatedAnswersRetainQuestionUntilMoveOrLocalEscape() {
        var session = HostedCoachingSession(learner: .white)
        session.openHelp(selectedSquare: nil, tentativeMove: nil)
        session.receive(.init(message: "Tap a knight.", actions: ["hint"], focus: [], expects: .findEndangeredPiece), continuationID: "resp_one")
        let state = GameState.startingPosition()
        let b1 = Square(file: .b, rank: 1), g1 = Square(file: .g, rank: 1)
        XCTAssertTrue(session.recordPieceSelectionAnswer(at: b1, in: state))
        XCTAssertTrue(session.recordPieceSelectionAnswer(at: g1, in: state))
        XCTAssertTrue(session.isAnswering)
        XCTAssertEqual(g1, session.answerSquare)
        XCTAssertFalse(session.recordPieceSelectionAnswer(at: Square(file: .a, rank: 3), in: state))
        let events = session.events
        session.playInstead()
        XCTAssertFalse(session.isAnswering)
        XCTAssertNil(session.answerSquare)
        XCTAssertEqual(events, session.events)
        XCTAssertFalse(session.recordPieceSelectionAnswer(at: b1, in: state))
        XCTAssertTrue(session.recordInteraction(committedState: state, selectedSquare: g1,
            tentativeMove: Move(from: g1, to: Square(file: .f, rank: 3))))
        XCTAssertFalse(session.isPlayingInstead)
        XCTAssertNil(session.referenceSquare)
    }

    func testDraftArrowBeginsAtTheVisiblePieceAndIsARelocation() {
        var session = HostedCoachingSession(learner: .white)
        session.openHelp(selectedSquare: nil, tentativeMove: nil)
        session.receive(.init(message: "Try here.", actions: [], focus: [], expects: .chooseWhetherToPlay,
            visualContent: .init(runs: [.text("Try here.")], visuals: [.move(from: "g1", to: "f3")])), continuationID: "resp_one")
        let draft = Move(from: Square(file: .g, rank: 1), to: Square(file: .h, rank: 3))
        let p = HostedCoachingPresentationProjector().presentation(for: session, board: GameState.startingPosition().board, tentativeMove: draft)
        XCTAssertEqual(draft.to, p.focus.paths.first?.source)
        XCTAssertEqual(.relocation, p.focus.paths.first?.geometryKind)
    }
}
