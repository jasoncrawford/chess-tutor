# CloudKit Invite Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current in-memory invite rendezvous with a real CloudKit-backed invite transport for creating invites, joining by code/link, preserving white-choice policy, and driving the existing confirmation UI.

**Architecture:** Add an invite-specific transport boundary that exposes app-shaped invite concepts and hides CloudKit types inside `ChessTutor/Remote/CloudKit`. CloudKit V1 stores short-lived pending invites in the public database, using the six-digit join code as the `CKRecord.ID.recordName`; invite links carry `code + token`, and the token is verified after direct record fetch. The accepted game and move-sync transport remain separate follow-up work.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen, CloudKit public database, existing `RemotePlayFlow` and `RemoteIdentityStore`.

---

## Scope

Included:

- CloudKit entitlements generated from source control.
- Invite domain models and transport protocol.
- In-memory invite transport for tests and simulator iteration.
- CloudKit pending-invite record codec and transport.
- Existing remote invite UI wired through the invite transport.
- User-facing loading and error states for create/join/cancel.

Not included:

- CKShare creation for accepted games.
- Move event storage in CloudKit.
- Push notifications.
- Presence.
- Expired-invite cleanup jobs beyond client-side expiry checks.

## File Structure

- Modify `project.yml`
  - Add the app entitlements file to build settings.
- Create `ChessTutor/ChessTutor.entitlements`
  - Source-controlled iCloud CloudKit entitlement for `iCloud.org.jasoncrawford.chesstutor`.
- Modify `ChessTutor/Remote/RemoteGameModels.swift`
  - Add invite IDs, code/token wrappers, invite status, white assignment, and request/result values.
- Create `ChessTutor/Remote/RemoteInviteTransport.swift`
  - Own invite transport protocol and in-memory implementation.
- Create `ChessTutor/Remote/CloudKit/CloudKitPendingInviteRecordCodec.swift`
  - Own `CKRecord` field names and conversion between CloudKit records and app invite models.
- Create `ChessTutor/Remote/CloudKit/CloudKitRemoteInviteTransport.swift`
  - Own direct CloudKit public-database create/fetch/update/delete calls.
- Modify `ChessTutor/Remote/RemotePlayFlow.swift`
  - Keep presentation state, but allow created/fetched invite records to supply code, token, inviter name, and white assignment.
- Modify `ChessTutor/UI/Remote/RemotePlaySheetView.swift`
  - Call async invite actions supplied by `ContentView`; show working/error states.
- Modify `ChessTutor/UI/Root/ContentView.swift`
  - Instantiate the real invite transport outside `DEBUG`; keep in-memory/fake behavior in simulator-friendly debug paths.
- Add tests under `ChessTutorTests/Remote/`.

## Task 1: CloudKit Entitlement Under XcodeGen

**Files:**
- Create: `ChessTutor/ChessTutor.entitlements`
- Modify: `project.yml`

- [ ] **Step 1: Add the entitlement file**

Create `ChessTutor/ChessTutor.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.org.jasoncrawford.chesstutor</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Wire entitlements into XcodeGen**

Modify `project.yml` under `targets.ChessTutor.settings.base`:

```yaml
        CODE_SIGN_ENTITLEMENTS: ChessTutor/ChessTutor.entitlements
```

- [ ] **Step 3: Regenerate the project**

Run:

```bash
xcodegen generate
```

Expected: `ChessTutor.xcodeproj/project.pbxproj` now contains `CODE_SIGN_ENTITLEMENTS = ChessTutor/ChessTutor.entitlements;`.

- [ ] **Step 4: Verify the app still builds**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add project.yml ChessTutor.xcodeproj/project.pbxproj ChessTutor/ChessTutor.entitlements
git commit -m "Configure CloudKit entitlements"
```

## Task 2: Invite Transport Models

