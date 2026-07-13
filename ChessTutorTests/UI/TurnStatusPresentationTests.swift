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

    func testRemoteWaitingTurnShowsOpponentMovingPresence() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(
            session: session,
            remoteOpponentName: "Maya",
            remotePresence: RemotePresenceUpdate(
                gameID: RemoteGameID(rawValue: "game"),
                playerID: RemotePlayerID(rawValue: "maya"),
                state: .activeMoving,
                updatedAt: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 20)
            ),
            now: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(presentation.detail, "Maya is moving...")
    }

    func testRemoteWaitingTurnShowsOpponentAwayWhenPresenceExpired() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(
            session: session,
            remoteOpponentName: "Maya",
            remotePresence: RemotePresenceUpdate(
                gameID: RemoteGameID(rawValue: "game"),
                playerID: RemotePlayerID(rawValue: "maya"),
                state: .foregroundIdle,
                updatedAt: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 20)
            ),
            now: Date(timeIntervalSince1970: 25)
        )

        XCTAssertEqual(presentation.detail, "Maya is away from the board.")
    }

    func testRemoteLocalTurnIgnoresOpponentPresence() {
        let session = GameSession()
        session.blackPlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(
            session: session,
            remoteOpponentName: "Maya",
            remotePresence: RemotePresenceUpdate(
                gameID: RemoteGameID(rawValue: "game"),
                playerID: RemotePlayerID(rawValue: "maya"),
                state: .activeMoving,
                updatedAt: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 20)
            ),
            now: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(presentation.detail, "It's your move.")
    }

    func testGuidanceOverridesRemoteTurnDetail() {
        let session = GameSession()
        session.whitePlayer = .remote(playerID: "maya")
        session.endRemoteGame(message: "Maya ended this game.")

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: "Maya")

        XCTAssertEqual(presentation.headline, "Game forfeit.")
        XCTAssertEqual(presentation.detail, "Maya ended this game.")
    }

    func testRemoteDetailIsSuppressedAfterCheckmate() {
        let session = GameSession(
            state: GameState(
                board: Board(),
                sideToMove: .white,
                result: .checkmate(winner: .black)
            )
        )
        session.whitePlayer = .remote(playerID: "maya")

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: "Maya")

        XCTAssertEqual(presentation.headline, "Checkmate. Black wins.")
        XCTAssertNil(presentation.detail)
    }

    func testLocalGameHasNoDefaultDetail() {
        let session = GameSession()

        let presentation = TurnStatusPresentation(session: session, remoteOpponentName: nil)

        XCTAssertEqual(presentation.headline, "White's turn")
        XCTAssertNil(presentation.detail)
    }
}
