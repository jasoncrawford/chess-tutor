import CloudKit
import Foundation

protocol CloudKitGameDatabase: Sendable {
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

extension CKDatabase: CloudKitGameDatabase {}

actor CloudKitRemoteGameTransport: RemoteGameTransport,
    RemoteGameMoveNotificationPreparing,
    RemoteGameLifecycleTransport,
    RemoteGameLifecycleNotificationPreparing,
    RemotePresenceTransport {
    enum Error: Swift.Error, Equatable {
        case conflictingSequence(Int)
        case missingSavedRecord
        case fetchFailed
    }

    private let database: any CloudKitGameDatabase
    private let fetchBatchSize: Int
    private let diagnosticsLog: DiagnosticsLog
    static let moveSubscriptionIDPrefix = "remote-game-moves-"
    static let statusSubscriptionIDPrefix = "remote-game-status-"

    init(
        database: any CloudKitGameDatabase = CKContainer(identifier: "iCloud.org.jasoncrawford.chesstutor").publicCloudDatabase,
        fetchBatchSize: Int = 20,
        diagnosticsLog: DiagnosticsLog = .shared
    ) {
        self.database = database
        self.fetchBatchSize = fetchBatchSize
        self.diagnosticsLog = diagnosticsLog
    }

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        let record = CloudKitRemoteMoveRecordCodec.record(from: event)
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "sendMoveSaving",
            fields: [
                "gameID": event.gameID.rawValue,
                "sequence": "\(event.sequenceNumber)",
                "eventID": event.id.rawValue,
                "actorPlayerID": event.actorPlayerID.rawValue
            ]
        )
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )

        if savedRecord(record.recordID, in: result.saveResults) != nil {
            await diagnosticsLog.append(
                category: "cloudKitGame",
                "sendMoveSaved",
                fields: [
                    "gameID": event.gameID.rawValue,
                    "sequence": "\(event.sequenceNumber)",
                    "recordID": record.recordID.recordName
                ]
            )
            return RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber)
        }

        let existingEvent = try await existingEvent(for: record.recordID)
        guard existingEvent == event else {
            await diagnosticsLog.append(
                category: "cloudKitGame",
                "sendMoveConflict",
                fields: ["gameID": event.gameID.rawValue, "sequence": "\(event.sequenceNumber)"]
            )
            throw Error.conflictingSequence(event.sequenceNumber)
        }
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "sendMoveIdempotent",
            fields: ["gameID": event.gameID.rawValue, "sequence": "\(event.sequenceNumber)"]
        )
        return RemoteMoveAck(
            eventID: existingEvent.id,
            gameID: existingEvent.gameID,
            sequenceNumber: existingEvent.sequenceNumber
        )
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        var events: [RemoteMoveEvent] = []
        var nextSequence = sequenceNumber + 1
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "fetchMovesStarted",
            fields: ["gameID": gameID.rawValue, "afterSequence": "\(sequenceNumber)"]
        )

        while true {
            let ids = (nextSequence..<(nextSequence + fetchBatchSize)).map {
                CloudKitRemoteMoveRecordCodec.recordID(gameID: gameID, sequenceNumber: $0)
            }
            let results = try await database.records(for: ids, desiredKeys: nil)

            for id in ids {
                guard let result = results[id] else {
                    return events
                }
                switch result {
                case .success(let record):
                    events.append(try CloudKitRemoteMoveRecordCodec.event(from: record))
                    nextSequence += 1
                case .failure(let error):
                    guard isMissingRecord(error) else {
                        await diagnosticsLog.append(
                            category: "cloudKitGame",
                            "fetchMovesFailed",
                            fields: [
                                "gameID": gameID.rawValue,
                                "afterSequence": "\(sequenceNumber)",
                                "error": String(describing: error)
                            ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                        )
                        throw Error.fetchFailed
                    }
                    await diagnosticsLog.append(
                        category: "cloudKitGame",
                        "fetchMovesReturned",
                        fields: [
                            "gameID": gameID.rawValue,
                            "afterSequence": "\(sequenceNumber)",
                            "count": "\(events.count)"
                        ]
                    )
                    return events
                }
            }
        }
    }

    func updateGameStatus(_ status: RemoteGameStatusUpdate) async throws {
        let record = CloudKitRemoteGameStatusRecordCodec.record(from: status)
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "statusSaving",
            fields: [
                "gameID": status.gameID.rawValue,
                "status": status.status.rawValue,
                "updatedByPlayerID": status.updatedByPlayerID.rawValue
            ]
        )
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard savedRecord(record.recordID, in: result.saveResults) != nil else {
            await diagnosticsLog.append(
                category: "cloudKitGame",
                "statusSaveRejected",
                fields: ["gameID": status.gameID.rawValue]
            )
            throw Error.missingSavedRecord
        }
    }

    func fetchGameStatus(gameID: RemoteGameID) async throws -> RemoteGameStatusUpdate? {
        let recordID = CloudKitRemoteGameStatusRecordCodec.recordID(gameID: gameID)
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard let result = results[recordID] else {
            return nil
        }
        switch result {
        case .success(let record):
            return try CloudKitRemoteGameStatusRecordCodec.status(from: record)
        case .failure(let error):
            guard isMissingRecord(error) else {
                await diagnosticsLog.append(
                    category: "cloudKitGame",
                    "statusFetchFailed",
                    fields: [
                        "gameID": gameID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
                throw Error.fetchFailed
            }
            return nil
        }
    }

    func updatePresence(_ presence: RemotePresenceUpdate) async throws {
        if let existingPresence = try await fetchPresence(gameID: presence.gameID, playerID: presence.playerID),
           existingPresence.updatedAt > presence.updatedAt {
            await diagnosticsLog.append(
                category: "cloudKitGame",
                "presenceSkippedOlderUpdate",
                fields: ["gameID": presence.gameID.rawValue, "playerID": presence.playerID.rawValue]
            )
            return
        }

        let record = CloudKitRemotePresenceRecordCodec.record(from: presence)
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        guard savedRecord(record.recordID, in: result.saveResults) != nil else {
            await diagnosticsLog.append(
                category: "cloudKitGame",
                "presenceSaveRejected",
                fields: ["gameID": presence.gameID.rawValue, "playerID": presence.playerID.rawValue]
            )
            throw Error.missingSavedRecord
        }
    }

    func fetchPresence(gameID: RemoteGameID, playerID: RemotePlayerID) async throws -> RemotePresenceUpdate? {
        let recordID = CloudKitRemotePresenceRecordCodec.recordID(gameID: gameID, playerID: playerID)
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard let result = results[recordID] else {
            return nil
        }
        switch result {
        case .success(let record):
            return try CloudKitRemotePresenceRecordCodec.presence(from: record)
        case .failure(let error):
            guard isMissingRecord(error) else {
                await diagnosticsLog.append(
                    category: "cloudKitGame",
                    "presenceFetchFailed",
                    fields: [
                        "gameID": gameID.rawValue,
                        "playerID": playerID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
                throw Error.fetchFailed
            }
            return nil
        }
    }

    func prepareMoveNotification(for descriptor: RemoteGameDescriptor) async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudKitRemoteMoveRecordCodec.recordType,
            predicate: NSPredicate(
                format: "%K == %@ AND %K != %@",
                CloudKitRemoteMoveRecordCodec.Field.gameID,
                descriptor.id.rawValue,
                CloudKitRemoteMoveRecordCodec.Field.actorPlayerID,
                descriptor.localPlayerID.rawValue
            ),
            subscriptionID: Self.moveSubscriptionID(for: descriptor.id),
            options: [.firesOnRecordCreation]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.alertLocalizationKey = "REMOTE_MOVE_NOTIFICATION_BODY"
        notificationInfo.alertLocalizationArgs = [CloudKitRemoteMoveRecordCodec.Field.notificationSummary]
        subscription.notificationInfo = notificationInfo
        _ = try await database.saveSubscription(subscription)
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "moveSubscriptionSaved",
            fields: ["gameID": descriptor.id.rawValue, "subscriptionID": subscription.subscriptionID]
        )
    }

    func prepareGameStatusNotification(gameID: RemoteGameID) async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudKitRemoteGameStatusRecordCodec.recordType,
            predicate: NSPredicate(
                format: "%K == %@",
                CloudKitRemoteGameStatusRecordCodec.Field.gameID,
                gameID.rawValue
            ),
            subscriptionID: Self.statusSubscriptionID(for: gameID),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try await database.saveSubscription(subscription)
        await diagnosticsLog.append(
            category: "cloudKitGame",
            "statusSubscriptionSaved",
            fields: ["gameID": gameID.rawValue, "subscriptionID": subscription.subscriptionID]
        )
    }

    static func moveSubscriptionID(for gameID: RemoteGameID) -> String {
        "\(moveSubscriptionIDPrefix)\(gameID.rawValue)"
    }

    static func gameID(fromMoveSubscriptionID subscriptionID: String) -> RemoteGameID? {
        guard subscriptionID.hasPrefix(moveSubscriptionIDPrefix) else {
            return nil
        }
        let rawValue = String(subscriptionID.dropFirst(moveSubscriptionIDPrefix.count))
        guard !rawValue.isEmpty else {
            return nil
        }
        return RemoteGameID(rawValue: rawValue)
    }

    static func statusSubscriptionID(for gameID: RemoteGameID) -> String {
        "\(statusSubscriptionIDPrefix)\(gameID.rawValue)"
    }

    static func gameID(fromStatusSubscriptionID subscriptionID: String) -> RemoteGameID? {
        guard subscriptionID.hasPrefix(statusSubscriptionIDPrefix) else {
            return nil
        }
        let rawValue = String(subscriptionID.dropFirst(statusSubscriptionIDPrefix.count))
        guard !rawValue.isEmpty else {
            return nil
        }
        return RemoteGameID(rawValue: rawValue)
    }

    private func existingEvent(for recordID: CKRecord.ID) async throws -> RemoteMoveEvent {
        let results = try await database.records(for: [recordID], desiredKeys: nil)
        guard case .success(let record) = results[recordID] else {
            throw Error.missingSavedRecord
        }
        return try CloudKitRemoteMoveRecordCodec.event(from: record)
    }

    private func isMissingRecord(_ error: any Swift.Error) -> Bool {
        guard let cloudKitError = error as? CKError else {
            return false
        }
        return cloudKitError.code == .unknownItem
    }

    private func savedRecord(
        _ recordID: CKRecord.ID,
        in results: [CKRecord.ID: Result<CKRecord, any Swift.Error>]
    ) -> CKRecord? {
        guard case .success(let record) = results[recordID] else {
            return nil
        }
        return record
    }
}
