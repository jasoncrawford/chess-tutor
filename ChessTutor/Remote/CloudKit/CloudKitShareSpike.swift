#if DEBUG
import CloudKit
import Foundation
import Observation
import SwiftUI
import UIKit

enum CloudKitShareSpikeLaunchConfiguration {
    static let argument = "--cloudkit-share-spike"
    static let useCloudKitArgument = "--cloudkit-share-spike-use-cloudkit"

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }
}

struct CloudKitShareSpikeRecordPointer: Codable, Equatable, Sendable {
    let recordName: String
    let zoneName: String
    let ownerName: String

    init(recordID: CKRecord.ID) {
        self.recordName = recordID.recordName
        self.zoneName = recordID.zoneID.zoneName
        self.ownerName = recordID.zoneID.ownerName
    }

    var recordID: CKRecord.ID {
        CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        )
    }
}

struct CloudKitShareSpikeCapabilities: Equatable, Sendable {
    let isCloudKitEnabled: Bool

    var canUseCloudKit: Bool {
        isCloudKitEnabled
    }

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> CloudKitShareSpikeCapabilities {
        return CloudKitShareSpikeCapabilities(
            isCloudKitEnabled: arguments.contains(CloudKitShareSpikeLaunchConfiguration.useCloudKitArgument)
        )
    }
}

@MainActor
@Observable
final class CloudKitShareSpikeModel {
    var shareURLText = ""
    var acceptedShareURLText = ""
    var moveNote = "hello from \(UIDevice.current.name)"
    var ownerRootPointer: CloudKitShareSpikeRecordPointer?
    var acceptedRootPointer: CloudKitShareSpikeRecordPointer?
    var logLines: [String] = []
    let setupMessage: String?

    private let capabilities: CloudKitShareSpikeCapabilities
    private let makeClient: () -> CloudKitShareSpikeClient
    private let acceptedStore = CloudKitShareSpikeAcceptedShareStore()
    private var client: CloudKitShareSpikeClient?

    var canUseCloudKit: Bool {
        capabilities.canUseCloudKit
    }

    init(
        capabilities: CloudKitShareSpikeCapabilities = .current(),
        makeClient: @escaping () -> CloudKitShareSpikeClient = { CloudKitShareSpikeClient() }
    ) {
        self.capabilities = capabilities
        self.makeClient = makeClient
        self.setupMessage = capabilities.canUseCloudKit
            ? nil
            : "CloudKit is not enabled for this launch. Add iCloud container entitlements, then launch with --cloudkit-share-spike-use-cloudkit."
        acceptedRootPointer = acceptedStore.load()
    }

    func checkAccount() {
        run("Checking iCloud account") {
            try await self.requireClient().accountStatusDescription()
        }
    }

    func createSharedGame() {
        run("Creating shared game") {
            let result = try await self.requireClient().createSharedGame()
            self.ownerRootPointer = result.rootPointer
            self.shareURLText = result.shareURL?.absoluteString ?? ""
            return """
            Created game root \(result.rootPointer.recordName)
            Share URL: \(self.shareURLText.isEmpty ? "(none returned)" : self.shareURLText)
            """
        }
    }

    func acceptShareURL() {
        run("Accepting share URL") {
            let client = try self.requireClient()
            guard let url = URL(string: self.acceptedShareURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw CloudKitShareSpikeError.missingShareURL
            }

            let pointer = try await client.acceptShare(url: url)
            self.acceptedRootPointer = pointer
            self.acceptedStore.save(pointer)
            return "Accepted shared root \(pointer.recordName)"
        }
    }

    func refreshAcceptedShareFromDelegate() {
        acceptedRootPointer = acceptedStore.load()
        if let acceptedRootPointer {
            append("Loaded accepted share root \(acceptedRootPointer.recordName)")
        } else {
            append("No accepted share root stored yet")
        }
    }

    func writeOwnerMove() {
        guard let ownerRootPointer else {
            append("Create a shared game first.")
            return
        }

        writeMove(label: "Writing owner move", databaseScope: .private, rootPointer: ownerRootPointer)
    }

