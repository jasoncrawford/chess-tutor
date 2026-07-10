import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitPendingInviteRecordCodecTests: XCTestCase {
    func testRecordNameIsInviteCodeAndFieldsRoundTrip() throws {
        let invite = makeInvite(inviteeDisplayName: "Maya")

        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let decoded = try CloudKitPendingInviteRecordCodec.invite(from: record)

        XCTAssertEqual(record.recordID.recordName, "428193")
        XCTAssertEqual(record["inviteCode"] as? String, "428193")
        XCTAssertEqual(decoded, invite)
    }

    func testDecodingMissingRequiredFieldThrowsExactMissingFieldError() {
        let record = CloudKitPendingInviteRecordCodec.record(from: makeInvite())
        record["token"] = nil

        assertDecoding(record, throws: .missingField("token"))
    }

    func testDecodingInvalidWhiteAssignmentThrowsExactInvalidWhiteAssignmentError() {
        let record = CloudKitPendingInviteRecordCodec.record(from: makeInvite())
        record["whiteAssignment"] = "sideways" as CKRecordValue

        assertDecoding(record, throws: .invalidWhiteAssignment("sideways"))
    }

    func testDecodingInvalidStatusThrowsExactInvalidStatusError() {
        let record = CloudKitPendingInviteRecordCodec.record(from: makeInvite())
        record["status"] = "archived" as CKRecordValue

        assertDecoding(record, throws: .invalidStatus("archived"))
    }

    func testApplyingInviteWithNilInviteeDisplayNameClearsExistingValue() throws {
        let record = CloudKitPendingInviteRecordCodec.record(
            from: makeInvite(inviteeDisplayName: "Maya")
        )
        let inviteWithoutInviteeDisplayName = makeInvite(inviteeDisplayName: nil)

        CloudKitPendingInviteRecordCodec.apply(inviteWithoutInviteeDisplayName, to: record)

        let decoded = try CloudKitPendingInviteRecordCodec.invite(from: record)
        XCTAssertNil(decoded.inviteeDisplayName)
    }

    private func makeInvite(inviteeDisplayName: String? = nil) -> RemotePendingInvite {
        RemotePendingInvite(
            id: RemoteInviteID(rawValue: "428193"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
            inviteeDisplayName: inviteeDisplayName,
            whiteAssignment: .inviteeChooses,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 70),
            protocolVersion: 1
        )
    }

    private func assertDecoding(
        _ record: CKRecord,
        throws expectedError: CloudKitPendingInviteRecordCodec.Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CloudKitPendingInviteRecordCodec.invite(from: record),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CloudKitPendingInviteRecordCodec.Error,
                expectedError,
                file: file,
                line: line
            )
        }
    }
}
