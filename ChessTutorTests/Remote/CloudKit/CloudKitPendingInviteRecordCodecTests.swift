import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitPendingInviteRecordCodecTests: XCTestCase {
    func testRecordNameIsInviteCodeAndFieldsRoundTrip() throws {
        let invite = makeInvite(inviteePlayerID: RemotePlayerID(rawValue: "maya"), inviteeDisplayName: "Maya")

        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let decoded = try CloudKitPendingInviteRecordCodec.invite(from: record)

        XCTAssertEqual(record.recordID.recordName, "428193")
        XCTAssertEqual(record["inviteCode"] as? String, "428193")
        XCTAssertEqual(record["inviteePlayerID"] as? String, "maya")
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

    func testAcceptanceRecordFieldsRoundTripWithPendingInvite() throws {
        let invite = makeInvite()
        let acceptedInvite = RemoteAcceptedInvite(
            invite: RemotePendingInvite(
                id: invite.id,
                code: invite.code,
                token: invite.token,
                inviter: invite.inviter,
                inviteeDisplayName: invite.inviteeDisplayName,
                whiteAssignment: invite.whiteAssignment,
                status: .accepted,
                createdAt: invite.createdAt,
                expiresAt: invite.expiresAt,
                protocolVersion: invite.protocolVersion
            ),
            joiner: RemotePlayerRef(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya"),
            joinerColor: .black
        )

        let record = CloudKitInviteAcceptanceRecordCodec.record(
            from: acceptedInvite,
            acceptedAt: Date(timeIntervalSince1970: 20)
        )
        let decoded = try CloudKitInviteAcceptanceRecordCodec.acceptedInvite(
            from: record,
            pendingInvite: invite
        )

        XCTAssertEqual(record.recordType, CloudKitInviteAcceptanceRecordCodec.recordType)
        XCTAssertEqual(record.recordID.recordName, "invite-acceptance-428193")
        XCTAssertEqual(record["inviteCode"] as? String, "428193")
        XCTAssertEqual(decoded, acceptedInvite)
    }

    private func makeInvite(
        inviteePlayerID: RemotePlayerID? = nil,
        inviteeDisplayName: String? = nil
    ) -> RemotePendingInvite {
        RemotePendingInvite(
            id: RemoteInviteID(rawValue: "428193"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
            inviteePlayerID: inviteePlayerID,
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