    func writeAcceptedMove() {
        guard let acceptedRootPointer else {
            append("Accept a share first.")
            return
        }

        writeMove(label: "Writing accepted participant move", databaseScope: .shared, rootPointer: acceptedRootPointer)
    }

    func fetchOwnerMoves() {
        guard let ownerRootPointer else {
            append("Create a shared game first.")
            return
        }

        fetchMoves(label: "Fetching owner moves", databaseScope: .private, rootPointer: ownerRootPointer)
    }

    func fetchAcceptedMoves() {
        guard let acceptedRootPointer else {
            append("Accept a share first.")
            return
        }

        fetchMoves(label: "Fetching accepted participant moves", databaseScope: .shared, rootPointer: acceptedRootPointer)
    }

    func clearLog() {
        logLines = []
    }

    private func writeMove(
        label: String,
        databaseScope: CloudKitShareSpikeDatabaseScope,
        rootPointer: CloudKitShareSpikeRecordPointer
    ) {
        run(label) {
            let saved = try await self.requireClient().writeMove(
                note: self.moveNote,
                rootPointer: rootPointer,
                databaseScope: databaseScope
            )
            return "Saved \(saved.recordName) in \(databaseScope.rawValue)"
        }
    }

    private func fetchMoves(
        label: String,
        databaseScope: CloudKitShareSpikeDatabaseScope,
        rootPointer: CloudKitShareSpikeRecordPointer
    ) {
        run(label) {
            let moves = try await self.requireClient().fetchMoves(
                rootPointer: rootPointer,
                databaseScope: databaseScope
            )
            guard !moves.isEmpty else {
                return "No moves found in \(databaseScope.rawValue)."
            }

            return moves
                .map { "\($0.recordName): \($0.note)" }
                .joined(separator: "\n")
        }
    }

    private func run(_ label: String, operation: @escaping () async throws -> String) {
        append("> \(label)")
        Task {
            do {
                append(try await operation())
            } catch {
                append("Error: \(error.localizedDescription)")
            }
        }
    }

    private func requireClient() throws -> CloudKitShareSpikeClient {
        guard capabilities.canUseCloudKit else {
            throw CloudKitShareSpikeError.cloudKitDisabledForLaunch
        }

        if let client {
            return client
        }

        let newClient = makeClient()
        client = newClient
        return newClient
    }

    private func append(_ line: String) {
        logLines.append(line)
    }
}

struct CloudKitShareSpikeView: View {
    @State private var model = CloudKitShareSpikeModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    Button("Check iCloud Account") {
                        model.checkAccount()
                    }
                    Text("Launch with \(CloudKitShareSpikeLaunchConfiguration.argument). Requires a real iCloud-enabled app container and CloudKit entitlement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let setupMessage = model.setupMessage {
                        Text(setupMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Owner") {
                    Button("Create Shared Game") {
                        model.createSharedGame()
                    }

                    if !model.shareURLText.isEmpty {
                        Text(model.shareURLText)
                            .font(.footnote)
                            .textSelection(.enabled)
                        if let url = URL(string: model.shareURLText) {
                            ShareLink(item: url)
                        }
                    }

                    Button("Write Owner Move") {
                        model.writeOwnerMove()
                    }
                    Button("Fetch Owner Moves") {
                        model.fetchOwnerMoves()
                    }
                }

                Section("Participant") {
                    TextField("Share URL", text: $model.acceptedShareURLText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Accept Share URL") {
                        model.acceptShareURL()
                    }
                    Button("Refresh Share Accepted By App Delegate") {
                        model.refreshAcceptedShareFromDelegate()
                    }
                    Button("Write Accepted Move") {
                        model.writeAcceptedMove()
                    }
                    Button("Fetch Accepted Moves") {
                        model.fetchAcceptedMoves()
                    }
                }

                Section("Move Note") {
                    TextField("Move note", text: $model.moveNote, axis: .vertical)
                }

                Section("Log") {
                    Button("Clear Log") {
                        model.clearLog()
                    }

                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("CKShare Spike")
            .disabled(!model.canUseCloudKit)
        }
    }
}

