import XCTest
@testable import ChessTutor

final class RemoteInviteTransportModelTests: XCTestCase {
    func testWhiteAssignmentMapsJoinerColor() {
        XCTAssertEqual(RemoteInviteWhiteAssignment.inviter.localPlayerColorForJoiner, .black)
        XCTAssertEqual(RemoteInviteWhiteAssignment.invitee.localPlayerColorForJoiner, .white)
        XCTAssertNil(RemoteInviteWhiteAssignment.inviteeChooses.localPlayerColorForJoiner)
    }

    func testInviteCodeFormatsSixDigits() {
        XCTAssertEqual(InviteCode(rawValue: "428193").formatted, "428 193")
        XCTAssertEqual(InviteCode(rawValue: "12345").formatted, "12345")
    }
}
