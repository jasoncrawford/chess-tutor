import XCTest
@testable import ChessTutor

final class TurnStatusPresentationTests: XCTestCase {
    func testRemoteLocalTurnShowsYourMoveDetail() {
        let session = GameSession()
        session.blackPlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: "Maya")

        XCTAssertEqual(presentation.headline, "White's turn")
        XCTAssertEqual(presentation.detail, "It's your move.")
    }

    func testRemoteWaitingTurnShowsOpponentMoveDetail() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: "Maya")

        XCTAssertEqual(presentation.headline, "White's turn")
        XCTAssertEqual(presentation.detail, "Waiting for Maya to move.")
    }

    func testGuidanceOverridesRemoteTurnDetail() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")
        session.endRemoteGame(message: "Maya ended this game.")

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: "Maya")

        XCTAssertEqual(presentation.detail, "Maya ended this game.")
    }

    func testLocalGameHasNoDefaultDetail() {
        let session = GameSession()

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: nil)

        XCTAssertEqual(presentation.headline, "White's turn")
        XCTAssertNil(presentation.detail)
    }
}
