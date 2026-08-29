import XCTest
@testable import ChessTutor

final class NewGameConfirmationPresentationTests: XCTestCase {
    func testLocalGameConfirmationUsesSimpleResetCopy() {
        let presentation = NewGameConfirmationPresentation.localGame

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "This will abandon the current game.")
        XCTAssertEqual(presentation.cancelActionTitle, "Keep Playing")
        XCTAssertNil(presentation.remoteInviteActionTitle)
        XCTAssertEqual(presentation.localResetActionTitle, "New Game")
    }

    func testRemoteGameConfirmationOffersSamePlayerInviteAndLocalReset() {
        let presentation = NewGameConfirmationPresentation.remoteGame(opponentName: "Maya")

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "You can invite Maya again or start a new game here.")
        XCTAssertEqual(presentation.cancelActionTitle, "Keep Playing")
        XCTAssertEqual(presentation.remoteInviteActionTitle, "Invite Maya Again")
        XCTAssertEqual(presentation.localResetActionTitle, "New Game Here")
    }

    func testCompletedRemoteGameStillOffersSamePlayerInviteAndLocalReset() {
        let presentation = NewGameConfirmationPresentation.presentation(
            result: .checkmate(winner: .white),
            isRemoteGameEnded: false,
            remoteOpponentName: "Maya"
        )

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "You can invite Maya again or start a new game here.")
        XCTAssertEqual(presentation.cancelActionTitle, "Keep Board")
        XCTAssertEqual(presentation.remoteInviteActionTitle, "Invite Maya Again")
        XCTAssertEqual(presentation.localResetActionTitle, "New Game Here")
    }

    func testCompletedGameConfirmationUsesBoardResetCopy() {
        let presentation = NewGameConfirmationPresentation.completedGame

        XCTAssertEqual(presentation.title, "Start a new game?")
        XCTAssertEqual(presentation.message, "The board will be reset.")
        XCTAssertEqual(presentation.cancelActionTitle, "Keep Board")
        XCTAssertNil(presentation.remoteInviteActionTitle)
        XCTAssertEqual(presentation.localResetActionTitle, "New Game")
    }

    func testNewGameRequestDoesNotConfirmWhenRemoteGameHasEnded() {
        XCTAssertFalse(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: false,
                isRemoteGameActive: true,
                gameResult: .checkmate(winner: .white)
            )
        )
    }

    func testNewGameRequestConfirmsForLocalGameInProgress() {
        XCTAssertTrue(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: true,
                isRemoteGameActive: false,
                gameResult: .ongoing
            )
        )
    }

    func testNewGameRequestConfirmsForRemoteGameBeforeFirstMove() {
        XCTAssertTrue(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: false,
                isRemoteGameActive: true,
                gameResult: .ongoing
            )
        )
    }

    func testNewGameRequestDoesNotConfirmForFinishedLocalGame() {
        XCTAssertFalse(
            NewGameRequestPolicy.shouldConfirm(
                hasGameInProgress: false,
                isRemoteGameActive: false,
                gameResult: .stalemate
            )
        )
    }

    func testPublishesRemoteEndOnlyWhenOngoingRemoteGameIsResetLocally() {
        XCTAssertTrue(RemoteGameEndPublishingPolicy.shouldPublishOnLocalReset(result: .ongoing))
        XCTAssertFalse(
            RemoteGameEndPublishingPolicy.shouldPublishOnLocalReset(result: .checkmate(winner: .white))
        )
        XCTAssertFalse(RemoteGameEndPublishingPolicy.shouldPublishOnLocalReset(result: .stalemate))
    }
}
