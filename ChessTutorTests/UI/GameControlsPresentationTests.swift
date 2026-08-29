import XCTest
@testable import ChessTutor

final class GameControlsPresentationTests: XCTestCase {
    func testPresentationUsesDoneBeforeAnyLocalMoves() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemotePlayAvailable: true
        )

        XCTAssertEqual(presentation.primaryAction, .done)
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testPresentationUsesDoneAfterPlayBegins() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemotePlayAvailable: false
        )

        XCTAssertEqual(presentation.primaryAction, .done)
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testPresentationPromotesNewGameAfterCheckmate() {
        let presentation = GameControlsPresentation(
            result: .checkmate(winner: .black),
            isRemotePlayAvailable: true
        )

        XCTAssertEqual(presentation.primaryAction, .newGame)
        XCTAssertEqual(presentation.secondaryActions, [.about])
    }

    func testPresentationPromotesNewGameAfterOpponentEndsRemoteGame() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemoteGameEnded: true,
            isRemotePlayAvailable: false
        )

        XCTAssertEqual(presentation.primaryAction, .newGame)
        XCTAssertEqual(presentation.secondaryActions, [.about])
    }

    func testPresentationShowsNoNewGameActionForPendingInvitationBoard() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemoteGameEnded: true,
            isInvitationPending: true
        )

        XCTAssertEqual(presentation.primaryAction, .waiting)
        XCTAssertEqual(presentation.secondaryActions, [.about])
    }
}
