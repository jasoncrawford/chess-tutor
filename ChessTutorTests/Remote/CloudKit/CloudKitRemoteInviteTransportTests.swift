import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitRemoteInviteTransportTests: XCTestCase {
    func testCreateInviteSavesRecordByCodeAndFetchesItBack() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: Self.joiner.id,
                inviteeDisplayName: "Maya",
                whiteAssignment: .invitee,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
        let fetched = try await transport.fetchInvite(
            code: Self.code,
            token: nil,
            now: Self.joinedAt
        )

        XCTAssertEqual(invite, fetched)
        XCTAssertEqual(fetched.inviteePlayerID, Self.joiner.id)
        let savedRecord = await database.record(withID: Self.recordID)
        let record = try XCTUnwrap(savedRecord)
        XCTAssertEqual(
            record[CloudKitPendingInviteRecordCodec.notificationBodyFieldName] as? String,
            "Jason wants to play."
        )
        let lastRequest = await database.lastModifyRequest()
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.savePolicy, .ifServerRecordUnchanged)
        XCTAssertTrue(request.atomically)
    }

    func testAddressedInviteCanBeFetchedByInviteePlayerID() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: Self.joiner.id,
                inviteeDisplayName: Self.joiner.displayName,
                whiteAssignment: .invitee,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )

        let fetched = try await transport.fetchPendingInvite(for: Self.joiner.id, now: Self.joinedAt)

        XCTAssertEqual(fetched, invite)
    }

    func testCreateInviteCanStoreCustomNotificationBody() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)

        _ = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: Self.joiner.id,
                inviteeDisplayName: Self.joiner.displayName,
                whiteAssignment: .invitee,
                notificationBody: "Jason wants to start a new game.",
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )

        let savedRecord = await database.record(withID: Self.recordID)
        let record = try XCTUnwrap(savedRecord)
        XCTAssertEqual(
            record[CloudKitPendingInviteRecordCodec.notificationBodyFieldName] as? String,
            "Jason wants to start a new game."
        )
    }

    func testUnaddressedInviteIsNotFetchedByInviteePlayerID() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        _ = try await createInvite(on: transport, whiteAssignment: .invitee)

        let fetched = try await transport.fetchPendingInvite(for: Self.joiner.id, now: Self.joinedAt)

        XCTAssertNil(fetched)
    }

    func testCreateInviteRecordLevelSaveFailureMapsToCodeCollision() async {
        let database = InMemoryCloudKitInviteDatabase()
        await database.failSaves(for: [Self.recordID])
        let transport = makeTransport(database: database)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.codeCollision,
            try await transport.createInvite(
                CreateRemoteInviteRequest(
                    inviter: Self.inviter,
                    inviteeDisplayName: nil,
                    whiteAssignment: .invitee,
                    now: Self.createdAt,
                    expiresAt: Self.expiresAt
                )
            )
        )
    }

    func testFetchInviteTokenMismatchMapsToTokenMismatch() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        _ = try await createInvite(on: transport, whiteAssignment: .inviter)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.tokenMismatch,
            try await transport.fetchInvite(
                code: Self.code,
                token: RemoteInviteToken(rawValue: "wrong-token"),
                now: Self.joinedAt
            )
        )
    }

    func testFetchInviteExpiredMapsToExpired() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        _ = try await createInvite(on: transport, whiteAssignment: .inviter)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.expired,
            try await transport.fetchInvite(
                code: Self.code,
                token: Self.token,
                now: Self.expiresAt
            )
        )
    }

    func testFetchAcceptedInviteMapsToNotPending() async {
        let database = InMemoryCloudKitInviteDatabase()
        await database.store(makeInvite(status: .accepted))
        let transport = makeTransport(database: database)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.fetchInvite(
                code: Self.code,
                token: Self.token,
                now: Self.joinedAt
            )
        )
    }

    func testAcceptInviteeChoosesChosenWhiteWritesPendingInviteAndResponseRecordConditionally() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let accepted = try await transport.acceptInvite(request, chosenColor: .white)

        XCTAssertEqual(accepted.joinerColor, .white)
        XCTAssertEqual(accepted.invite.status, .accepted)
        let storedRecord = await database.record(withID: Self.recordID)
        let savedRecord = try XCTUnwrap(storedRecord)
        let savedInvite = try CloudKitPendingInviteRecordCodec.invite(from: savedRecord)
        XCTAssertEqual(savedInvite.status, .accepted)
        let acceptedFromPendingRecord = try CloudKitPendingInviteRecordCodec.acceptedInvite(from: savedRecord)
        XCTAssertEqual(acceptedFromPendingRecord, accepted)
        let acceptanceRecord = await database.record(withID: Self.acceptanceRecordID)
        XCTAssertNotNil(acceptanceRecord)
        let requests = await database.modifyRequests()
        let acceptRequests = Array(requests.suffix(2))
        XCTAssertEqual(acceptRequests.map(\.savedRecordIDs), [[Self.recordID], [Self.acceptanceRecordID]])
        XCTAssertEqual(acceptRequests.map(\.savePolicy), [.ifServerRecordUnchanged, .ifServerRecordUnchanged])
        XCTAssertEqual(acceptRequests.map(\.atomically), [true, true])
    }

    func testAcceptSucceedsWhenResponseRecordCannotBeSavedAfterPendingInviteIsAccepted() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        await database.failSaves(for: [Self.acceptanceRecordID])

        let accepted = try await transport.acceptInvite(
            JoinRemoteInviteRequest(
                code: invite.code,
                token: invite.token,
                joiner: Self.joiner,
                now: Self.joinedAt
            ),
            chosenColor: .black
        )

        XCTAssertEqual(accepted.joinerColor, .black)
        let storedRecord = await database.record(withID: Self.recordID)
        let savedRecord = try XCTUnwrap(storedRecord)
        XCTAssertEqual(try CloudKitPendingInviteRecordCodec.acceptedInvite(from: savedRecord), accepted)
        let acceptanceRecord = await database.record(withID: Self.acceptanceRecordID)
        XCTAssertNil(acceptanceRecord)
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertEqual(fetchedAcceptance, accepted)
    }

    func testAcceptSucceedsWhenPendingInviteCannotBeUpdatedButResponseRecordIsSaved() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        await database.failSaves(for: [Self.recordID])

        let accepted = try await transport.acceptInvite(
            JoinRemoteInviteRequest(
                code: invite.code,
                token: invite.token,
                joiner: Self.joiner,
                now: Self.joinedAt
            ),
            chosenColor: .white
        )

        XCTAssertEqual(accepted.joinerColor, .white)
        let storedRecord = await database.record(withID: Self.recordID)
        let savedRecord = try XCTUnwrap(storedRecord)
        let savedInvite = try CloudKitPendingInviteRecordCodec.invite(from: savedRecord)
        XCTAssertEqual(savedInvite.status, .pending)
        let acceptanceRecord = await database.record(withID: Self.acceptanceRecordID)
        XCTAssertNotNil(acceptanceRecord)
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertEqual(fetchedAcceptance, accepted)
    }

    func testAcceptFixedWhiteAssignmentAllowsOmittedOrMatchingChosenColor() async throws {
        let noChoiceDatabase = InMemoryCloudKitInviteDatabase()
        let noChoiceTransport = makeTransport(database: noChoiceDatabase)
        let noChoiceInvite = try await createInvite(on: noChoiceTransport, whiteAssignment: .inviter)
        let noChoiceRequest = JoinRemoteInviteRequest(
            code: noChoiceInvite.code,
            token: noChoiceInvite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let acceptedWithoutChoice = try await noChoiceTransport.acceptInvite(noChoiceRequest, chosenColor: nil)

        XCTAssertEqual(acceptedWithoutChoice.joinerColor, .black)

        let matchingChoiceDatabase = InMemoryCloudKitInviteDatabase()
        let matchingChoiceTransport = makeTransport(database: matchingChoiceDatabase)
        let matchingChoiceInvite = try await createInvite(on: matchingChoiceTransport, whiteAssignment: .invitee)
        let matchingChoiceRequest = JoinRemoteInviteRequest(
            code: matchingChoiceInvite.code,
            token: matchingChoiceInvite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let acceptedWithMatchingChoice = try await matchingChoiceTransport.acceptInvite(
            matchingChoiceRequest,
            chosenColor: .white
        )

        XCTAssertEqual(acceptedWithMatchingChoice.joinerColor, .white)
    }

    func testAcceptedInviteCanBeFetchedAfterJoinerAccepts() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let request = JoinRemoteInviteRequest(
            code: invite.code,
            token: invite.token,
            joiner: Self.joiner,
            now: Self.joinedAt
        )

        let beforeAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertNil(beforeAcceptance)
        let accepted = try await transport.acceptInvite(request, chosenColor: .black)
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)

        XCTAssertEqual(fetchedAcceptance, accepted)
    }

    func testFetchInviteAfterSeparateAcceptanceMapsToNotPending() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)

        _ = try await transport.acceptInvite(
            JoinRemoteInviteRequest(
                code: invite.code,
                token: invite.token,
                joiner: Self.joiner,
                now: Self.joinedAt
            ),
            chosenColor: .black
        )

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.fetchInvite(code: invite.code, token: invite.token, now: Self.joinedAt)
        )
    }

    func testCancelReportsInviterLeftOnSubsequentFetch() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviter)

        try await transport.cancelInvite(id: invite.id)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.cancelled(inviterDisplayName: Self.inviter.displayName),
            try await transport.fetchInvite(code: invite.code, token: invite.token, now: Self.joinedAt)
        )
    }

    func testDeclinePreventsInviteePromptAndReportsDeclineToInviter() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: Self.joiner.id,
                inviteeDisplayName: Self.joiner.displayName,
                whiteAssignment: .invitee,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )

        try await transport.declineInvite(id: invite.id)

        let pendingInvite = try await transport.fetchPendingInvite(for: Self.joiner.id, now: Self.joinedAt)
        XCTAssertNil(pendingInvite)
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.declined(inviteeDisplayName: Self.joiner.displayName),
            try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        )
    }

    func testDeclineFallsBackToResponseRecordWhenPendingInviteCannotBeUpdated() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: Self.joiner.id,
                inviteeDisplayName: Self.joiner.displayName,
                whiteAssignment: .invitee,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
        await database.failSaves(for: [Self.recordID])

        try await transport.declineInvite(id: invite.id)

        let storedPendingRecord = await database.record(withID: Self.recordID)
        let pendingRecord = try XCTUnwrap(storedPendingRecord)
        let pendingInvite = try CloudKitPendingInviteRecordCodec.invite(from: pendingRecord)
        XCTAssertEqual(pendingInvite.status, .pending)
        let storedResponseRecord = await database.record(withID: Self.acceptanceRecordID)
        let responseRecord = try XCTUnwrap(storedResponseRecord)
        XCTAssertEqual(try CloudKitInviteAcceptanceRecordCodec.responseStatus(from: responseRecord), .declined)
        XCTAssertEqual(
            CloudKitInviteAcceptanceRecordCodec.declinedInviteeDisplayName(from: responseRecord),
            Self.joiner.displayName
        )
        let pendingInviteForJoiner = try await transport.fetchPendingInvite(for: Self.joiner.id, now: Self.joinedAt)
        XCTAssertNil(pendingInviteForJoiner)
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.declined(inviteeDisplayName: Self.joiner.displayName),
            try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        )
    }

    func testAcceptAfterInviteWasCancelledDuringRaceReportsCancellation() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .invitee)
        await database.applyServerInviteStatusBeforeNextSave(id: invite.id, status: .cancelled)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.cancelled(inviterDisplayName: Self.inviter.displayName),
            try await transport.acceptInvite(
                JoinRemoteInviteRequest(
                    code: invite.code,
                    token: invite.token,
                    joiner: Self.joiner,
                    now: Self.joinedAt
                ),
                chosenColor: .white
            )
        )
        let acceptanceRecord = await database.record(withID: Self.acceptanceRecordID)
        XCTAssertNil(acceptanceRecord)
    }

    func testCancelAfterInviteWasAcceptedDuringRaceDoesNotOverwriteAcceptance() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .invitee)
        let acceptedInvite = RemoteAcceptedInvite(
            invite: RemotePendingInvite(
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
            ),
            joiner: Self.joiner,
            joinerColor: .white
        )
        await database.applyServerAcceptedInviteBeforeNextSave(acceptedInvite)

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.cancelInvite(id: invite.id)
        )
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertEqual(fetchedAcceptance, acceptedInvite)
    }

    func testSecondAcceptanceMapsToNotPendingWithoutOverwritingFirstAcceptance() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        let firstAccepted = try await transport.acceptInvite(
            JoinRemoteInviteRequest(
                code: invite.code,
                token: invite.token,
                joiner: Self.joiner,
                now: Self.joinedAt
            ),
            chosenColor: .black
        )

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.acceptInvite(
                JoinRemoteInviteRequest(
                    code: invite.code,
                    token: invite.token,
                    joiner: RemotePlayerRef(id: RemotePlayerID(rawValue: "other"), displayName: "Other"),
                    now: Self.joinedAt.addingTimeInterval(1)
                ),
                chosenColor: .white
            )
        )
        let fetchedAcceptance = try await transport.acceptedInvite(id: invite.id, now: Self.joinedAt)
        XCTAssertEqual(fetchedAcceptance, firstAccepted)
    }

    func testPreparingAcceptanceNotificationSavesQuerySubscriptionForInviteCode() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .invitee)

        try await transport.prepareAcceptanceNotification(for: invite)

        let storedAcceptanceSubscription = await database.subscription(withID: "pending-invite-accepted-428193")
        let acceptanceSubscription = try XCTUnwrap(storedAcceptanceSubscription as? CKQuerySubscription)
        XCTAssertEqual(acceptanceSubscription.recordType, CloudKitInviteAcceptanceRecordCodec.recordType)
        XCTAssertEqual(acceptanceSubscription.notificationInfo?.shouldSendContentAvailable, true)
        let storedStatusSubscription = await database.subscription(withID: "pending-invite-status-428193")
        let statusSubscription = try XCTUnwrap(storedStatusSubscription as? CKQuerySubscription)
        XCTAssertEqual(statusSubscription.recordType, CloudKitPendingInviteRecordCodec.recordType)
        XCTAssertEqual(statusSubscription.notificationInfo?.shouldSendContentAvailable, true)
    }

    func testPreparingAcceptanceNotificationDeletesStaleInviteResponseSubscriptionsBeforeSavingCurrentSubscriptions() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        await database.storeSubscription(subscription(id: "pending-invite-accepted-old"))
        await database.storeSubscription(subscription(id: "pending-invite-status-old"))
        await database.storeSubscription(subscription(id: "pending-invite-for-maya"))
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .invitee)

        try await transport.prepareAcceptanceNotification(for: invite)

        let staleAcceptanceSubscription = await database.subscription(withID: "pending-invite-accepted-old")
        let staleStatusSubscription = await database.subscription(withID: "pending-invite-status-old")
        let incomingInviteSubscription = await database.subscription(withID: "pending-invite-for-maya")
        let currentAcceptanceSubscription = await database.subscription(withID: "pending-invite-accepted-428193")
        let currentStatusSubscription = await database.subscription(withID: "pending-invite-status-428193")
        XCTAssertNil(staleAcceptanceSubscription)
        XCTAssertNil(staleStatusSubscription)
        XCTAssertNotNil(incomingInviteSubscription)
        XCTAssertNotNil(currentAcceptanceSubscription)
        XCTAssertNotNil(currentStatusSubscription)
    }

    func testPreparingIncomingInviteNotificationSavesAddressedInviteSubscription() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)

        try await transport.prepareIncomingInviteNotification(for: Self.joiner.id)

        let storedSubscription = await database.subscription(withID: "pending-invite-for-maya")
        let subscription = try XCTUnwrap(storedSubscription)
        XCTAssertEqual(subscription.subscriptionID, "pending-invite-for-maya")
        let querySubscription = try XCTUnwrap(subscription as? CKQuerySubscription)
        XCTAssertEqual(querySubscription.recordType, CloudKitPendingInviteRecordCodec.recordType)
        XCTAssertEqual(querySubscription.notificationInfo?.shouldSendContentAvailable, true)
        XCTAssertEqual(querySubscription.notificationInfo?.alertLocalizationKey, "REMOTE_INVITE_NOTIFICATION_BODY")
        XCTAssertEqual(querySubscription.notificationInfo?.alertLocalizationArgs, ["notificationBody"])
    }

    func testAcceptanceSubscriptionIDParsesInviteIDForPushNotificationRouting() {
        XCTAssertEqual(
            CloudKitRemoteInviteTransport.inviteID(
                fromAcceptanceSubscriptionID: "pending-invite-accepted-428193"
            ),
            RemoteInviteID(rawValue: "428193")
        )
        XCTAssertNil(
            CloudKitRemoteInviteTransport.inviteID(fromAcceptanceSubscriptionID: "remote-game-moves-game-1")
        )
    }

    func testInviteStatusSubscriptionIDParsesInviteIDForPushNotificationRouting() {
        XCTAssertEqual(
            CloudKitRemoteInviteTransport.inviteID(
                fromStatusSubscriptionID: "pending-invite-status-428193"
            ),
            RemoteInviteID(rawValue: "428193")
        )
        XCTAssertNil(
            CloudKitRemoteInviteTransport.inviteID(fromStatusSubscriptionID: "remote-game-moves-game-1")
        )
    }

    func testIncomingInviteSubscriptionIDParsesPlayerIDForPushNotificationRouting() {
        XCTAssertEqual(
            CloudKitRemoteInviteTransport.playerID(
                fromIncomingInviteSubscriptionID: "pending-invite-for-maya"
            ),
            RemotePlayerID(rawValue: "maya")
        )
        XCTAssertNil(
            CloudKitRemoteInviteTransport.playerID(fromIncomingInviteSubscriptionID: "pending-invite-accepted-428193")
        )
    }

    func testAcceptFailsWhenNeitherPendingInviteNorResponseRecordCanBeSaved() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = makeTransport(database: database)
        let invite = try await createInvite(on: transport, whiteAssignment: .inviteeChooses)
        await database.failSaves(for: [Self.recordID, Self.acceptanceRecordID])

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notPending,
            try await transport.acceptInvite(
                JoinRemoteInviteRequest(
                    code: invite.code,
                    token: invite.token,
                    joiner: Self.joiner,
                    now: Self.joinedAt
                ),
                chosenColor: .white
            )
        )
    }

    func testCancelInviteSaveFailureOrMissingIDMapsToNotFound() async throws {
        let failingSaveDatabase = InMemoryCloudKitInviteDatabase()
        let failingSaveTransport = makeTransport(database: failingSaveDatabase)
        let invite = try await createInvite(on: failingSaveTransport, whiteAssignment: .inviter)
        await failingSaveDatabase.failSaves(for: [Self.recordID])

        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notFound,
            try await failingSaveTransport.cancelInvite(id: invite.id)
        )

        let missingSaveDatabase = InMemoryCloudKitInviteDatabase()
        let missingSaveTransport = makeTransport(database: missingSaveDatabase)
        await XCTAssertThrowsRemoteInviteTransportErrorAsync(.notFound,
            try await missingSaveTransport.cancelInvite(id: RemoteInviteID(rawValue: "missing"))
        )
    }

    private static let code = InviteCode(rawValue: "428193")
    private static let recordID = CKRecord.ID(recordName: code.rawValue)
    private static let acceptanceRecordID = CloudKitInviteAcceptanceRecordCodec.recordID(
        for: RemoteInviteID(rawValue: code.rawValue)
    )
    private static let token = RemoteInviteToken(rawValue: "token-1")
    private static let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")
    private static let joiner = RemotePlayerRef(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
    private static let createdAt = Date(timeIntervalSince1970: 10)
    private static let joinedAt = Date(timeIntervalSince1970: 20)
    private static let expiresAt = Date(timeIntervalSince1970: 70)

    private func makeTransport(database: InMemoryCloudKitInviteDatabase) -> CloudKitRemoteInviteTransport {
        CloudKitRemoteInviteTransport(
            database: database,
            codeGenerator: { Self.code },
            tokenGenerator: { Self.token }
        )
    }

    private func createInvite(
        on transport: CloudKitRemoteInviteTransport,
        whiteAssignment: RemoteInviteWhiteAssignment
    ) async throws -> RemotePendingInvite {
        try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: Self.inviter,
                inviteePlayerID: nil,
                inviteeDisplayName: nil,
                whiteAssignment: whiteAssignment,
                now: Self.createdAt,
                expiresAt: Self.expiresAt
            )
        )
    }

    private func makeInvite(
        whiteAssignment: RemoteInviteWhiteAssignment = .inviteeChooses,
        status: RemoteInviteStatus = .pending
    ) -> RemotePendingInvite {
        RemotePendingInvite(
            id: RemoteInviteID(rawValue: Self.code.rawValue),
            code: Self.code,
            token: Self.token,
            inviter: Self.inviter,
            inviteeDisplayName: nil,
            whiteAssignment: whiteAssignment,
            status: status,
            createdAt: Self.createdAt,
            expiresAt: Self.expiresAt,
            protocolVersion: 1
        )
    }

    private func subscription(id: String) -> CKSubscription {
        CKQuerySubscription(
            recordType: "TestRecord",
            predicate: NSPredicate(value: true),
            subscriptionID: id,
            options: [.firesOnRecordCreation]
        )
    }
}