**Files:**
- Modify: `ChessTutor/Remote/RemoteGameModels.swift`
- Test: `ChessTutorTests/Remote/RemoteInviteTransportModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Create `ChessTutorTests/Remote/RemoteInviteTransportModelTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteInviteTransportModelTests: XCTestCase {
    func testWhiteAssignmentMapsJoinerColor() {
        XCTAssertEqual(RemoteInviteWhiteAssignment.inviter.localPlayerColorForJoiner, .black)
        XCTAssertEqual(RemoteInviteWhiteAssignment.invitee.localPlayerColorForJoiner, .white)
        XCTAssertNil(RemoteInviteWhiteAssignment.inviteeChooses.localPlayerColorForJoiner)
    }

    func testInviteCodeFormatsSixDigits() {
        XCTAssertEqual(InviteCode(rawValue: "428193").formatted, "428 193")
        XCTAssertEqual(InviteCode(rawValue: "12345").formatted, "12345")
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemoteInviteTransportModelTests
```

Expected: fails because the invite transport model types do not exist.

- [ ] **Step 3: Add invite model types**

Append to `ChessTutor/Remote/RemoteGameModels.swift`:

```swift
struct RemoteInviteID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct InviteCode: Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    var formatted: String {
        guard rawValue.count == 6 else {
            return rawValue
        }
        let splitIndex = rawValue.index(rawValue.startIndex, offsetBy: 3)
        return "\(rawValue[..<splitIndex]) \(rawValue[splitIndex...])"
    }
}

struct RemoteInviteToken: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

enum RemoteInviteWhiteAssignment: String, Codable, Equatable, Sendable {
    case inviter
    case invitee
    case inviteeChooses

    var localPlayerColorForJoiner: PieceColor? {
        switch self {
        case .inviter:
            return .black
        case .invitee:
            return .white
        case .inviteeChooses:
            return nil
        }
    }
}

enum RemoteInviteStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case cancelled
    case expired
}

struct RemotePendingInvite: Codable, Equatable, Sendable {
    let id: RemoteInviteID
    let code: InviteCode
    let token: RemoteInviteToken
    let inviter: RemotePlayerRef
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let status: RemoteInviteStatus
    let createdAt: Date
    let expiresAt: Date
    let protocolVersion: Int
}

struct CreateRemoteInviteRequest: Equatable, Sendable {
    let inviter: RemotePlayerRef
    let inviteeDisplayName: String?
    let whiteAssignment: RemoteInviteWhiteAssignment
    let now: Date
    let expiresAt: Date
}

struct JoinRemoteInviteRequest: Equatable, Sendable {
    let code: InviteCode
    let token: RemoteInviteToken?
    let joiner: RemotePlayerRef
    let now: Date
}

struct RemoteAcceptedInvite: Equatable, Sendable {
    let invite: RemotePendingInvite
    let joiner: RemotePlayerRef
    let joinerColor: PieceColor
}
```

- [ ] **Step 4: Run model tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemoteInviteTransportModelTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteGameModels.swift ChessTutorTests/Remote/RemoteInviteTransportModelTests.swift
git commit -m "Add remote invite transport models"
```

## Task 3: In-Memory Invite Transport

**Files:**
- Create: `ChessTutor/Remote/RemoteInviteTransport.swift`
- Test: `ChessTutorTests/Remote/RemoteInviteTransportTests.swift`

- [ ] **Step 1: Write failing transport tests**

Create `ChessTutorTests/Remote/RemoteInviteTransportTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteInviteTransportTests: XCTestCase {
    func testCreatedInviteCanBeFetchedByCode() async throws {
        let transport = InMemoryRemoteInviteTransport(
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )
        let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: inviter,
                inviteeDisplayName: "Maya",
                whiteAssignment: .inviteeChooses,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )
        let fetched = try await transport.fetchInvite(code: InviteCode(rawValue: "428193"), token: nil, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(fetched, invite)
        XCTAssertEqual(fetched.whiteAssignment, .inviteeChooses)
    }

    func testLinkTokenMustMatchWhenPresent() async throws {
        let transport = InMemoryRemoteInviteTransport(
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )
        let inviter = RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason")
        _ = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: inviter,
                inviteeDisplayName: nil,
                whiteAssignment: .inviter,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await transport.fetchInvite(
                code: InviteCode(rawValue: "428193"),
                token: RemoteInviteToken(rawValue: "wrong"),
                now: Date(timeIntervalSince1970: 20)
            )
        )
    }
}
```

If the project has no async throwing assertion helper, add this helper at the bottom of the test file:

```swift
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemoteInviteTransportTests
```

Expected: fails because `RemoteInviteTransport` and `InMemoryRemoteInviteTransport` do not exist.

- [ ] **Step 3: Add transport protocol and in-memory implementation**

Create `ChessTutor/Remote/RemoteInviteTransport.swift`:

