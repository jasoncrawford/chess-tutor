import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitRemoteGameTransportTests: XCTestCase {
    func testSendMoveSavesRecordByGameAndSequenceAndFetchesItBack() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        let event = makeEvent(sequence: 1)

        let ack = try await transport.sendMove(event)
        let fetched = try await transport.fetchMoves(gameID: Self.gameID, after: 0)

        XCTAssertEqual(ack, RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: 1))
        XCTAssertEqual(fetched, [event])
        let savedRecord = await database.record(withID: Self.recordID(sequence: 1))
        XCTAssertNotNil(savedRecord)
        let lastRequest = await database.lastModifyRequest()
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.savedRecordIDs, [Self.recordID(sequence: 1)])
        XCTAssertEqual(request.savePolicy, .ifServerRecordUnchanged)
        XCTAssertTrue(request.atomically)
    }

    func testSendMoveIsIdempotentForMatchingExistingEvent() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        let event = makeEvent(sequence: 1)
        await database.store(event)
        await database.failSaves(for: [Self.recordID(sequence: 1)])

        let ack = try await transport.sendMove(event)

        XCTAssertEqual(ack, RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: 1))
    }

    func testFetchMovesStopsAtFirstMissingSequence() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        let first = makeEvent(sequence: 1)
        let third = makeEvent(sequence: 3)
        await database.store(first)
        await database.store(third)

        let fetched = try await transport.fetchMoves(gameID: Self.gameID, after: 0)

        XCTAssertEqual(fetched, [first])
    }

    func testFetchMovesThrowsWhenCloudKitFetchFails() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        await database.failFetches(for: [Self.recordID(sequence: 1)], with: CKError(.networkUnavailable))

        do {
            _ = try await transport.fetchMoves(gameID: Self.gameID, after: 0)
            XCTFail("Expected fetchMoves to throw for a CloudKit fetch failure")
        } catch let error as CloudKitRemoteGameTransport.Error {
            XCTAssertEqual(error, .fetchFailed)
        }
    }

    func testPrepareMoveNotificationSubscribesToOpponentMoveCreations() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        let descriptor = RemoteGameDescriptor(
            id: Self.gameID,
            protocolVersion: 1,
            status: .active,
            whitePlayer: RemotePlayerRef(id: Self.whiteID, displayName: "White"),
            blackPlayer: RemotePlayerRef(id: Self.blackID, displayName: "Black"),
            localPlayerID: Self.whiteID
        )

        try await transport.prepareMoveNotification(for: descriptor)

        let savedSubscription = await database.lastSubscription()
        let subscription = try XCTUnwrap(savedSubscription as? CKQuerySubscription)
        XCTAssertEqual(subscription.subscriptionID, "remote-game-moves-game-1")
        XCTAssertEqual(subscription.recordType, CloudKitRemoteMoveRecordCodec.recordType)
        XCTAssertEqual(subscription.notificationInfo?.shouldSendContentAvailable, true)
        XCTAssertEqual(subscription.notificationInfo?.alertLocalizationKey, "REMOTE_MOVE_NOTIFICATION_BODY")
        XCTAssertEqual(subscription.notificationInfo?.alertLocalizationArgs, ["notificationSummary"])
        XCTAssertEqual(
            CloudKitRemoteGameTransport.gameID(fromMoveSubscriptionID: subscription.subscriptionID),
            Self.gameID
        )
    }

    func testUpdateGameStatusSavesAndFetchesStatusRecord() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)
        let status = RemoteGameStatusUpdate(
            gameID: Self.gameID,
            status: .ended,
            updatedByPlayerID: Self.whiteID,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try await transport.updateGameStatus(status)

        let fetchedStatus = try await transport.fetchGameStatus(gameID: Self.gameID)
        XCTAssertEqual(fetchedStatus, status)
        let savedRequest = await database.lastModifyRequest()
        let lastRequest = try XCTUnwrap(savedRequest)
        XCTAssertEqual(lastRequest.savedRecordIDs, [CKRecord.ID(recordName: "game-status-game-1")])
    }

    func testPrepareGameStatusNotificationSubscribesToGameStatusChanges() async throws {
        let database = InMemoryCloudKitGameDatabase()
        let transport = CloudKitRemoteGameTransport(database: database)

        try await transport.prepareGameStatusNotification(gameID: Self.gameID)

        let savedSubscription = await database.lastSubscription()
        let subscription = try XCTUnwrap(savedSubscription as? CKQuerySubscription)
        XCTAssertEqual(subscription.subscriptionID, "remote-game-status-game-1")
        XCTAssertEqual(subscription.recordType, CloudKitRemoteGameStatusRecordCodec.recordType)
        XCTAssertEqual(subscription.notificationInfo?.shouldSendContentAvailable, true)
        XCTAssertEqual(
            CloudKitRemoteGameTransport.gameID(fromStatusSubscriptionID: subscription.subscriptionID),
            Self.gameID
        )
    }

    private static let gameID = RemoteGameID(rawValue: "game-1")
    private static let whiteID = RemotePlayerID(rawValue: "white")
    private static let blackID = RemotePlayerID(rawValue: "black")

    private static func recordID(sequence: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "game-1-\(sequence)")
    }

    private func makeEvent(sequence: Int) -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: Self.gameID,
            sequenceNumber: sequence,
            actorPlayerID: Self.whiteID,
            move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
            createdAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprint(rawValue: "before-\(sequence)"),
            resultingPositionFingerprint: PositionFingerprint(rawValue: "after-\(sequence)"),
            notificationSummary: "White pawn to e4"
        )
    }
}

private struct ModifyGameRecordsRequest: Equatable {
    let savedRecordIDs: [CKRecord.ID]
    let savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    let atomically: Bool
}

private actor InMemoryCloudKitGameDatabase: CloudKitGameDatabase {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var failingSaveIDs: Set<CKRecord.ID> = []
    private var fetchFailures: [CKRecord.ID: any Error] = [:]
    private var requests: [ModifyGameRecordsRequest] = []
    private var subscriptions: [CKSubscription] = []

    func record(withID id: CKRecord.ID) -> CKRecord? {
        records[id]
    }

    func store(_ event: RemoteMoveEvent) {
        let record = CloudKitRemoteMoveRecordCodec.record(from: event)
        records[record.recordID] = record
    }

    func failSaves(for ids: [CKRecord.ID]) {
        failingSaveIDs.formUnion(ids)
    }

    func failFetches(for ids: [CKRecord.ID], with error: any Error) {
        for id in ids {
            fetchFailures[id] = error
        }
    }

    func lastModifyRequest() -> ModifyGameRecordsRequest? {
        requests.last
    }

    func lastSubscription() -> CKSubscription? {
        subscriptions.last
    }

    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        subscriptions.append(subscription)
        return subscription
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        for id in ids {
            if let error = fetchFailures[id] {
                results[id] = .failure(error)
            } else if let record = records[id] {
                results[id] = .success(record)
            } else {
                results[id] = .failure(CKError(.unknownItem))
            }
        }
        return results
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>]
    ) {
        requests.append(
            ModifyGameRecordsRequest(
                savedRecordIDs: recordsToSave.map(\.recordID),
                savePolicy: savePolicy,
                atomically: atomically
            )
        )

        var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        for record in recordsToSave {
            if failingSaveIDs.contains(record.recordID) {
                saveResults[record.recordID] = .failure(CKError(.serverRecordChanged))
            } else {
                records[record.recordID] = record
                saveResults[record.recordID] = .success(record)
            }
        }

        return (saveResults: saveResults, deleteResults: [:])
    }
}
