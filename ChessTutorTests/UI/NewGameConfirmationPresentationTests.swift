import XCTest
@testable import ChessTutor

final class NewGameConfirmationPresentationTests: XCTestCase {
    func testLocalGameConfirmationUsesSimpleResetCopy() {
        let presentation = NewGameConfirmationPresentation.localGame

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "This will abandon the current game.")
        XCTAssertNil(presentation.remoteInviteActionTitle)
        XCTAssertEqual(presentation.localResetActionTitle, "New Game")
    }

    func testRemoteGameConfirmationOffersSamePlayerInviteAndLocalReset() {
        let presentation = NewGameConfirmationPresentation.remoteGame(opponentName: "Maya")

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "You can invite Maya again or start a new game here.")
        XCTAssertEqual(presentation.remoteInviteActionTitle, "Invite Maya Again")
        XCTAssertEqual(presentation.localResetActionTitle, "New Game Here")
    }

    func testNewGameRequestConfirmsWhenRemoteGameIsActiveAfterGameEnds() {
        XCTAssertTrue(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: false,
                isRemoteGameActive: true
            )
        )
    }

    func testNewGameRequestDoesNotConfirmForFinishedLocalGame() {
        XCTAssertFalse(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: false,
                isRemoteGameActive: false
            )
        )
    }
}
