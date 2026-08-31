import XCTest
@testable import ChessTutor

final class HostedCoachingSessionTests: XCTestCase {
    func testEpisodeDerivesCurrentLearnerEventsAndBuildsEveryRequestFromCurrentState() throws {
        let state = GameState.startingPosition()
        let b1 = Square(file: .b, rank: 1)
        let b8 = Square(file: .b, rank: 8)
        let c3 = Square(file: .c, rank: 3)
        let a3 = Square(file: .a, rank: 3)
        var session = HostedCoachingSession(learner: .white)

        session.openHelp(selectedSquare: nil, tentativeMove: nil)
        XCTAssertEqual(.helpOpened, session.latestEvent.kind)

        XCTAssertFalse(
            session.recordInteraction(
                committedState: state,
                selectedSquare: b1,
                tentativeMove: nil
            )
        )
        XCTAssertEqual(.helpOpened, session.latestEvent.kind)
        XCTAssertEqual(1, session.events.count)

        let firstMove = Move(from: b1, to: c3)
        XCTAssertTrue(
            session.recordInteraction(
                committedState: state,
                selectedSquare: nil,
                tentativeMove: firstMove
            )
        )
        XCTAssertEqual(.moveStaged, session.latestEvent.kind)
        XCTAssertEqual(["move:b1-c3"], session.latestEvent.referencedIDs)

        let replacement = Move(from: b1, to: a3)
        XCTAssertTrue(
            session.recordInteraction(
                committedState: state,
                selectedSquare: nil,
                tentativeMove: replacement
            )
        )
        XCTAssertEqual(.moveReplaced, session.latestEvent.kind)

        XCTAssertTrue(
            session.recordInteraction(
                committedState: state,
                selectedSquare: nil,
                tentativeMove: nil
            )
        )
        XCTAssertEqual(.moveRemoved, session.latestEvent.kind)
        XCTAssertEqual(["move:b1-a3"], session.latestEvent.referencedIDs)

        XCTAssertFalse(
            session.recordInteraction(
                committedState: state,
                selectedSquare: b8,
                tentativeMove: nil
            )
        )
        XCTAssertEqual(.moveRemoved, session.latestEvent.kind)

        session.recordHintAction()
        XCTAssertEqual(.actionChosen, session.latestEvent.kind)
        XCTAssertEqual(["action:hint"], session.latestEvent.referencedIDs)

        let request = session.request(
            committedState: state,
            selectedSquare: b8,
            tentativeMove: nil,
            positionRevision: 7,
            requestID: "hosted-7"
        )
        XCTAssertEqual("hosted-7", request.requestID)
        XCTAssertEqual(7, request.positionRevision)
        XCTAssertEqual(session.events, request.interaction.episodeEvents)
        XCTAssertEqual(session.latestEvent, request.interaction.latestEvent)
        XCTAssertEqual(.thinking, session.phase)
        XCTAssertNil(session.continuationID)

        session.receive(
            ModelCoachingChessNativeTurn(
                message: "What could you notice?",
                actions: [],
                focus: []
            ),
            continuationID: "resp_first-123"
        )
        XCTAssertEqual("resp_first-123", session.continuationID)

        session.openHelp(selectedSquare: nil, tentativeMove: nil)
        XCTAssertNil(session.continuationID)
    }

    func testDuplicateInteractionDoesNotAddAnEventAndPhaseTransitionsAreExplicit() {
        let state = GameState.startingPosition()
        var session = HostedCoachingSession(learner: .white)
        session.openHelp(selectedSquare: nil, tentativeMove: nil)

        XCTAssertFalse(
            session.recordInteraction(
                committedState: state,
                selectedSquare: nil,
                tentativeMove: nil
            )
        )
        XCTAssertEqual(1, session.events.count)

        let turn = ModelCoachingChessNativeTurn(
            message: "Look at your knight.",
            actions: ["hint"],
            focus: [.square("b1")]
        )
        session.receive(turn, continuationID: "resp_ready-123")
        XCTAssertEqual(.ready(turn), session.phase)
        session.fail()
        XCTAssertEqual(.failed, session.phase)
        session.recordRetry()
        XCTAssertEqual(.helpReopened, session.latestEvent.kind)
        XCTAssertEqual(.thinking, session.phase)
    }
}