final class CloudKitShareSpikeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        guard CloudKitShareSpikeLaunchConfiguration.isEnabled(arguments: ProcessInfo.processInfo.arguments) else {
            return
        }
        guard CloudKitShareSpikeCapabilities.current().canUseCloudKit else {
            return
        }

        Task {
            do {
                let pointer = try await CloudKitShareSpikeClient().accept(metadata: cloudKitShareMetadata)
                await MainActor.run {
                    CloudKitShareSpikeAcceptedShareStore().save(pointer)
                }
            } catch {
                // The spike view can still accept URLs manually; this path is only for OS share callbacks.
            }
        }
    }
}

enum CloudKitShareSpikeDatabaseScope: String {
    case `private`
    case shared
}

struct CloudKitShareSpikeMove: Equatable {
    let recordName: String
    let note: String
}

enum CloudKitShareSpikeError: LocalizedError {
    case cloudKitDisabledForLaunch
    case missingShareURL
    case missingShareMetadata(URL)
    case missingAcceptedShare
    case missingAcceptedRootRecord
    case missingSavedRecord(CKRecord.ID)

    var errorDescription: String? {
        switch self {
        case .cloudKitDisabledForLaunch:
            return "CloudKit is not enabled for this launch."
        case .missingShareURL:
            return "Enter a share URL first."
        case .missingShareMetadata(let url):
            return "No share metadata returned for \(url.absoluteString)."
        case .missingAcceptedShare:
            return "No accepted share was returned."
        case .missingAcceptedRootRecord:
            return "The accepted share did not include a root game record."
        case .missingSavedRecord(let recordID):
            return "CloudKit did not return saved record \(recordID.recordName)."
        }
    }
}

struct CloudKitShareSpikeCreationResult {
    let rootPointer: CloudKitShareSpikeRecordPointer
    let shareURL: URL?
}

struct CloudKitShareSpikeClient {
    private enum RecordType {
        static let game = "CloudKitShareSpikeGame"
        static let move = "CloudKitShareSpikeMove"
    }

    private enum Field {
        static let createdAt = "createdAt"
        static let gameRecordName = "gameRecordName"
        static let note = "note"
    }

    private let zoneID = CKRecordZone.ID(zoneName: "CloudKitShareSpikeZone")
    private var container: CKContainer {
        CKContainer.default()
    }

    func accountStatusDescription() async throws -> String {
        let status = try await accountStatus()
        return "iCloud account status: \(status.description)"
    }

    func createSharedGame() async throws -> CloudKitShareSpikeCreationResult {
        try await ensurePrivateZone()

        let rootRecord = CKRecord(
            recordType: RecordType.game,
            recordID: CKRecord.ID(recordName: "game-\(UUID().uuidString)", zoneID: zoneID)
        )
        rootRecord[Field.createdAt] = Date() as CKRecordValue

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "ChessTutor CKShare Spike" as CKRecordValue
        share.publicPermission = .readWrite

        let saveResults = try await privateDatabase.modifyRecords(
            saving: [rootRecord, share],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        ).saveResults

        guard let savedRootResult = saveResults[rootRecord.recordID] else {
            throw CloudKitShareSpikeError.missingSavedRecord(rootRecord.recordID)
        }
        _ = try savedRootResult.get()

        guard let savedShare = try saveResults[share.recordID]?.get() as? CKShare else {
            throw CloudKitShareSpikeError.missingSavedRecord(share.recordID)
        }

        return CloudKitShareSpikeCreationResult(
            rootPointer: CloudKitShareSpikeRecordPointer(recordID: rootRecord.recordID),
            shareURL: savedShare.url
        )
    }

