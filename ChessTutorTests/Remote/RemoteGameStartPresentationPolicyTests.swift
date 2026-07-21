import XCTest
@testable import ChessTutor

final class RemoteGameStartPresentationPolicyTests: XCTestCase {
    func testOnlyInviterSeesGameStartAnnouncement() {
        XCTAssertTrue(RemoteGameStartPresentationPolicy.shouldShowAnnouncement(for: .inviter))
        XCTAssertFalse(RemoteGameStartPresentationPolicy.shouldShowAnnouncement(for: .joiner))
    }
}