private struct ModifyRecordsRequest: Equatable {
    let savedRecordIDs: [CKRecord.ID]
    let deletedRecordIDs: [CKRecord.ID]
    let savePolicy: CKModifyRecordsOperation.RecordSavePolicy
    let atomically: Bool
}

private actor InMemoryCloudKitInviteDatabase: CloudKitInviteDatabase {
    private var records: [CKRecord.ID: CKRecord] = [:]
    private var subscriptions: [String: CKSubscription] = [:]
    private var failingSaveIDs: Set<CKRecord.ID> = []
    private var failingDeleteIDs: Set<CKRecord.ID> = []
    private var fetchedRecordIDs: Set<CKRecord.ID> = []
    private var recordsToApplyBeforeNextSave: [CKRecord.ID: CKRecord] = [:]
    private var requests: [ModifyRecordsRequest] = []

    func record(withID id: CKRecord.ID) -> CKRecord? {
        records[id].map(clone)
    }

    func subscription(withID id: String) -> CKSubscription? {
        subscriptions[id]
    }

    func storeSubscription(_ subscription: CKSubscription) {
        subscriptions[subscription.subscriptionID] = subscription
    }

    func store(_ invite: RemotePendingInvite) {
        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        records[record.recordID] = record
    }

    func applyServerInviteStatusBeforeNextSave(id: RemoteInviteID, status: RemoteInviteStatus) {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        guard let record = records[recordID] else {
            return
        }
        let updatedRecord = clone(record)
        updatedRecord["status"] = status.rawValue as CKRecordValue
        recordsToApplyBeforeNextSave[recordID] = updatedRecord
    }

    func applyServerAcceptedInviteBeforeNextSave(_ acceptedInvite: RemoteAcceptedInvite) {
        let pendingRecord = CloudKitPendingInviteRecordCodec.record(from: acceptedInvite.invite)
        CloudKitPendingInviteRecordCodec.apply(acceptedInvite, to: pendingRecord)
        let acceptanceRecord = CloudKitInviteAcceptanceRecordCodec.record(
            from: acceptedInvite,
            acceptedAt: acceptedInvite.invite.createdAt
        )
        recordsToApplyBeforeNextSave[pendingRecord.recordID] = pendingRecord
        recordsToApplyBeforeNextSave[acceptanceRecord.recordID] = acceptanceRecord
    }

    func failSaves(for ids: [CKRecord.ID]) {
        failingSaveIDs.formUnion(ids)
    }

    func failDeletes(for ids: [CKRecord.ID]) {
        failingDeleteIDs.formUnion(ids)
    }

    func lastModifyRequest() -> ModifyRecordsRequest? {
        requests.last
    }

    func modifyRequests() -> [ModifyRecordsRequest] {
        requests
    }

    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        subscriptions[subscription.subscriptionID] = subscription
        return subscription
    }

    func allSubscriptions() async throws -> [CKSubscription] {
        Array(subscriptions.values)
    }

    func modifySubscriptions(
        saving subscriptionsToSave: [CKSubscription],
        deleting subscriptionIDsToDelete: [CKSubscription.ID]
    ) async throws -> (
        saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
        deleteResults: [CKSubscription.ID: Result<Void, any Error>]
    ) {
        var saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>] = [:]
        for subscription in subscriptionsToSave {
            subscriptions[subscription.subscriptionID] = subscription
            saveResults[subscription.subscriptionID] = .success(subscription)
        }

        var deleteResults: [CKSubscription.ID: Result<Void, any Error>] = [:]
        for subscriptionID in subscriptionIDsToDelete {
            subscriptions.removeValue(forKey: subscriptionID)
            deleteResults[subscriptionID] = .success(())
        }

        return (saveResults: saveResults, deleteResults: deleteResults)
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        var results: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        for id in ids {
            if let record = records[id] {
                fetchedRecordIDs.insert(id)
                results[id] = .success(clone(record))
            } else {
                results[id] = .failure(CKError(.unknownItem))
            }
        }
        return results
    }

    func records(
        matching query: CKQuery,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> [CKRecord] {
        Array(records.values)
            .filter { record in
                record.recordType == query.recordType
            }
            .sorted {
                let lhs = ($0["createdAt"] as? Date) ?? .distantPast
                let rhs = ($1["createdAt"] as? Date) ?? .distantPast
                return lhs > rhs
            }
            .prefix(resultsLimit)
            .map(clone)
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
            ModifyRecordsRequest(
                savedRecordIDs: recordsToSave.map(\.recordID),
                deletedRecordIDs: recordIDsToDelete,
                savePolicy: savePolicy,
                atomically: atomically
            )
        )

        let serverChangedIDs = Set(recordsToApplyBeforeNextSave.keys)
        for (id, record) in recordsToApplyBeforeNextSave {
            records[id] = clone(record)
            fetchedRecordIDs.remove(id)
        }
        recordsToApplyBeforeNextSave = [:]

        var saveResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]
        let saveFailuresByID = Dictionary(
            uniqueKeysWithValues: recordsToSave.compactMap { record -> (CKRecord.ID, any Error)? in
                if failingSaveIDs.contains(record.recordID) {
                    return (record.recordID, CKError(.serverRecordChanged))
                }
                if savePolicy == .ifServerRecordUnchanged,
                   records[record.recordID] != nil,
                   (!fetchedRecordIDs.contains(record.recordID) || serverChangedIDs.contains(record.recordID)) {
                    return (record.recordID, CKError(.serverRecordChanged))
                }
                return nil
            }
        )

        if atomically, !saveFailuresByID.isEmpty {
            for record in recordsToSave {
                saveResults[record.recordID] = .failure(
                    saveFailuresByID[record.recordID] ?? CKError(.batchRequestFailed)
                )
            }
        } else {
            for record in recordsToSave {
                if failingSaveIDs.contains(record.recordID) {
                    saveResults[record.recordID] = .failure(CKError(.serverRecordChanged))
                } else if savePolicy == .ifServerRecordUnchanged,
                          records[record.recordID] != nil,
                          (!fetchedRecordIDs.contains(record.recordID) || serverChangedIDs.contains(record.recordID)) {
                    saveResults[record.recordID] = .failure(CKError(.serverRecordChanged))
                } else {
                    records[record.recordID] = clone(record)
                    fetchedRecordIDs.remove(record.recordID)
                    saveResults[record.recordID] = .success(record)
                }
            }
        }

        var deleteResults: [CKRecord.ID: Result<Void, any Error>] = [:]
        for id in recordIDsToDelete {
            if failingDeleteIDs.contains(id) || records[id] == nil {
                deleteResults[id] = .failure(CKError(.unknownItem))
            } else {
                records.removeValue(forKey: id)
                deleteResults[id] = .success(())
            }
        }

        return (saveResults: saveResults, deleteResults: deleteResults)
    }

    private func clone(_ record: CKRecord) -> CKRecord {
        record.copy() as! CKRecord
    }
}

private func XCTAssertThrowsRemoteInviteTransportErrorAsync<T>(
    _ expectedError: RemoteInviteTransportError,
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch let error as RemoteInviteTransportError {
        XCTAssertEqual(error, expectedError, file: file, line: line)
    } catch {
        XCTFail("Expected \(expectedError), got \(error)", file: file, line: line)
    }
}