    func acceptShare(url: URL) async throws -> CloudKitShareSpikeRecordPointer {
        let metadataResults = try await container.shareMetadatas(for: [url])
        guard let metadataResult = metadataResults[url] else {
            throw CloudKitShareSpikeError.missingShareMetadata(url)
        }

        return try await accept(metadata: metadataResult.get())
    }

    func accept(metadata: CKShare.Metadata) async throws -> CloudKitShareSpikeRecordPointer {
        let acceptResults = try await container.accept([metadata])
        guard let acceptedResult = acceptResults[metadata] else {
            throw CloudKitShareSpikeError.missingAcceptedShare
        }

        _ = try acceptedResult.get()
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudKitShareSpikeError.missingAcceptedRootRecord
        }
        return CloudKitShareSpikeRecordPointer(recordID: rootRecordID)
    }

    func writeMove(
        note: String,
        rootPointer: CloudKitShareSpikeRecordPointer,
        databaseScope: CloudKitShareSpikeDatabaseScope
    ) async throws -> CKRecord.ID {
        let moveRecord = CKRecord(
            recordType: RecordType.move,
            recordID: CKRecord.ID(recordName: "move-\(UUID().uuidString)", zoneID: rootPointer.recordID.zoneID)
        )
        moveRecord.parent = CKRecord.Reference(recordID: rootPointer.recordID, action: .none)
        moveRecord[Field.createdAt] = Date() as CKRecordValue
        moveRecord[Field.gameRecordName] = rootPointer.recordName as CKRecordValue
        moveRecord[Field.note] = note as CKRecordValue

        let saveResults = try await database(for: databaseScope).modifyRecords(
            saving: [moveRecord],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        ).saveResults

        guard let savedMoveResult = saveResults[moveRecord.recordID] else {
            throw CloudKitShareSpikeError.missingSavedRecord(moveRecord.recordID)
        }
        _ = try savedMoveResult.get()

        return moveRecord.recordID
    }

    func fetchMoves(
        rootPointer: CloudKitShareSpikeRecordPointer,
        databaseScope: CloudKitShareSpikeDatabaseScope
    ) async throws -> [CloudKitShareSpikeMove] {
        let query = CKQuery(
            recordType: RecordType.move,
            predicate: NSPredicate(format: "%K == %@", Field.gameRecordName, rootPointer.recordName)
        )
        query.sortDescriptors = [NSSortDescriptor(key: Field.createdAt, ascending: true)]

        let results = try await database(for: databaseScope).records(
            matching: query,
            inZoneWith: rootPointer.recordID.zoneID
        )

        return try results.matchResults.map { recordID, result in
            let record = try result.get()
            return CloudKitShareSpikeMove(
                recordName: recordID.recordName,
                note: record[Field.note] as? String ?? ""
            )
        }
    }

    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    private var sharedDatabase: CKDatabase {
        container.sharedCloudDatabase
    }

    private func database(for scope: CloudKitShareSpikeDatabaseScope) -> CKDatabase {
        switch scope {
        case .private:
            return privateDatabase
        case .shared:
            return sharedDatabase
        }
    }

    private func ensurePrivateZone() async throws {
        _ = try await privateDatabase.modifyRecordZones(
            saving: [CKRecordZone(zoneID: zoneID)],
            deleting: []
        )
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

private extension CKAccountStatus {
    var description: String {
        switch self {
        case .available:
            return "available"
        case .couldNotDetermine:
            return "could not determine"
        case .noAccount:
            return "no account"
        case .restricted:
            return "restricted"
        case .temporarilyUnavailable:
            return "temporarily unavailable"
        @unknown default:
            return "unknown"
        }
    }
}

struct CloudKitShareSpikeAcceptedShareStore {
    private let key = "CloudKitShareSpikeAcceptedRootPointer"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ pointer: CloudKitShareSpikeRecordPointer) {
        guard let data = try? JSONEncoder().encode(pointer) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func load() -> CloudKitShareSpikeRecordPointer? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(CloudKitShareSpikeRecordPointer.self, from: data)
    }
}
#endif