```swift
import Foundation

protocol RemoteInviteTransport: Sendable {
    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite
    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite
    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite
    func cancelInvite(id: RemoteInviteID) async throws
}

enum RemoteInviteTransportError: Error, Equatable {
    case notFound
    case tokenMismatch
    case expired
    case notPending
    case colorChoiceRequired
    case colorChoiceNotAllowed
    case codeCollision
}

actor InMemoryRemoteInviteTransport: RemoteInviteTransport {
    private var invitesByCode: [InviteCode: RemotePendingInvite] = [:]
    private let codeGenerator: @Sendable () -> InviteCode
    private let tokenGenerator: @Sendable () -> RemoteInviteToken

    init(
        codeGenerator: @escaping @Sendable () -> InviteCode = {
            InviteCode(rawValue: String(format: "%06d", Int.random(in: 0...999_999)))
        },
        tokenGenerator: @escaping @Sendable () -> RemoteInviteToken = {
            RemoteInviteToken(rawValue: UUID().uuidString)
        }
    ) {
        self.codeGenerator = codeGenerator
        self.tokenGenerator = tokenGenerator
    }

    func createInvite(_ request: CreateRemoteInviteRequest) async throws -> RemotePendingInvite {
        let code = codeGenerator()
        guard invitesByCode[code] == nil else {
            throw RemoteInviteTransportError.codeCollision
        }
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
        invitesByCode[code] = invite
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
        guard let invite = invitesByCode[code] else {
            throw RemoteInviteTransportError.notFound
        }
        if let token, token != invite.token {
            throw RemoteInviteTransportError.tokenMismatch
        }
        guard invite.status == .pending else {
            throw RemoteInviteTransportError.notPending
        }
        guard invite.expiresAt > now else {
            throw RemoteInviteTransportError.expired
        }
        return invite
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let invite = try await fetchInvite(code: request.code, token: request.token, now: request.now)
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

        let accepted = RemotePendingInvite(
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
        invitesByCode[request.code] = accepted
        return RemoteAcceptedInvite(invite: accepted, joiner: request.joiner, joinerColor: joinerColor)
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        guard let code = invitesByCode.first(where: { $0.value.id == id })?.key,
              let invite = invitesByCode[code] else {
            throw RemoteInviteTransportError.notFound
        }
        invitesByCode[code] = RemotePendingInvite(
            id: invite.id,
            code: invite.code,
            token: invite.token,
            inviter: invite.inviter,
            inviteeDisplayName: invite.inviteeDisplayName,
            whiteAssignment: invite.whiteAssignment,
            status: .cancelled,
            createdAt: invite.createdAt,
            expiresAt: invite.expiresAt,
            protocolVersion: invite.protocolVersion
        )
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemoteInviteTransportTests
```

