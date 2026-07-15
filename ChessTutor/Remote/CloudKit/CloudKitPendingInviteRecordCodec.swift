import CloudKit
import Foundation

enum CloudKitPendingInviteRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidWhiteAssignment(String)
        case invalidStatus(String)
        case invalidJoinerColor(String)
    }

    static let recordType = "PendingInvite"

    private enum Field {
        static let inviteCode = "inviteCode"
        static let token = "token"
        static let inviterPlayerID = "inviterPlayerID"
        static let inviterDisplayName = "inviterDisplayName"
        static let inviteePlayerID = "inviteePlayerID"
        static let inviteeDisplayName = "inviteeDisplayName"
        static let notificationBody = "notificationBody"
        static let whiteAssignment = "whiteAssignment"
        static let status = "status"
        static let acceptedJoinerPlayerID = "acceptedJoinerPlayerID"
        static let acceptedJoinerDisplayName = "acceptedJoinerDisplayName"
        static let acceptedJoinerColor = "acceptedJoinerColor"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
        static let protocolVersion = "protocolVersion"
    }

    static func record(from invite: RemotePendingInvite) -> CKRecord {
        let recordID = CKRecord.ID(recordName: invite.code.rawValue)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        apply(invite, to: record)
        return record
    }

    static func apply(_ invite: RemotePendingInvite, to record: CKRecord) {
        record[Field.inviteCode] = invite.code.rawValue as CKRecordValue
        record[Field.token] = invite.token.rawValue as CKRecordValue
        record[Field.inviterPlayerID] = invite.inviter.id.rawValue as CKRecordValue
        record[Field.inviterDisplayName] = invite.inviter.displayName as CKRecordValue
        record[Field.inviteePlayerID] = invite.inviteePlayerID?.rawValue as CKRecordValue?
        record[Field.inviteeDisplayName] = invite.inviteeDisplayName as CKRecordValue?
        record[Field.whiteAssignment] = invite.whiteAssignment.rawValue as CKRecordValue
        record[Field.status] = invite.status.rawValue as CKRecordValue
        record[Field.createdAt] = invite.createdAt as CKRecordValue
        record[Field.expiresAt] = invite.expiresAt as CKRecordValue
        record[Field.protocolVersion] = invite.protocolVersion as CKRecordValue
    }

    static func applyNotificationBody(_ notificationBody: String, to record: CKRecord) {
        record[Field.notificationBody] = notificationBody as CKRecordValue
    }

    static var notificationBodyFieldName: String {
        Field.notificationBody
    }

    static func apply(_ acceptedInvite: RemoteAcceptedInvite, to record: CKRecord) {
        apply(acceptedInvite.invite, to: record)
        record[Field.acceptedJoinerPlayerID] = acceptedInvite.joiner.id.rawValue as CKRecordValue
        record[Field.acceptedJoinerDisplayName] = acceptedInvite.joiner.displayName as CKRecordValue
        record[Field.acceptedJoinerColor] = acceptedInvite.joinerColor.rawValue as CKRecordValue
    }

    static func invite(from record: CKRecord) throws -> RemotePendingInvite {
        let whiteAssignmentRaw = try string(Field.whiteAssignment, from: record)
        guard let whiteAssignment = RemoteInviteWhiteAssignment(rawValue: whiteAssignmentRaw) else {
            throw Error.invalidWhiteAssignment(whiteAssignmentRaw)
        }

        let statusRaw = try string(Field.status, from: record)
        guard let status = RemoteInviteStatus(rawValue: statusRaw) else {
            throw Error.invalidStatus(statusRaw)
        }

        return RemotePendingInvite(
            id: RemoteInviteID(rawValue: record.recordID.recordName),
            code: InviteCode(rawValue: record.recordID.recordName),
            token: RemoteInviteToken(rawValue: try string(Field.token, from: record)),
            inviter: RemotePlayerRef(
                id: RemotePlayerID(rawValue: try string(Field.inviterPlayerID, from: record)),
                displayName: try string(Field.inviterDisplayName, from: record)
            ),
            inviteePlayerID: (record[Field.inviteePlayerID] as? String).map(RemotePlayerID.init(rawValue:)),
            inviteeDisplayName: record[Field.inviteeDisplayName] as? String,
            whiteAssignment: whiteAssignment,
            status: status,
            createdAt: try date(Field.createdAt, from: record),
            expiresAt: try date(Field.expiresAt, from: record),
            protocolVersion: try int(Field.protocolVersion, from: record)
        )
    }

    static func acceptedInvite(from record: CKRecord) throws -> RemoteAcceptedInvite {
        let invite = try invite(from: record)
        let joinerColorRaw = try string(Field.acceptedJoinerColor, from: record)
        guard let joinerColor = PieceColor(rawValue: joinerColorRaw) else {
            throw Error.invalidJoinerColor(joinerColorRaw)
        }

        return RemoteAcceptedInvite(
            invite: invite,
            joiner: RemotePlayerRef(
                id: RemotePlayerID(rawValue: try string(Field.acceptedJoinerPlayerID, from: record)),
                displayName: try string(Field.acceptedJoinerDisplayName, from: record)
            ),
            joinerColor: joinerColor
        )
    }

    private static func string(_ key: String, from record: CKRecord) throws -> String {
        guard let value = record[key] as? String else {
            throw Error.missingField(key)
        }
        return value
    }

    private static func date(_ key: String, from record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw Error.missingField(key)
        }
        return value
    }

    private static func int(_ key: String, from record: CKRecord) throws -> Int {
        guard let value = record[key] as? Int else {
            throw Error.missingField(key)
        }
        return value
    }
}
