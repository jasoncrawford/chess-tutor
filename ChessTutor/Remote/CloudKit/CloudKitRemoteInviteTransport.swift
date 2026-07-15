import CloudKit
import Foundation

protocol CloudKitInviteDatabase: Sendable {
    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]

    func records(
        matching query: CKQuery,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> [CKRecord]

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

    func records(
        matching query: CKQuery,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> [CKRecord] {
        let results = try await records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: desiredKeys,
            resultsLimit: resultsLimit
        )
        return try results.matchResults.compactMap { _, result in
            try result.get()
        }
    }
}

actor CloudKitRemoteInviteTransport: RemoteInviteTransport {
    private let database: any CloudKitInviteDatabase
    private let codeGenerator: @Sendable () -> InviteCode
    private let tokenGenerator: @Sendable () -> RemoteInviteToken
    private let diagnosticsLog: DiagnosticsLog

    init(
        database: any CloudKitInviteDatabase = CKContainer(identifier: "iCloud.org.jasoncrawford.chesstutor").publicCloudDatabase,
        codeGenerator: @escaping @Sendable () -> InviteCode = {
            InviteCode(rawValue: String(format: "%06d", Int.random(in: 0...999_999)))
        },
        tokenGenerator: @escaping @Sendable () -> RemoteInviteToken = {
            RemoteInviteToken(rawValue: UUID().uuidString)
        },
        diagnosticsLog: DiagnosticsLog = .shared
    ) {
        self.database = database
        self.codeGenerator = codeGenerator
        self.tokenGenerator = tokenGenerator
        self.diagnosticsLog = diagnosticsLog
    }

    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite {
        let code = codeGenerator()
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: code.rawValue),
            code: code,
            token: tokenGenerator(),
            inviter: request.inviter,
            inviteePlayerID: request.inviteePlayerID,
            inviteeDisplayName: request.inviteeDisplayName,
            whiteAssignment: request.whiteAssignment,
            status: .pending,
            createdAt: request.now,
            expiresAt: request.expiresAt,
            protocolVersion: 1
        )
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "createSaving",
            fields: [
                "code": invite.code.rawValue,
                "inviteID": invite.id.rawValue,
                "tokenSuffix": DiagnosticsLog.tokenSuffix(invite.token),
                "whiteAssignment": invite.whiteAssignment.rawValue
            ]
        )
        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        CloudKitPendingInviteRecordCodec.applyNotificationBody(request.notificationBody, to: record)
        let result: (
            saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
            deleteResults: [CKRecord.ID: Result<Void, any Error>]
        )
        do {
            result = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
        } catch {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "createSaveThrown",
                fields: [
                    "code": invite.code.rawValue,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
        guard savedRecord(record.recordID, in: result.saveResults) != nil else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "createSaveRejected",
                fields: ["code": invite.code.rawValue, "mappedError": "codeCollision"]
            )
            throw RemoteInviteTransportError.codeCollision
        }
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "createSaved",
            fields: [
                "code": invite.code.rawValue,
                "recordID": record.recordID.recordName,
                "inviteePlayerID": invite.inviteePlayerID?.rawValue ?? "none",
                "notificationBody": request.notificationBody
            ]
        )
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
        do {
            let invite = try await fetchPendingInviteRecord(code: code, token: token, now: now).invite
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchReturned",
                fields: [
                    "code": code.rawValue,
                    "inviteID": invite.id.rawValue,
                    "status": invite.status.rawValue,
                    "tokenSuffix": DiagnosticsLog.tokenSuffix(token)
                ]
            )
            return invite
        } catch {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchFailed",
                fields: [
                    "code": code.rawValue,
                    "tokenSuffix": DiagnosticsLog.tokenSuffix(token),
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
    }

    private func fetchPendingInviteRecord(
        code: InviteCode,
        token: RemoteInviteToken?,
        now: Date
    ) async throws -> (invite: RemotePendingInvite, record: CKRecord) {
        let recordID = CKRecord.ID(recordName: code.rawValue)
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await database.records(for: [recordID], desiredKeys: nil)
        } catch {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchRecordThrown",
                fields: [
                    "code": code.rawValue,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
        guard case .success(let record) = results[recordID] else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchRecordMissing",
                fields: ["code": code.rawValue]
            )
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        if let token, token != invite.token {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchTokenMismatch",
                fields: [
                    "code": code.rawValue,
                    "providedTokenSuffix": DiagnosticsLog.tokenSuffix(token),
                    "storedTokenSuffix": DiagnosticsLog.tokenSuffix(invite.token)
                ]
            )
            throw RemoteInviteTransportError.tokenMismatch
        }
        if invite.status == .cancelled {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchCancelled",
                fields: ["code": code.rawValue, "inviterID": invite.inviter.id.rawValue]
            )
            throw RemoteInviteTransportError.cancelled(inviterDisplayName: invite.inviter.displayName)
        }
        if invite.status == .declined {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchDeclined",
                fields: ["code": code.rawValue, "inviteeDisplayName": invite.inviteeDisplayName ?? "none"]
            )
            throw RemoteInviteTransportError.declined(inviteeDisplayName: invite.inviteeDisplayName)
        }
        guard invite.status == .pending else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchNotPending",
                fields: ["code": code.rawValue, "status": invite.status.rawValue]
            )
            throw RemoteInviteTransportError.notPending
        }
        guard invite.expiresAt > now else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchExpired",
                fields: ["code": code.rawValue, "expiresAt": "\(invite.expiresAt.timeIntervalSince1970)"]
            )
            throw RemoteInviteTransportError.expired
        }
        if try await acceptanceRecordExists(for: invite.id) {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "fetchAcceptanceAlreadyExists",
                fields: ["code": code.rawValue, "inviteID": invite.id.rawValue]
            )
            throw RemoteInviteTransportError.notPending
        }
        return (invite, record)
    }

    func fetchPendingInvite(for inviteePlayerID: RemotePlayerID, now: Date) async throws -> RemotePendingInvite? {
        let query = CKQuery(
            recordType: CloudKitPendingInviteRecordCodec.recordType,
            predicate: NSPredicate(
                format: "%K == %@ AND %K == %@",
                "inviteePlayerID",
                inviteePlayerID.rawValue,
                "status",
                RemoteInviteStatus.pending.rawValue
            )
        )
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let records = try await database.records(matching: query, desiredKeys: nil, resultsLimit: 20)
        for record in records {
            let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
            let alreadyAccepted = try await acceptanceRecordExists(for: invite.id)
            guard invite.inviteePlayerID == inviteePlayerID,
                  invite.status == .pending,
                  invite.expiresAt > now,
                  !alreadyAccepted else {
                continue
            }
            return invite
        }
        return nil
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let fetched = try await fetchPendingInviteRecord(code: request.code, token: request.token, now: request.now)
        let invite = fetched.invite
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "acceptPreparing",
            fields: [
                "code": invite.code.rawValue,
                "inviteID": invite.id.rawValue,
                "chosenColor": chosenColor?.rawValue ?? "none"
            ]
        )
        let joinerColor: PieceColor
        if let fixedColor = invite.whiteAssignment.localPlayerColorForJoiner {
            guard chosenColor == nil || chosenColor == fixedColor else {
                await diagnosticsLog.append(
                    category: "cloudKitInvite",
                    "acceptColorNotAllowed",
                    fields: [
                        "inviteID": invite.id.rawValue,
                        "chosenColor": chosenColor?.rawValue ?? "none",
                        "fixedColor": fixedColor.rawValue
                    ]
                )
                throw RemoteInviteTransportError.colorChoiceNotAllowed
            }
            joinerColor = fixedColor
        } else {
            guard let chosenColor else {
                await diagnosticsLog.append(
                    category: "cloudKitInvite",
                    "acceptColorRequired",
                    fields: ["inviteID": invite.id.rawValue]
                )
                throw RemoteInviteTransportError.colorChoiceRequired
            }
            joinerColor = chosenColor
        }

        let acceptedInviteRecord = RemotePendingInvite(
            id: invite.id,
            code: invite.code,
            token: invite.token,
            inviter: invite.inviter,
            inviteePlayerID: invite.inviteePlayerID,
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
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "acceptSaveRejected",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "acceptanceRecordID": acceptanceRecord.recordID.recordName
                ]
            )
            throw RemoteInviteTransportError.notPending
        }
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "acceptSaved",
            fields: [
                "inviteID": invite.id.rawValue,
                "acceptanceRecordID": acceptanceRecord.recordID.recordName,
                "joinerID": request.joiner.id.rawValue,
                "joinerColor": joinerColor.rawValue
            ]
        )
        return acceptedInvite
    }

    func acceptedInvite(id: RemoteInviteID, now: Date) async throws -> RemoteAcceptedInvite? {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let acceptanceRecordID = CloudKitInviteAcceptanceRecordCodec.recordID(for: id)
        let results = try await database.records(for: [recordID, acceptanceRecordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "acceptedInvitePendingRecordMissing",
                fields: ["inviteID": id.rawValue]
            )
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        if invite.status == .cancelled {
            throw RemoteInviteTransportError.cancelled(inviterDisplayName: invite.inviter.displayName)
        }
        if invite.status == .declined {
            throw RemoteInviteTransportError.declined(inviteeDisplayName: invite.inviteeDisplayName)
        }
        if invite.status == .accepted {
            return try CloudKitPendingInviteRecordCodec.acceptedInvite(from: record)
        }
        guard case .success(let acceptanceRecord) = results[acceptanceRecordID] else {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "acceptedInviteNotReady",
                fields: ["inviteID": id.rawValue, "acceptanceRecordID": acceptanceRecordID.recordName]
            )
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
        let acceptanceSubscription = CKQuerySubscription(
            recordType: CloudKitInviteAcceptanceRecordCodec.recordType,
            predicate: NSPredicate(format: "%K == %@", "inviteCode", invite.code.rawValue),
            subscriptionID: acceptanceSubscriptionID(for: invite.id),
            options: [.firesOnRecordCreation]
        )
        let acceptanceNotificationInfo = CKSubscription.NotificationInfo()
        acceptanceNotificationInfo.shouldSendContentAvailable = true
        acceptanceSubscription.notificationInfo = acceptanceNotificationInfo
        do {
            _ = try await database.saveSubscription(acceptanceSubscription)
        } catch {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "acceptanceSubscriptionFailed",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "subscriptionID": acceptanceSubscription.subscriptionID,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
        let statusSubscription = CKQuerySubscription(
            recordType: CloudKitPendingInviteRecordCodec.recordType,
            predicate: NSPredicate(format: "%K == %@", "inviteCode", invite.code.rawValue),
            subscriptionID: statusSubscriptionID(for: invite.id),
            options: [.firesOnRecordUpdate]
        )
        let statusNotificationInfo = CKSubscription.NotificationInfo()
        statusNotificationInfo.shouldSendContentAvailable = true
        statusSubscription.notificationInfo = statusNotificationInfo
        do {
            _ = try await database.saveSubscription(statusSubscription)
        } catch {
            await diagnosticsLog.append(
                category: "cloudKitInvite",
                "inviteStatusSubscriptionFailed",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "subscriptionID": statusSubscription.subscriptionID,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "acceptanceSubscriptionSaved",
            fields: [
                "inviteID": invite.id.rawValue,
                "subscriptionID": acceptanceSubscription.subscriptionID,
                "statusSubscriptionID": statusSubscription.subscriptionID
            ]
        )
    }

    func prepareIncomingInviteNotification(for inviteePlayerID: RemotePlayerID) async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudKitPendingInviteRecordCodec.recordType,
            predicate: NSPredicate(
                format: "%K == %@ AND %K == %@",
                "inviteePlayerID",
                inviteePlayerID.rawValue,
                "status",
                RemoteInviteStatus.pending.rawValue
            ),
            subscriptionID: Self.incomingInviteSubscriptionID(for: inviteePlayerID),
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.alertLocalizationKey = "REMOTE_INVITE_NOTIFICATION_BODY"
        notificationInfo.alertLocalizationArgs = [CloudKitPendingInviteRecordCodec.notificationBodyFieldName]
        subscription.notificationInfo = notificationInfo
        _ = try await database.saveSubscription(subscription)
        await diagnosticsLog.append(
            category: "cloudKitInvite",
            "incomingInviteSubscriptionSaved",
            fields: [
                "inviteePlayerID": inviteePlayerID.rawValue,
                "subscriptionID": subscription.subscriptionID
            ]
        )
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        try await updateInviteStatus(id: id, status: .cancelled)
    }

    func declineInvite(id: RemoteInviteID) async throws {
        try await updateInviteStatus(id: id, status: .declined)
    }

    private func updateInviteStatus(id: RemoteInviteID, status: RemoteInviteStatus) async throws {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        let records = try await database.records(for: [recordID], desiredKeys: nil)
        guard case .success(let record) = records[recordID] else {
            throw RemoteInviteTransportError.notFound
        }
        let invite = try CloudKitPendingInviteRecordCodec.invite(from: record)
        let updatedInvite = RemotePendingInvite(
            id: invite.id,
            code: invite.code,
            token: invite.token,
            inviter: invite.inviter,
            inviteePlayerID: invite.inviteePlayerID,
            inviteeDisplayName: invite.inviteeDisplayName,
            whiteAssignment: invite.whiteAssignment,
            status: status,
            createdAt: invite.createdAt,
            expiresAt: invite.expiresAt,
            protocolVersion: invite.protocolVersion
        )
        CloudKitPendingInviteRecordCodec.apply(updatedInvite, to: record)
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard savedRecord(recordID, in: result.saveResults) != nil else {
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

    static func inviteID(fromStatusSubscriptionID subscriptionID: String) -> RemoteInviteID? {
        guard subscriptionID.hasPrefix(statusSubscriptionIDPrefix) else {
            return nil
        }
        let rawValue = String(subscriptionID.dropFirst(statusSubscriptionIDPrefix.count))
        return RemoteInviteID(rawValue: rawValue)
    }

    static func playerID(fromIncomingInviteSubscriptionID subscriptionID: String) -> RemotePlayerID? {
        guard subscriptionID.hasPrefix(incomingInviteSubscriptionIDPrefix) else {
            return nil
        }
        let rawValue = String(subscriptionID.dropFirst(incomingInviteSubscriptionIDPrefix.count))
        return RemotePlayerID(rawValue: rawValue)
    }

    private func acceptanceSubscriptionID(for id: RemoteInviteID) -> String {
        Self.acceptanceSubscriptionIDPrefix + id.rawValue
    }

    private func statusSubscriptionID(for id: RemoteInviteID) -> String {
        Self.statusSubscriptionIDPrefix + id.rawValue
    }

    private static func incomingInviteSubscriptionID(for playerID: RemotePlayerID) -> String {
        incomingInviteSubscriptionIDPrefix + playerID.rawValue
    }

    private static let acceptanceSubscriptionIDPrefix = "pending-invite-accepted-"
    private static let statusSubscriptionIDPrefix = "pending-invite-status-"
    private static let incomingInviteSubscriptionIDPrefix = "pending-invite-for-"
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
            inviteePlayerID: pendingInvite.inviteePlayerID,
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
