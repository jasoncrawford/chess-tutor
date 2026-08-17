import XCTest
@testable import ChessTutor

final class GameControlsPresentationTests: XCTestCase {
    func testPresentationPromotesRemotePlayBeforePlayBegins() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemotePlayAvailable: true
        )

        XCTAssertEqual(presentation.primaryAction, .playRemotely)
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testPresentationUsesDoneAfterPlayBegins() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            isRemotePlayAvailable: false
        )

        XCTAssertEqual(presentation.primaryAction, .done)
        XCTAssertEqual(presentation.supplementalActions, [])
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testPresentationOffersHelpAsSupplementalActionWhenSessionAllowsIt() {
        let presentation = GameControlsPresentation(
            result: .ongoing,
            canRequestCoaching: true
        )

        XCTAssertEqual(presentation.primaryAction, .done)
        XCTAssertEqual(presentation.supplementalActions, [.help])
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testPresentationHidesHelpWheneverSessionPolicyDisallowsIt() {
        let unavailableCases: [(name: String, presentation: GameControlsPresentation)] = [
            (
                "active coaching",
                GameControlsPresentation(result: .ongoing, canRequestCoaching: false)
            ),
            (
                "remote turn",
                GameControlsPresentation(result: .ongoing, canRequestCoaching: false)
            ),
            (
                "remote lock",
                GameControlsPresentation(
                    result: .ongoing,
                    isRemoteGameEnded: true,
                    canRequestCoaching: false
                )
            ),
            (
                "promotion choice",
                GameControlsPresentation(result: .ongoing, canRequestCoaching: false)
            ),
            (
                "terminal result",
                GameControlsPresentation(
                    result: .checkmate(winner: .black),
                    canRequestCoaching: false
                )
            ),
        ]

        for unavailableCase in unavailableCases {
            XCTAssertEqual(
                unavailableCase.presentation.supplementalActions,
                [],
                "Unexpected Help action for \(unavailableCase.name)"
            )
        }
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
}