Expected: transport tests pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteInviteTransport.swift ChessTutorTests/Remote/RemoteInviteTransportTests.swift
git commit -m "Add remote invite transport"
```

## Task 4: CloudKit Pending Invite Codec

**Files:**
- Create: `ChessTutor/Remote/CloudKit/CloudKitPendingInviteRecordCodec.swift`
- Test: `ChessTutorTests/Remote/CloudKitPendingInviteRecordCodecTests.swift`

- [ ] **Step 1: Write failing record codec tests**

Create `ChessTutorTests/Remote/CloudKitPendingInviteRecordCodecTests.swift`:

```swift
import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitPendingInviteRecordCodecTests: XCTestCase {
    func testRecordNameIsInviteCodeAndFieldsRoundTrip() throws {
        let invite = RemotePendingInvite(
            id: RemoteInviteID(rawValue: "428193"),
            code: InviteCode(rawValue: "428193"),
            token: RemoteInviteToken(rawValue: "token-1"),
            inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
            inviteeDisplayName: "Maya",
            whiteAssignment: .inviteeChooses,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 70),
            protocolVersion: 1
        )

        let record = CloudKitPendingInviteRecordCodec.record(from: invite)
        let decoded = try CloudKitPendingInviteRecordCodec.invite(from: record)

        XCTAssertEqual(record.recordID.recordName, "428193")
        XCTAssertEqual(decoded, invite)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/CloudKitPendingInviteRecordCodecTests
```

Expected: fails because the codec does not exist.

- [ ] **Step 3: Add the CloudKit record codec**

Create `ChessTutor/Remote/CloudKit/CloudKitPendingInviteRecordCodec.swift`:

```swift
import CloudKit
import Foundation

enum CloudKitPendingInviteRecordCodec {
    enum Error: Swift.Error, Equatable {
        case missingField(String)
        case invalidWhiteAssignment(String)
        case invalidStatus(String)
    }

    static let recordType = "PendingInvite"

    private enum Field {
        static let token = "token"
        static let inviterPlayerID = "inviterPlayerID"
        static let inviterDisplayName = "inviterDisplayName"
        static let inviteeDisplayName = "inviteeDisplayName"
        static let whiteAssignment = "whiteAssignment"
        static let status = "status"
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
        record[Field.token] = invite.token.rawValue as CKRecordValue
        record[Field.inviterPlayerID] = invite.inviter.id.rawValue as CKRecordValue
        record[Field.inviterDisplayName] = invite.inviter.displayName as CKRecordValue
        record[Field.inviteeDisplayName] = invite.inviteeDisplayName as CKRecordValue?
        record[Field.whiteAssignment] = invite.whiteAssignment.rawValue as CKRecordValue
        record[Field.status] = invite.status.rawValue as CKRecordValue
        record[Field.createdAt] = invite.createdAt as CKRecordValue
        record[Field.expiresAt] = invite.expiresAt as CKRecordValue
        record[Field.protocolVersion] = invite.protocolVersion as CKRecordValue
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
            inviteeDisplayName: record[Field.inviteeDisplayName] as? String,
            whiteAssignment: whiteAssignment,
            status: status,
            createdAt: try date(Field.createdAt, from: record),
            expiresAt: try date(Field.expiresAt, from: record),
            protocolVersion: try int(Field.protocolVersion, from: record)
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
```

- [ ] **Step 4: Run codec tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/CloudKitPendingInviteRecordCodecTests
```

Expected: codec tests pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/CloudKit/CloudKitPendingInviteRecordCodec.swift ChessTutorTests/Remote/CloudKitPendingInviteRecordCodecTests.swift
git commit -m "Add CloudKit invite record codec"
```

## Task 5: CloudKit Invite Transport

**Files:**
- Create: `ChessTutor/Remote/CloudKit/CloudKitRemoteInviteTransport.swift`
- Test: `ChessTutorTests/Remote/CloudKitRemoteInviteTransportTests.swift`

- [ ] **Step 1: Write failing tests with an in-memory CloudKit client**

Create `ChessTutorTests/Remote/CloudKitRemoteInviteTransportTests.swift` with an in-memory client that implements the same small database protocol as the production transport:

```swift
import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitRemoteInviteTransportTests: XCTestCase {
    func testCreateInviteSavesRecordByCodeAndFetchesItBack() async throws {
        let database = InMemoryCloudKitInviteDatabase()
        let transport = CloudKitRemoteInviteTransport(
            database: database,
            codeGenerator: { InviteCode(rawValue: "428193") },
            tokenGenerator: { RemoteInviteToken(rawValue: "token-1") }
        )

        let invite = try await transport.createInvite(
            CreateRemoteInviteRequest(
                inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
                inviteeDisplayName: "Maya",
                whiteAssignment: .invitee,
                now: Date(timeIntervalSince1970: 10),
                expiresAt: Date(timeIntervalSince1970: 70)
            )
        )
        let fetched = try await transport.fetchInvite(code: InviteCode(rawValue: "428193"), token: nil, now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(invite, fetched)
        XCTAssertNotNil(await database.record(withID: CKRecord.ID(recordName: "428193")))
    }
}
```

Add this test helper in the same file:

```swift
private actor InMemoryCloudKitInviteDatabase: CloudKitInviteDatabase {
    var records: [CKRecord.ID: CKRecord] = [:]

    func record(withID id: CKRecord.ID) -> CKRecord? {
        records[id]
    }

    func records(for ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]?) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        Dictionary(uniqueKeysWithValues: ids.map { id in
            if let record = records[id] {
                return (id, .success(record))
            } else {
                return (id, .failure(CKError(.unknownItem)))
            }
        })
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
        for record in recordsToSave {
            records[record.recordID] = record
        }
        for id in recordIDsToDelete {
            records.removeValue(forKey: id)
        }
        return (
            saveResults: Dictionary(uniqueKeysWithValues: recordsToSave.map { ($0.recordID, .success($0)) }),
            deleteResults: Dictionary(uniqueKeysWithValues: recordIDsToDelete.map { ($0, .success(())) })
        )
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/CloudKitRemoteInviteTransportTests
```

Expected: fails because `CloudKitRemoteInviteTransport` and `CloudKitInviteDatabase` do not exist.

- [ ] **Step 3: Add CloudKit database protocol and transport**

Create `ChessTutor/Remote/CloudKit/CloudKitRemoteInviteTransport.swift`:

```swift
import CloudKit
import Foundation

protocol CloudKitInviteDatabase: Sendable {
    func records(for ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]?) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]
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

extension CKDatabase: CloudKitInviteDatabase {}

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
        guard case .success = result.saveResults[record.recordID] else {
            throw RemoteInviteTransportError.codeCollision
        }
        return invite
    }

    func fetchInvite(code: InviteCode, token: RemoteInviteToken?, now: Date) async throws -> RemotePendingInvite {
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
        return invite
    }

    func acceptInvite(_ request: JoinRemoteInviteRequest, chosenColor: PieceColor?) async throws -> RemoteAcceptedInvite {
        let invite = try await fetchInvite(code: request.code, token: request.token, now: request.now)
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

        let accepted = RemotePendingInvite(
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
        let record = CloudKitPendingInviteRecordCodec.record(from: accepted)
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys, atomically: true)
        return RemoteAcceptedInvite(invite: accepted, joiner: request.joiner, joinerColor: joinerColor)
    }

    func cancelInvite(id: RemoteInviteID) async throws {
        let recordID = CKRecord.ID(recordName: id.rawValue)
        _ = try await database.modifyRecords(saving: [], deleting: [recordID], savePolicy: .changedKeys, atomically: true)
    }
}
```

- [ ] **Step 4: Run CloudKit transport tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/CloudKitRemoteInviteTransportTests
```

Expected: CloudKit transport tests pass using the in-memory CloudKit database client.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/CloudKit/CloudKitRemoteInviteTransport.swift ChessTutorTests/Remote/CloudKitRemoteInviteTransportTests.swift
git commit -m "Add CloudKit invite transport"
```

## Task 6: Wire Invite Transport Into The Existing UI Flow

**Files:**
- Modify: `ChessTutor/Remote/RemotePlayFlow.swift`
- Modify: `ChessTutor/UI/Remote/RemotePlaySheetView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Test: `ChessTutorTests/Remote/RemotePlayFlowTests.swift`

- [ ] **Step 1: Write failing flow tests for remote-created invites**

Add to `ChessTutorTests/Remote/RemotePlayFlowTests.swift`:

```swift
func testCreatedRemoteInvitePresentationUsesTransportInviteCodeAndLinkToken() {
    let flow = RemotePlayFlow(localDisplayName: "Jason")
    let invite = RemotePendingInvite(
        id: RemoteInviteID(rawValue: "428193"),
        code: InviteCode(rawValue: "428193"),
        token: RemoteInviteToken(rawValue: "token-1"),
        inviter: RemotePlayerRef(id: RemotePlayerID(rawValue: "jason"), displayName: "Jason"),
        inviteeDisplayName: "Maya",
        whiteAssignment: .inviteeChooses,
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 10),
        expiresAt: Date(timeIntervalSince1970: 70),
        protocolVersion: 1
    )

    flow.open()
    flow.inviteSomeoneNew()
    flow.showCreatedRemoteInvite(invite, target: .newPlayer)

    guard case .waitingForInvitee(let pendingInvite) = flow.stage else {
        return XCTFail("Expected waiting state")
    }
    let presentation = flow.inviteSharePresentation(for: pendingInvite)
    XCTAssertEqual(presentation.code, "428 193")
    XCTAssertEqual(presentation.inviteURL.absoluteString, "chesstutor://invite?code=428193&token=token-1")
}
```

- [ ] **Step 2: Run the flow test and verify it fails**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemotePlayFlowTests/testCreatedRemoteInvitePresentationUsesTransportInviteCodeAndLinkToken
```

Expected: fails because `showCreatedRemoteInvite` does not exist and invite URLs do not include token.

- [ ] **Step 3: Extend `RemotePlayFlow.PendingInvite`**

Modify `PendingInvite` in `ChessTutor/Remote/RemotePlayFlow.swift`:

```swift
struct PendingInvite: Equatable, Hashable {
    let target: InviteTarget
    let whiteChoice: WhiteChoice
    let code: String
    let token: String?
    let remoteInviteID: RemoteInviteID?

    init(
        target: InviteTarget,
        whiteChoice: WhiteChoice,
        code: String,
        token: String? = nil,
        remoteInviteID: RemoteInviteID? = nil
    ) {
        self.target = target
        self.whiteChoice = whiteChoice
        self.code = code
        self.token = token
        self.remoteInviteID = remoteInviteID
    }

    var formattedCode: String {
        InviteCode(rawValue: code).formatted
    }
}
```

Update existing tests that construct `PendingInvite` to rely on the default `token` and `remoteInviteID` values.

- [ ] **Step 4: Add remote-created invite state transition**

Add to `RemotePlayFlow`:

```swift
func showCreatedRemoteInvite(_ invite: RemotePendingInvite, target: InviteTarget) {
    let pendingInvite = PendingInvite(
        target: target,
        whiteChoice: Self.whiteChoice(from: invite.whiteAssignment),
        code: invite.code.rawValue,
        token: invite.token.rawValue,
        remoteInviteID: invite.id
    )
    inviteWhiteChoicesByCode[pendingInvite.code] = pendingInvite.whiteChoice
    stage = .waitingForInvitee(pendingInvite)
}

private static func whiteChoice(from assignment: RemoteInviteWhiteAssignment) -> WhiteChoice {
    switch assignment {
    case .inviter:
        return .localPlayer
    case .invitee:
        return .invitee
    case .inviteeChooses:
        return .inviteeChooses
    }
}
```

Modify `inviteURL(for:)` so links include token when present:

```swift
private static func inviteURL(for pendingInvite: PendingInvite) -> URL {
    var queryItems = [URLQueryItem(name: "code", value: pendingInvite.code)]
    if let token = pendingInvite.token {
        queryItems.append(URLQueryItem(name: "token", value: token))
    }

    var components = URLComponents()
    components.scheme = "chesstutor"
    components.host = "invite"
    components.queryItems = queryItems
    return components.url!
}
```

- [ ] **Step 5: Run flow tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemotePlayFlowTests
```

Expected: all `RemotePlayFlowTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Remote/RemotePlayFlow.swift ChessTutorTests/Remote/RemotePlayFlowTests.swift
git commit -m "Use transport invites in remote play flow"
```

## Task 7: Async UI Actions For Create And Join

**Files:**
- Modify: `ChessTutor/UI/Remote/RemotePlaySheetView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`

- [ ] **Step 1: Add sheet callbacks and local working state**

Modify `RemotePlaySheetView` to accept async callbacks:

```swift
let onCreateRemoteInvite: (RemotePlayFlow.InviteTarget, RemotePlayFlow.WhiteChoice) async throws -> RemotePendingInvite
let onFetchRemoteInvite: (InviteCode, RemoteInviteToken?) async throws -> RemotePendingInvite
```

Add state:

```swift
@State private var remoteInviteTask: Task<Void, Never>?
@State private var remoteInviteErrorMessage: String?
@State private var isWorkingWithRemoteInvite = false
```

- [ ] **Step 2: Replace direct send invite with async create**

In the send-invite button action, call a new helper:

```swift
private func createRemoteInvite(target: RemotePlayFlow.InviteTarget) {
    let whiteChoice = flow.selectedWhiteChoice
    isWorkingWithRemoteInvite = true
    remoteInviteErrorMessage = nil
    remoteInviteTask?.cancel()
    remoteInviteTask = Task { @MainActor in
        do {
            let invite = try await onCreateRemoteInvite(target, whiteChoice)
            flow.showCreatedRemoteInvite(invite, target: target)
        } catch {
            remoteInviteErrorMessage = "Could not create invite. Check your connection and try again."
        }
        isWorkingWithRemoteInvite = false
    }
}
```

Show `remoteInviteErrorMessage` beneath the primary action using the same muted/error text styling as join errors.

- [ ] **Step 3: Wire real transport in `ContentView`**

Add properties:

```swift
private let remoteInviteTransport: any RemoteInviteTransport
```

In `init()`:

```swift
#if DEBUG
self.remoteInviteTransport = InMemoryRemoteInviteTransport()
#else
self.remoteInviteTransport = CloudKitRemoteInviteTransport()
#endif
```

Add helpers:

```swift
private func createRemoteInvite(
    target: RemotePlayFlow.InviteTarget,
    whiteChoice: RemotePlayFlow.WhiteChoice
) async throws -> RemotePendingInvite {
    let profile = try remoteIdentityStore.loadLocalProfile()
    guard let displayName = profile.displayName else {
        throw RemoteInviteTransportError.notFound
    }

    return try await remoteInviteTransport.createInvite(
        CreateRemoteInviteRequest(
            inviter: RemotePlayerRef(id: profile.id, displayName: displayName),
            inviteeDisplayName: remoteInviteeDisplayName(for: target),
            whiteAssignment: remoteWhiteAssignment(from: whiteChoice),
            now: Date(),
            expiresAt: Date().addingTimeInterval(10 * 60)
        )
    )
}

private func remoteInviteeDisplayName(for target: RemotePlayFlow.InviteTarget) -> String? {
    switch target {
    case .known(let player):
        return player.displayName
    case .newPlayer:
        return nil
    }
}

private func remoteWhiteAssignment(from choice: RemotePlayFlow.WhiteChoice) -> RemoteInviteWhiteAssignment {
    switch choice {
    case .localPlayer:
        return .inviter
    case .invitee:
        return .invitee
    case .inviteeChooses:
        return .inviteeChooses
    }
}
```

Pass `onCreateRemoteInvite: createRemoteInvite` into `RemotePlaySheetView`.

- [ ] **Step 4: Build to catch UI integration errors**

Run:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/UI/Remote/RemotePlaySheetView.swift ChessTutor/UI/Root/ContentView.swift
git commit -m "Create remote invites through transport"
```

## Task 8: Join Code And Link Through Transport

**Files:**
- Modify: `ChessTutor/Remote/RemotePlayFlow.swift`
- Modify: `ChessTutor/UI/Remote/RemotePlaySheetView.swift`
- Modify: `ChessTutor/UI/Root/ContentView.swift`
- Test: `ChessTutorTests/Remote/RemotePlayFlowTests.swift`

- [ ] **Step 1: Write failing URL parsing tests**

Add to `RemotePlayFlowTests`:

```swift
func testInviteLinkParsesCodeAndTokenWithoutPolicy() {
    let parsed = RemotePlayFlow.inviteLookup(from: URL(string: "chesstutor://invite?code=428193&token=token-1")!)

    XCTAssertEqual(parsed?.code, InviteCode(rawValue: "428193"))
    XCTAssertEqual(parsed?.token, RemoteInviteToken(rawValue: "token-1"))
}
```

- [ ] **Step 2: Run the URL parsing test and verify it fails**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemotePlayFlowTests/testInviteLinkParsesCodeAndTokenWithoutPolicy
```

Expected: fails because `inviteLookup(from:)` does not exist.

- [ ] **Step 3: Add a lookup parser**

Add to `RemotePlayFlow`:

```swift
struct InviteLookup: Equatable {
    let code: InviteCode
    let token: RemoteInviteToken?
}

static func inviteLookup(from url: URL) -> InviteLookup? {
    guard url.scheme == "chesstutor",
          url.host == "invite",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let rawCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
        return nil
    }

    let code = String(rawCode.filter(\.isNumber).prefix(6))
    guard code.count == 6 else {
        return nil
    }

    let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        .map(RemoteInviteToken.init(rawValue:))
    return InviteLookup(code: InviteCode(rawValue: code), token: token)
}
```

Keep `inviteCode(from:)` as a private compatibility helper only if existing tests still require it; otherwise route callers through `inviteLookup(from:)`.

- [ ] **Step 4: Fetch invite before showing confirmation**

In `ContentView.handleInviteURL`, parse the lookup and fetch the invite through `remoteInviteTransport`:

```swift
private func handleInviteURL(_ url: URL) {
    guard let lookup = RemotePlayFlow.inviteLookup(from: url) else {
        remotePlayFlow.open()
        return
    }

    Task { @MainActor in
        do {
            let invite = try await remoteInviteTransport.fetchInvite(
                code: lookup.code,
                token: lookup.token,
                now: Date()
            )
            showRemoteInviteConfirmation(
                RemoteInviteConfirmation(
                    opponentName: invite.inviter.displayName,
                    localPlayerColor: invite.whiteAssignment.localPlayerColorForJoiner
                )
            )
        } catch {
            remotePlayFlow.open()
        }
    }
}
```

- [ ] **Step 5: Fetch invite for manual join code**

In `RemotePlaySheetView.joinWithCode`, replace the fake synchronous `flow.requestJoinCode()` success path with:

```swift
private func joinWithCode() {
    let code = InviteCode(rawValue: flow.joinCode)
    isWorkingWithRemoteInvite = true
    remoteInviteErrorMessage = nil
    remoteInviteTask?.cancel()
    remoteInviteTask = Task { @MainActor in
        do {
            let invite = try await onFetchRemoteInvite(code, nil)
            onRemoteInviteConfirmationNeeded(
                RemoteInviteConfirmation(
                    opponentName: invite.inviter.displayName,
                    localPlayerColor: invite.whiteAssignment.localPlayerColorForJoiner
                )
            )
            flow.cancel()
        } catch {
            remoteInviteErrorMessage = "That code did not match an open invite."
        }
        isWorkingWithRemoteInvite = false
    }
}
```

Pass `onFetchRemoteInvite` from `ContentView`:

```swift
private func fetchRemoteInvite(code: InviteCode, token: RemoteInviteToken?) async throws -> RemotePendingInvite {
    try await remoteInviteTransport.fetchInvite(code: code, token: token, now: Date())
}
```

- [ ] **Step 6: Run remote flow tests and build**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5' -only-testing:ChessTutorTests/RemotePlayFlowTests
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5'
```

Expected: flow tests pass and build succeeds.

- [ ] **Step 7: Commit**

```bash
git add ChessTutor/Remote/RemotePlayFlow.swift ChessTutor/UI/Remote/RemotePlaySheetView.swift ChessTutor/UI/Root/ContentView.swift ChessTutorTests/Remote/RemotePlayFlowTests.swift
git commit -m "Join remote invites through transport"
```

## Task 9: Manual CloudKit Device Verification

**Files:**
- No source changes unless verification reveals a bug.

- [ ] **Step 1: Run full automated tests**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5'
```

Expected: all tests pass with 0 failures.

- [ ] **Step 2: Install on the physical iPad**

Use Xcode or:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS,name=<connected iPad name>'
```

Expected: app builds and installs with CloudKit entitlements.

- [ ] **Step 3: Verify owner account**

On the iPad signed into the owner iCloud account:

1. Launch ChessTutor.
2. Tap `Play Remotely`.
3. Choose `Someone New`.
4. Choose `Let them choose`.
5. Tap `Send Invite`.

Expected:

- Share screen appears with a six-digit code and copyable link.
- The link contains `code` and `token`, but no `white` or policy parameter.

- [ ] **Step 4: Verify joiner account**

Switch the same iPad to the second iCloud account, or use a second device signed into the second account:

1. Launch ChessTutor.
2. Tap `Play Remotely`.
3. Enter the owner code.

Expected:

- Joiner sees `<owner name> wants to play`.
- White/Black choice is shown because owner chose `Let them choose`.
- `Start` is disabled until a color is chosen.

- [ ] **Step 5: Verify fixed color policies**

Repeat owner invite creation with:

- `Me`
- invitee name

Expected:

- `Me`: joiner confirmation starts with joiner as Black.
- Invitee name: joiner confirmation starts with joiner as White.
- No choice UI appears in either fixed-color case.

- [ ] **Step 6: Commit any verification fixes**

If manual verification revealed and fixed bugs:

```bash
git add <changed files>
git commit -m "Fix CloudKit invite verification issue"
```

If no source changes were needed, do not create an empty commit.

## Final Verification

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4),OS=26.5'
```

Expected: all tests pass with 0 failures.

Then build the simulator app for quick UI smoke testing:

```bash
xcodebuild build -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16),OS=26.5'
```

Expected: `** BUILD SUCCEEDED **`.

## Scope Notes For The Next Plan

The next plan after this one should convert an accepted invite into an accepted remote game:

- Create or accept a CKShare-backed game root.
- Persist active remote game metadata locally.
- Connect `RemoteGameCoordinator` to the accepted game.
- Store and fetch move events through the accepted shared database.
- Replace debug fake remote moves with real transport move sync.
