import XCTest
@testable import ChessTutor

final class HostedVisualInteractionTests: XCTestCase {
    @MainActor
    func testSpokenMatchingDraftArrowNamesTheVisiblePiece() {
        let session = GameSession()
        let g1 = Square(file: .g, rank: 1), h3 = Square(file: .h, rank: 3)
        session.select(g1)
        _ = session.moveSelectedPiece(to: h3)
        var hosted = HostedCoachingSession(learner: .white)
        hosted.openHelp(selectedSquare: nil, tentativeMove: nil)
        hosted.receive(.init(message: "Your knight moved.", actions: [], focus: [], expects: .chooseWhetherToPlay,
            visualContent: .init(runs: [.text("Your knight moved.")], visuals: [.move(from: "g1", to: "h3")])), continuationID: "resp_test")
        let presentation = HostedCoachingPresentationProjector().presentation(for: hosted,
            board: GameState.startingPosition().board, tentativeMove: Move(from: g1, to: h3))
        XCTAssertEqual(CoachingVisualAccessibility.arrow(presentation.replayPath, board: session.state.board,
                                                        isStagedMove: presentation.arrowIsDraft),
                       "White knight on h3 moved from g1.")
    }

    func testBoardAnswerPromptTracksExpectedActionAndClearsOnEscapeAndFailure() {
        for (expects, prompt): (ModelCoachingChessNativeExpectedResponse, String) in [
            (.findEndangeredPiece, "Tap the piece that needs help"),
            (.findSafeCapture, "Tap a piece you can capture"),
            (.selectPiece, "Tap a piece to answer")
        ] {
            var session = HostedCoachingSession(learner: .white)
            session.openHelp(selectedSquare: nil, tentativeMove: nil)
            session.receive(.init(message: "Which piece?", actions: ["hint"], focus: [], expects: expects), continuationID: "resp_one")
            let state = GameState.startingPosition()
            let projector = HostedCoachingPresentationProjector()
            XCTAssertEqual(projector.presentation(for: session, board: state.board, tentativeMove: nil).boardAnswerPrompt, prompt)
            XCTAssertTrue(session.recordPieceSelectionAnswer(at: Square(file: .b, rank: 1), in: state))
            let waiting = projector.presentation(for: session, board: state.board, tentativeMove: nil)
            XCTAssertEqual(waiting.boardAnswerPrompt, prompt)
            XCTAssertTrue(waiting.isAwaitingAnswer)
            session.playInstead()
            let escaped = projector.presentation(for: session, board: state.board, tentativeMove: nil)
            XCTAssertNil(escaped.boardAnswerPrompt)
            XCTAssertFalse(escaped.isAwaitingAnswer)
        }
        for phase: HostedCoachingPhase in [.failed, .timedOut] {
            XCTAssertNil(HostedCoachingPresentationProjector().presentation(for: phase, pulseID: 0).boardAnswerPrompt)
        }
    }

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
