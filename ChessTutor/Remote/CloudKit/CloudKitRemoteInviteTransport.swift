import CloudKit
import Foundation

protocol CloudKitInviteDatabase: Sendable {
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>]
    )
}

extension CKDatabase: CloudKitInviteDatabase {
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        try await save(subscription)
    }
}

actor CloudKitRemoteInviteTransport: RemoteInviteTransport {
    private let database: any CloudKitInviteDatabase
    private let codeGenerator: @Sendable () -> InviteCode
    private let tokenGenerator: @Sendable () -> RemoteInviteToken

    init(
        database: any CloudKitInviteDatabase = CKContainer(identifier: "iCloud.org.jasoncrawford.chesstutor").publicCloudDatabase,
        codeGenerator: @escaping @Sendable () -> InviteCode = {
            InviteCode(rawValue: String(format: "%06d", Int.random(in: 0...999_999)))
        },
        tokenGenerator: @escaping @Sendable () -> RemoteInviteToken = {
            RemoteInviteToken(rawValue: UUID().uuidString)
        }
    ) {
        self.database = database
        self.codeGenerator = codeGenerator
        self.tokenGenerator = tokenGenerator
    }

    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite {
        let code = codeGenerator()
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: code.rawValue),
            code: code,
            token: tokenGenerator(),
            inviter: request.inviter,
            inviteeDisplayName: request.inviteeDisplayName,
            whiteAssignment: request.whiteAssignment,
            status: .pending,
            createdAt: request.now,
            expiresAt: request.expiresAt,
            protocolVersion: 1
        )
        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard savedRecord(record.recordID, in: result.saveResults) != nil else {
            throw RemoteInviteTransportError.codeCollision
        }
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
        try await fetchPendingInviteRecord(code: code, token: token, now: now).invite
    }

    private func fetchPendingInviteRecord(
        code: InviteCode,
        token: RemoteInviteToken?,
        now: Date
    ) async throws -> (invite: RemotePendingInvite, record: CKRecord) {
        let recordID = CKRecord.ID(recordName: code.rawValue)
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        if let token, token != invite.token {
            throw RemoteInviteTransportError.tokenMismatch
        }
        guard invite.status == .pending else {
            throw RemoteInviteTransportError.notPending
        }
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        if try await acceptanceRecordExists(for: invite.id) {
            throw RemoteInviteTransportError.notPending
        }
        return (invite, record)
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let fetched = try await fetchPendingInviteRecord(code: request.code, token: request.token, now: request.now)
        let invite = fetched.invite
        let joinerColor: PieceColor
        if let fixedColor = invite.whiteAssignment.localPlayerColorForJoiner {
            guard chosenColor == nil || chosenColor == fixedColor else {
                throw RemoteInviteTransportError.colorChoiceNotAllowed
            }
            joinerColor = fixedColor
        } else {
            guard let chosenColor else {
                throw RemoteInviteTransportError.colorChoiceRequired
            }
            joinerColor = chosenColor
        }

        let acceptedInviteRecord = RemotePendingInvite(
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
        )
        let acceptedInvite = RemoteAcceptedInvite(
            invite: acceptedInviteRecord,
            joiner: request.joiner,
            joinerColor: joinerColor
        )
        let acceptanceRecord = CloudKitInviteAcceptanceRecordCodec.record(
            from: acceptedInvite,
            acceptedAt: request.now
        )
        let result = try await database.modifyRecords(
            saving: [acceptanceRecord],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard savedRecord(acceptanceRecord.recordID, in: result.saveResults) != nil else {
            throw RemoteInviteTransportError.notPending
        }
        return acceptedInvite
    }

    func acceptedInvite(id: RemoteInviteID, now: Date) async throws -> RemoteAcceptedInvite? {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let acceptanceRecordID = CloudKitInviteAcceptanceRecordCodec.recordID(for: id)
        let results = try await database.records(for: [recordID, acceptanceRecordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        if invite.status == .accepted {
            return try CloudKitPendingInviteRecordCodec.acceptedInvite(from: record)
        }
        guard case .success(let acceptanceRecord) = results[acceptanceRecordID] else {
            return nil
        }
        guard invite.status == .pending else {
            return nil
        }
        return try CloudKitInviteAcceptanceRecordCodec.acceptedInvite(
            from: acceptanceRecord,
            pendingInvite: invite
        )
    }

    func prepareAcceptanceNotification(for invite: RemotePendingInvite) async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudKitInviteAcceptanceRecordCodec.recordType,
            predicate: NSPredicate(format: "%K == %@", "inviteCode", invite.code.rawValue),
            subscriptionID: acceptanceSubscriptionID(for: invite.id),
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try await database.saveSubscription(subscription)
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let result = try await database.modifyRecords(
            saving: [],
            deleting: [recordID],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard deletedRecord(recordID, in: result.deleteResults) else {
            throw RemoteInviteTransportError.notFound
        }
    }

    private func savedRecord(
        _ recordID: CKRecord.ID,
        in results: [CKRecord.ID: Result<CKRecord, any Error>]
    ) -> CKRecord? {
        guard case .success(let record) = results[recordID] else {
            return nil
        }
        return record
    }

    private func deletedRecord(
        _ recordID: CKRecord.ID,
        in results: [CKRecord.ID: Result<Void, any Error>]
    ) -> Bool {
        guard case .success = results[recordID] else {
            return false
        }
        return true
    }

    private func acceptanceRecordExists(for id: RemoteInviteID) async throws -> Bool {
        let recordID = CloudKitInviteAcceptanceRecordCodec.recordID(for: id)
        let results = try await database.records(for: [recordID], desiredKeys: [])
        guard case .success = results[recordID] else {
            return false
        }
        return true
    }

    static func inviteID(fromAcceptanceSubscriptionID subscriptionID: String) -> RemoteInviteID? {
        guard subscriptionID.hasPrefix(acceptanceSubscriptionIDPrefix) else {
            return nil
        }
        let rawValue = String(subscriptionID.dropFirst(acceptanceSubscriptionIDPrefix.count))
        return RemoteInviteID(rawValue: rawValue)
    }

    private func acceptanceSubscriptionID(for id: RemoteInviteID) -> String {
        Self.acceptanceSubscriptionIDPrefix + id.rawValue
    }

    private static let acceptanceSubscriptionIDPrefix = "pending-invite-accepted-"
}

enum CloudKitInviteAcceptanceRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidJoinerColor(String)
    }

    static let recordType = "InviteAcceptance"

    private enum Field {
        static let inviteCode = "inviteCode"
        static let acceptedJoinerPlayerID = "acceptedJoinerPlayerID"
        static let acceptedJoinerDisplayName = "acceptedJoinerDisplayName"
        static let acceptedJoinerColor = "acceptedJoinerColor"
        static let acceptedAt = "acceptedAt"
    }

    static func recordID(for inviteID: RemoteInviteID) -> CKRecord.ID {
        CKRecord.ID(recordName: "invite-acceptance-\(inviteID.rawValue)")
    }

    static func record(from acceptedInvite: RemoteAcceptedInvite, acceptedAt: Date) -> CKRecord {
        let record = CKRecord(
            recordType: recordType,
            recordID: recordID(for: acceptedInvite.invite.id)
        )
        record[Field.inviteCode] = acceptedInvite.invite.code.rawValue as CKRecordValue
        record[Field.acceptedJoinerPlayerID] = acceptedInvite.joiner.id.rawValue as CKRecordValue
        record[Field.acceptedJoinerDisplayName] = acceptedInvite.joiner.displayName as CKRecordValue
        record[Field.acceptedJoinerColor] = acceptedInvite.joinerColor.rawValue as CKRecordValue
        record[Field.acceptedAt] = acceptedAt as CKRecordValue
        return record
    }

    static func acceptedInvite(
        from record: CKRecord,
        pendingInvite: RemotePendingInvite
    ) throws -> RemoteAcceptedInvite {
        let joinerColorRaw = try string(Field.acceptedJoinerColor, from: record)
        guard let joinerColor = PieceColor(rawValue: joinerColorRaw) else {
            throw Error.invalidJoinerColor(joinerColorRaw)
        }
        let acceptedInvite = RemotePendingInvite(
            id: pendingInvite.id,
            code: pendingInvite.code,
            token: pendingInvite.token,
            inviter: pendingInvite.inviter,
            inviteeDisplayName: pendingInvite.inviteeDisplayName,
            whiteAssignment: pendingInvite.whiteAssignment,
            status: .accepted,
            createdAt: pendingInvite.createdAt,
            expiresAt: pendingInvite.expiresAt,
            protocolVersion: pendingInvite.protocolVersion
        )
        return RemoteAcceptedInvite(
            invite: acceptedInvite,
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
}
