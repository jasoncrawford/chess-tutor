import UserNotifications
import XCTest
@testable import ChessTutor

final class RemoteNotificationPermissionPolicyTests: XCTestCase {
    func testRequestsOnlyWhenAuthorizationIsNotDetermined() {
        XCTAssertTrue(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .notDetermined))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .denied))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .authorized))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .provisional))
        XCTAssertFalse(RemoteNotificationPermissionPolicy.shouldRequestAuthorization(for: .ephemeral))
    }

    func testDiagnosticsNameDescribesAuthorizationStatus() {
        XCTAssertEqual(RemoteNotificationPermissionPolicy.diagnosticsName(for: .notDetermined), "notDetermined")
        XCTAssertEqual(RemoteNotificationPermissionPolicy.diagnosticsName(for: .denied), "denied")
        XCTAssertEqual(RemoteNotificationPermissionPolicy.diagnosticsName(for: .authorized), "authorized")
        XCTAssertEqual(RemoteNotificationPermissionPolicy.diagnosticsName(for: .provisional), "provisional")
        XCTAssertEqual(RemoteNotificationPermissionPolicy.diagnosticsName(for: .ephemeral), "ephemeral")
    }
}
