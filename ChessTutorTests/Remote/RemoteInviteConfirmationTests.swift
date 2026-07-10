import XCTest
@testable import ChessTutor

final class RemoteInviteConfirmationTests: XCTestCase {
    func testFixedColorConfirmationCanStartImmediately() {
        let confirmation = RemoteInviteConfirmation(
            opponentName: "Maya",
            localPlayerColor: .black
        )

        XCTAssertEqual(confirmation.title, "Maya wants to play")
        XCTAssertEqual(confirmation.startButtonTitle, "Start")
        XCTAssertEqual(confirmation.cancelButtonTitle, "Cancel")
        XCTAssertTrue(confirmation.canStart)
        XCTAssertFalse(confirmation.requiresColorChoice)
        XCTAssertEqual(confirmation.whiteSeat.playerName, "Maya")
        XCTAssertEqual(confirmation.blackSeat.playerName, "You")
    }

    func testChoiceConfirmationRequiresColorBeforeStart() {
        let confirmation = RemoteInviteConfirmation(
            opponentName: "Maya",
            localPlayerColor: nil
        )

        XCTAssertEqual(confirmation.title, "Maya wants to play")
        XCTAssertTrue(confirmation.requiresColorChoice)
        XCTAssertFalse(confirmation.canStart)
        XCTAssertNil(confirmation.localPlayerColor)
        XCTAssertEqual(confirmation.whiteSeat.playerName, "Choose White")
        XCTAssertEqual(confirmation.blackSeat.playerName, "Choose Black")
    }

    func testChoosingColorEnablesStartAndAssignsSeats() {
        let confirmation = RemoteInviteConfirmation(
            opponentName: "Maya",
            localPlayerColor: nil
        ).selectColor(.white)

        XCTAssertTrue(confirmation.canStart)
        XCTAssertEqual(confirmation.localPlayerColor, .white)
        XCTAssertEqual(confirmation.whiteSeat.playerName, "You")
        XCTAssertEqual(confirmation.blackSeat.playerName, "Maya")
    }
}
