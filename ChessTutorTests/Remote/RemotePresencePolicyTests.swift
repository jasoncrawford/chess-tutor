import XCTest
@testable import ChessTutor

final class RemotePresencePolicyTests: XCTestCase {
    func testActiveMovingRepublishesBeforeCurrentUpdateExpires() {
        let lastPublishedAt = Date(timeIntervalSince1970: 10)

        XCTAssertFalse(
            RemotePresencePolicy.shouldPublishActiveMoving(
                lastPublishedAt: lastPublishedAt,
                now: Date(timeIntervalSince1970: 11)
            )
        )
        XCTAssertTrue(
            RemotePresencePolicy.shouldPublishActiveMoving(
                lastPublishedAt: lastPublishedAt,
                now: Date(timeIntervalSince1970: 12)
            )
        )
        XCTAssertLessThan(
            RemotePresencePolicy.activeMovingRepublishInterval,
            RemotePresencePolicy.activeMovingExpiresAfter
        )
    }
}
