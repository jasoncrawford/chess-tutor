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

actor CloudKitRemoteGameTransport: RemoteGameTransport, RemoteGameMoveNotificationPreparing {
    enum Error: Swift.Error, Equatable {
        case conflictingSequence(Int)
        case missingSavedRecord
        case fetchFailed
    }

    private let database: any CloudKitGameDatabase
    private let fetchBatchSize: Int
    static let moveSubscriptionIDPrefix = "remote-game-moves-"

    init(
        database: any CloudKitGameDatabase = CKContainer(identifier: "iCloud.org.jasoncrawford.chesstutor").publicCloudDatabase,
        fetchBatchSize: Int = 20
    ) {
        self.database = database
        self.fetchBatchSize = fetchBatchSize
    }

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        let record = CloudKitRemoteMoveRecordCodec.record(from: event)
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )

        if savedRecord(record.recordID, in: result.saveResults) != nil {
            return RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber)
        }

        let existingEvent = try await existingEvent(for: record.recordID)
        guard existingEvent == event else {
            throw Error.conflictingSequence(event.sequenceNumber)
        }
        return RemoteMoveAck(
            eventID: existingEvent.id,
            gameID: existingEvent.gameID,
            sequenceNumber: existingEvent.sequenceNumber
        )
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        var events: [RemoteMoveEvent] = []
        var nextSequence = sequenceNumber + 1

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
                        throw Error.fetchFailed
                    }
                    return events
                }
            }
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
        subscription.notificationInfo = notificationInfo
        _ = try await database.saveSubscription(subscription)
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
