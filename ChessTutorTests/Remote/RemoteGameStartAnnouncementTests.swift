import XCTest
@testable import ChessTutor

final class RemoteGameStartAnnouncementTests: XCTestCase {
    func testAnnouncementShowsOpponentAndSeatsWhenLocalPlayerIsWhite() {
        let announcement = RemoteGameStartAnnouncement(
            opponentName: "Maya",
            localPlayerColor: .white
        )

        XCTAssertEqual(announcement.title, "You're playing Maya")
        XCTAssertEqual(announcement.whitePlayerName, "You")
        XCTAssertEqual(announcement.blackPlayerName, "Maya")
        XCTAssertEqual(announcement.whiteSeat.squareTone, .dark)
        XCTAssertEqual(announcement.blackSeat.squareTone, .light)
        XCTAssertEqual(announcement.buttonTitle, "Start")
    }

    func testAnnouncementShowsOpponentAndSeatsWhenLocalPlayerIsBlack() {
        let announcement = RemoteGameStartAnnouncement(
            opponentName: "Maya",
            localPlayerColor: .black
        )

        XCTAssertEqual(announcement.title, "You're playing Maya")
        XCTAssertEqual(announcement.whitePlayerName, "Maya")
        XCTAssertEqual(announcement.blackPlayerName, "You")
        XCTAssertEqual(announcement.whiteSeat.squareTone, .dark)
        XCTAssertEqual(announcement.blackSeat.squareTone, .light)
        XCTAssertEqual(announcement.buttonTitle, "Start")
    }
}
