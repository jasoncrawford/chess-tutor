# Remote Play Transport Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the transport-independent foundation for private remote play: canonical remote models, move encoding, position fingerprints, move-log validation, an outbox, a fake transport, and the first `GameSession` hooks for remote turn ownership.

**Architecture:** Add a new `ChessTutor/Remote` module that depends on `Core` and `Game` value types but does not import CloudKit or SwiftUI. `GameSession` remains the board-facing model; remote infrastructure records committed moves and decides whether the local player may act. CloudKit integration, invite UI, notifications, and persistence files are intentionally left for later plans.

**Tech Stack:** Swift 6, XCTest, XcodeGen source autodiscovery, native iOS target.

---

## Scope

This plan implements the first buildable slice from `docs/superpowers/specs/2026-07-01-remote-play-technical-architecture.md`.

Included:

- Remote domain identifiers and event models.
- Codable encoding for `Move`.
- Deterministic `PositionFingerprint`.
- Remote move-log projector and validator.
- In-memory outbox state machine.
- In-memory fake transport for later coordinator tests.
- `GameSession` hooks to expose committed moves and deny remote-turn movement while allowing piece inspection.

Not included:

- CloudKit records or CKShare adapter.
- Invite links or short codes.
- Notifications or presence.
- Application Support JSON persistence.
- Remote-play modal UI.

## File Structure

- Create `ChessTutor/Remote/RemoteGameModels.swift`
  - Owns app-shaped remote identifiers, player refs, game descriptors, move events, acknowledgments, and transport errors.
- Create `ChessTutor/Remote/RemoteMoveCodec.swift`
  - Encodes and decodes `Move` and `Move.Special` into Codable wire values.
- Modify `ChessTutor/Core/Piece.swift`
  - Adds `Codable` to `Piece.Kind` so promotion moves can be encoded without duplicating piece-kind names.
- Create `ChessTutor/Remote/PositionFingerprinting.swift`
  - Produces a deterministic string fingerprint from `GameState`.
- Create `ChessTutor/Remote/RemoteMoveLog.swift`
  - Applies ordered `RemoteMoveEvent` values to a projected `GameState` and rejects invalid sequences or payloads.
- Create `ChessTutor/Remote/RemoteOutbox.swift`
  - Tracks local committed events pending upload and matches acknowledgments idempotently.
- Create `ChessTutor/Remote/RemoteGameTransport.swift`
  - Defines the transport protocol and a test fake with no CloudKit dependency.
- Modify `ChessTutor/Game/PlayerSeat.swift`
  - Add remote-player seat identity while preserving `.humanLocal`.
- Modify `ChessTutor/Game/GameSession.swift`
  - Return the committed move from `finishTurn`, add local-turn permission checks, and allow remote piece inspection without destination affordances.
- Create tests under `ChessTutorTests/Remote/`.
- Extend `ChessTutorTests/Game/GameSessionTests.swift`.

## Task 1: Remote Models And Move Codec

**Files:**
- Modify: `ChessTutor/Core/Piece.swift`
- Create: `ChessTutor/Remote/RemoteGameModels.swift`
- Create: `ChessTutor/Remote/RemoteMoveCodec.swift`
- Test: `ChessTutorTests/Remote/RemoteMoveCodecTests.swift`

- [ ] **Step 1: Write failing move codec tests**

Create `ChessTutorTests/Remote/RemoteMoveCodecTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteMoveCodecTests: XCTestCase {
    func testEncodesNormalMove() throws {
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))

        let encoded = RemoteMoveCodec.encode(move)

        XCTAssertEqual(encoded.from, "e2")
        XCTAssertEqual(encoded.to, "e4")
        XCTAssertEqual(encoded.special, .none)
    }

    func testRoundTripsPromotionMove() throws {
        let move = Move(
            from: Square(file: .e, rank: 7),
            to: Square(file: .e, rank: 8),
            special: .promotion(.queen)
        )

        let encoded = RemoteMoveCodec.encode(move)
        let decoded = try RemoteMoveCodec.decode(encoded)

        XCTAssertEqual(decoded, move)
    }

    func testDecodingRejectsInvalidSquare() {
        let encoded = RemoteEncodedMove(from: "i2", to: "e4", special: .none)

        XCTAssertThrowsError(try RemoteMoveCodec.decode(encoded)) { error in
            XCTAssertEqual(error as? RemoteMoveCodec.Error, .invalidSquare("i2"))
        }
    }
}
```

- [ ] **Step 2: Run codec tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteMoveCodecTests
```

Expected: fails because `RemoteMoveCodecTests`, `RemoteMoveCodec`, and `RemoteEncodedMove` do not exist.

- [ ] **Step 3: Make piece kinds Codable**

Modify `ChessTutor/Core/Piece.swift`:

```swift
struct Piece: Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Codable, Sendable {
        case king
        case queen
        case rook
        case bishop
        case knight
        case pawn
    }

    let kind: Kind
    let color: PieceColor
}
```

- [ ] **Step 4: Add remote model types**

Create `ChessTutor/Remote/RemoteGameModels.swift`:

```swift
import Foundation

struct RemoteGameID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemotePlayerID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemoteMoveEventID: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemotePlayerRef: Codable, Equatable, Sendable {
    let id: RemotePlayerID
    let displayName: String
}

enum RemoteGameStatus: String, Codable, Equatable, Sendable {
    case active
    case ended
    case error
}

struct RemoteGameDescriptor: Codable, Equatable, Sendable {
    let id: RemoteGameID
    let protocolVersion: Int
    let status: RemoteGameStatus
    let whitePlayer: RemotePlayerRef
    let blackPlayer: RemotePlayerRef
    let localPlayerID: RemotePlayerID
}

struct PositionFingerprint: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
}

struct RemoteMoveEvent: Codable, Equatable, Sendable {
    let id: RemoteMoveEventID
    let gameID: RemoteGameID
    let sequenceNumber: Int
    let actorPlayerID: RemotePlayerID
    let move: RemoteEncodedMove
    let createdAt: Date
    let protocolVersion: Int
    let previousPositionFingerprint: PositionFingerprint
    let resultingPositionFingerprint: PositionFingerprint
    let notificationSummary: String
}

struct RemoteMoveAck: Codable, Equatable, Sendable {
    let eventID: RemoteMoveEventID
    let gameID: RemoteGameID
    let sequenceNumber: Int
}
```

- [ ] **Step 5: Add move codec**

Create `ChessTutor/Remote/RemoteMoveCodec.swift`:

```swift
enum RemoteMoveSpecial: Codable, Equatable, Sendable {
    case none
    case castleKingside
    case castleQueenside
    case enPassant
    case promotion(Piece.Kind)
}

struct RemoteEncodedMove: Codable, Equatable, Sendable {
    let from: String
    let to: String
    let special: RemoteMoveSpecial
}

enum RemoteMoveCodec {
    enum Error: Swift.Error, Equatable {
        case invalidSquare(String)
    }

    static func encode(_ move: Move) -> RemoteEncodedMove {
        RemoteEncodedMove(
            from: encode(move.from),
            to: encode(move.to),
            special: encode(move.special)
        )
    }

    static func encodeSquare(_ square: Square) -> String {
        encode(square)
    }

    static func decode(_ encoded: RemoteEncodedMove) throws -> Move {
        Move(
            from: try decodeSquare(encoded.from),
            to: try decodeSquare(encoded.to),
            special: decode(encoded.special)
        )
    }

    private static func encode(_ square: Square) -> String {
        "\(fileLetter(for: square.file))\(square.rank)"
    }

    private static func decodeSquare(_ value: String) throws -> Square {
        guard value.count == 2,
              let fileCharacter = value.first,
              let rankCharacter = value.last,
              let file = file(for: fileCharacter),
              let rank = Int(String(rankCharacter)),
              (1...8).contains(rank) else {
            throw Error.invalidSquare(value)
        }
        return Square(file: file, rank: rank)
    }

    private static func encode(_ special: Move.Special?) -> RemoteMoveSpecial {
        switch special {
        case .castleKingside:
            return .castleKingside
        case .castleQueenside:
            return .castleQueenside
        case .enPassant:
            return .enPassant
        case .promotion(let kind):
            return .promotion(kind)
        case nil:
            return .none
        }
    }

    private static func decode(_ special: RemoteMoveSpecial) -> Move.Special? {
        switch special {
        case .none:
            return nil
        case .castleKingside:
            return .castleKingside
        case .castleQueenside:
            return .castleQueenside
        case .enPassant:
            return .enPassant
        case .promotion(let kind):
            return .promotion(kind)
        }
    }

    private static func fileLetter(for file: Square.File) -> String {
        switch file {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        }
    }

    private static func file(for character: Character) -> Square.File? {
        switch character {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        default: return nil
        }
    }
}
```

- [ ] **Step 6: Run codec tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteMoveCodecTests
```

Expected: `RemoteMoveCodecTests` pass.

- [ ] **Step 7: Commit**

```bash
git add ChessTutor/Core/Piece.swift ChessTutor/Remote/RemoteGameModels.swift ChessTutor/Remote/RemoteMoveCodec.swift ChessTutorTests/Remote/RemoteMoveCodecTests.swift
git commit -m "Add remote move codec"
```

## Task 2: Position Fingerprints

**Files:**
- Create: `ChessTutor/Remote/PositionFingerprinting.swift`
- Test: `ChessTutorTests/Remote/PositionFingerprintingTests.swift`

- [ ] **Step 1: Write failing fingerprint tests**

Create `ChessTutorTests/Remote/PositionFingerprintingTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class PositionFingerprintingTests: XCTestCase {
    func testStartingPositionFingerprintIsDeterministic() {
        let first = PositionFingerprinting.fingerprint(for: .startingPosition())
        let second = PositionFingerprinting.fingerprint(for: .startingPosition())

        XCTAssertEqual(first, second)
    }

    func testFingerprintChangesAfterMove() {
        var state = GameState.startingPosition()
        let before = PositionFingerprinting.fingerprint(for: state)

        state.apply(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))
        let after = PositionFingerprinting.fingerprint(for: state)

        XCTAssertNotEqual(before, after)
    }

    func testFingerprintIncludesSideToMove() {
        var whiteToMove = GameState.startingPosition()
        var blackToMove = GameState.startingPosition()
        blackToMove.sideToMove = .black

        XCTAssertNotEqual(
            PositionFingerprinting.fingerprint(for: whiteToMove),
            PositionFingerprinting.fingerprint(for: blackToMove)
        )
    }
}
```

- [ ] **Step 2: Run fingerprint tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PositionFingerprintingTests
```

Expected: fails because `PositionFingerprinting` does not exist.

- [ ] **Step 3: Add deterministic fingerprinting**

Create `ChessTutor/Remote/PositionFingerprinting.swift`:

```swift
enum PositionFingerprinting {
    static func fingerprint(for state: GameState) -> PositionFingerprint {
        PositionFingerprint(rawValue: components(for: state).joined(separator: "|"))
    }

    private static func components(for state: GameState) -> [String] {
        [
            boardComponent(for: state.board),
            "turn:\(state.sideToMove.rawValue)",
            "castle:\(castlingComponent(for: state.castlingRights))",
            "ep:\(state.enPassantTarget.map(squareComponent) ?? "-")",
            "result:\(resultComponent(for: state.result))",
            "moves:\(state.moveHistory.count)",
        ]
    }

    private static func boardComponent(for board: Board) -> String {
        Square.File.allCases.flatMap { file in
            (1...8).map { rank in
                let square = Square(file: file, rank: rank)
                guard let piece = board[square] else {
                    return "\(squareComponent(square))=empty"
                }
                return "\(squareComponent(square))=\(piece.color.rawValue)-\(piece.kind.rawValue)"
            }
        }
        .joined(separator: ",")
    }

    private static func castlingComponent(for rights: CastlingRights) -> String {
        [
            rights.whiteKingside ? "K" : "-",
            rights.whiteQueenside ? "Q" : "-",
            rights.blackKingside ? "k" : "-",
            rights.blackQueenside ? "q" : "-",
        ].joined()
    }

    private static func resultComponent(for result: GameResult) -> String {
        switch result {
        case .ongoing:
            return "ongoing"
        case .checkmate(let winner):
            return "checkmate-\(winner.rawValue)"
        case .stalemate:
            return "stalemate"
        }
    }

    private static func squareComponent(_ square: Square) -> String {
        RemoteMoveCodec.encodeSquare(square)
    }
}
```

- [ ] **Step 4: Run fingerprint tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/PositionFingerprintingTests
```

Expected: `PositionFingerprintingTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/PositionFingerprinting.swift ChessTutor/Remote/RemoteMoveCodec.swift ChessTutorTests/Remote/PositionFingerprintingTests.swift
git commit -m "Add remote position fingerprints"
```

## Task 3: Remote Move Log Projection And Validation

**Files:**
- Create: `ChessTutor/Remote/RemoteMoveLog.swift`
- Test: `ChessTutorTests/Remote/RemoteMoveLogTests.swift`

- [ ] **Step 1: Write failing move-log tests**

Create `ChessTutorTests/Remote/RemoteMoveLogTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteMoveLogTests: XCTestCase {
    private let gameID = RemoteGameID(rawValue: "game-1")
    private let whiteID = RemotePlayerID(rawValue: "white")
    private let blackID = RemotePlayerID(rawValue: "black")

    func testAppliesValidMoveEvent() throws {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 1, actor: whiteID, move: move, from: state)

        let result = try RemoteMoveLog.apply(
            events: [event],
            to: state,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )

        XCTAssertEqual(result.state.board[Square(file: .e, rank: 4)], Piece(kind: .pawn, color: .white))
        XCTAssertEqual(result.lastAppliedSequence, 1)
    }

    func testRejectsMissingSequence() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 2, actor: whiteID, move: move, from: state)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .unexpectedSequence(expected: 1, actual: 2))
        }
    }

    func testRejectsWrongActorForTurn() {
        let state = GameState.startingPosition()
        let move = Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))
        let event = makeEvent(sequence: 1, actor: blackID, move: move, from: state)

        XCTAssertThrowsError(try RemoteMoveLog.apply(
            events: [event],
            to: state,
            whitePlayerID: whiteID,
            blackPlayerID: blackID
        )) { error in
            XCTAssertEqual(error as? RemoteMoveLog.Error, .wrongActor(expected: whiteID, actual: blackID))
        }
    }

    private func makeEvent(
        sequence: Int,
        actor: RemotePlayerID,
        move: Move,
        from state: GameState
    ) -> RemoteMoveEvent {
        var next = state
        next.apply(move)
        return RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: gameID,
            sequenceNumber: sequence,
            actorPlayerID: actor,
            move: RemoteMoveCodec.encode(move),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprinting.fingerprint(for: state),
            resultingPositionFingerprint: PositionFingerprinting.fingerprint(for: next),
            notificationSummary: "Test move"
        )
    }
}
```

- [ ] **Step 2: Run move-log tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteMoveLogTests
```

Expected: fails because `RemoteMoveLog` does not exist.

- [ ] **Step 3: Add move-log projection**

Create `ChessTutor/Remote/RemoteMoveLog.swift`:

```swift
enum RemoteMoveLog {
    struct ApplyResult: Equatable {
        let state: GameState
        let lastAppliedSequence: Int
    }

    enum Error: Swift.Error, Equatable {
        case unexpectedSequence(expected: Int, actual: Int)
        case wrongActor(expected: RemotePlayerID, actual: RemotePlayerID)
        case previousFingerprintMismatch
        case resultingFingerprintMismatch
        case illegalMove(Move)
    }

    static func apply(
        events: [RemoteMoveEvent],
        to initialState: GameState,
        whitePlayerID: RemotePlayerID,
        blackPlayerID: RemotePlayerID,
        startingAfter lastAppliedSequence: Int = 0
    ) throws -> ApplyResult {
        var state = initialState
        var expectedSequence = lastAppliedSequence + 1

        for event in events.sorted(by: { $0.sequenceNumber < $1.sequenceNumber }) {
            guard event.sequenceNumber == expectedSequence else {
                throw Error.unexpectedSequence(expected: expectedSequence, actual: event.sequenceNumber)
            }

            let expectedActor = state.sideToMove == .white ? whitePlayerID : blackPlayerID
            guard event.actorPlayerID == expectedActor else {
                throw Error.wrongActor(expected: expectedActor, actual: event.actorPlayerID)
            }

            guard event.previousPositionFingerprint == PositionFingerprinting.fingerprint(for: state) else {
                throw Error.previousFingerprintMismatch
            }

            let move = try RemoteMoveCodec.decode(event.move)
            guard LegalMoveGenerator.allLegalMoves(in: state).contains(move) else {
                throw Error.illegalMove(move)
            }

            state.apply(move)

            guard event.resultingPositionFingerprint == PositionFingerprinting.fingerprint(for: state) else {
                throw Error.resultingFingerprintMismatch
            }

            expectedSequence += 1
        }

        return ApplyResult(state: state, lastAppliedSequence: expectedSequence - 1)
    }
}
```

- [ ] **Step 4: Run move-log tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteMoveLogTests
```

Expected: `RemoteMoveLogTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteMoveLog.swift ChessTutorTests/Remote/RemoteMoveLogTests.swift
git commit -m "Add remote move log validation"
```

## Task 4: Remote Outbox

**Files:**
- Create: `ChessTutor/Remote/RemoteOutbox.swift`
- Test: `ChessTutorTests/Remote/RemoteOutboxTests.swift`

- [ ] **Step 1: Write failing outbox tests**

Create `ChessTutorTests/Remote/RemoteOutboxTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class RemoteOutboxTests: XCTestCase {
    func testStartsWithPendingEvent() {
        let event = makeEvent(sequence: 1)
        let outbox = RemoteOutbox(events: [event])

        XCTAssertEqual(outbox.items, [RemoteOutboxItem(event: event, state: .pendingUpload)])
    }

    func testMarksMatchingAckUploaded() throws {
        let event = makeEvent(sequence: 1)
        var outbox = RemoteOutbox(events: [event])

        try outbox.markUploaded(RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber))

        XCTAssertEqual(outbox.items.first?.state, .uploaded)
    }

    func testRejectsMismatchedAck() {
        let event = makeEvent(sequence: 1)
        var outbox = RemoteOutbox(events: [event])

        XCTAssertThrowsError(try outbox.markUploaded(RemoteMoveAck(
            eventID: RemoteMoveEventID(rawValue: "other"),
            gameID: event.gameID,
            sequenceNumber: event.sequenceNumber
        ))) { error in
            XCTAssertEqual(error as? RemoteOutbox.Error, .missingEvent(RemoteMoveEventID(rawValue: "other")))
        }
    }

    private func makeEvent(sequence: Int) -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: RemoteGameID(rawValue: "game"),
            sequenceNumber: sequence,
            actorPlayerID: RemotePlayerID(rawValue: "white"),
            move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprint(rawValue: "before"),
            resultingPositionFingerprint: PositionFingerprint(rawValue: "after"),
            notificationSummary: "White pawn to e4"
        )
    }
}
```

- [ ] **Step 2: Run outbox tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteOutboxTests
```

Expected: fails because `RemoteOutbox` does not exist.

- [ ] **Step 3: Add outbox implementation**

Create `ChessTutor/Remote/RemoteOutbox.swift`:

```swift
struct RemoteOutboxItem: Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case pendingUpload
        case uploading
        case uploaded
        case failedRetrying
        case offlineQueued
    }

    let event: RemoteMoveEvent
    var state: State
}

struct RemoteOutbox: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case missingEvent(RemoteMoveEventID)
        case mismatchedAck
    }

    private(set) var items: [RemoteOutboxItem]

    init(events: [RemoteMoveEvent] = []) {
        self.items = events.map { RemoteOutboxItem(event: $0, state: .pendingUpload) }
    }

    mutating func append(_ event: RemoteMoveEvent) {
        items.append(RemoteOutboxItem(event: event, state: .pendingUpload))
    }

    mutating func markUploading(_ eventID: RemoteMoveEventID) throws {
        try update(eventID) { item in
            item.state = .uploading
        }
    }

    mutating func markUploaded(_ ack: RemoteMoveAck) throws {
        try update(ack.eventID) { item in
            guard item.event.gameID == ack.gameID,
                  item.event.sequenceNumber == ack.sequenceNumber else {
                throw Error.mismatchedAck
            }
            item.state = .uploaded
        }
    }

    var pendingEvents: [RemoteMoveEvent] {
        items.compactMap { item in
            switch item.state {
            case .pendingUpload, .failedRetrying, .offlineQueued:
                return item.event
            case .uploading, .uploaded:
                return nil
            }
        }
    }

    private mutating func update(
        _ eventID: RemoteMoveEventID,
        mutate: (inout RemoteOutboxItem) throws -> Void
    ) throws {
        guard let index = items.firstIndex(where: { $0.event.id == eventID }) else {
            throw Error.missingEvent(eventID)
        }
        try mutate(&items[index])
    }
}
```

- [ ] **Step 4: Run outbox tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/RemoteOutboxTests
```

Expected: `RemoteOutboxTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteOutbox.swift ChessTutorTests/Remote/RemoteOutboxTests.swift
git commit -m "Add remote move outbox"
```

## Task 5: Transport Protocol And In-Memory Fake

**Files:**
- Create: `ChessTutor/Remote/RemoteGameTransport.swift`
- Test: `ChessTutorTests/Remote/InMemoryRemoteGameTransportTests.swift`

- [ ] **Step 1: Write failing fake transport tests**

Create `ChessTutorTests/Remote/InMemoryRemoteGameTransportTests.swift`:

```swift
import XCTest
@testable import ChessTutor

final class InMemoryRemoteGameTransportTests: XCTestCase {
    func testSendMoveStoresMoveAndReturnsAck() async throws {
        let transport = InMemoryRemoteGameTransport()
        let event = makeEvent(sequence: 1)

        let ack = try await transport.sendMove(event)
        let fetched = try await transport.fetchMoves(gameID: event.gameID, after: 0)

        XCTAssertEqual(ack, RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: 1))
        XCTAssertEqual(fetched, [event])
    }

    func testFetchMovesOnlyReturnsEventsAfterSequence() async throws {
        let transport = InMemoryRemoteGameTransport()
        let first = makeEvent(sequence: 1)
        let second = makeEvent(sequence: 2)
        _ = try await transport.sendMove(first)
        _ = try await transport.sendMove(second)

        let fetched = try await transport.fetchMoves(gameID: first.gameID, after: 1)

        XCTAssertEqual(fetched, [second])
    }

    private func makeEvent(sequence: Int) -> RemoteMoveEvent {
        RemoteMoveEvent(
            id: RemoteMoveEventID(rawValue: "event-\(sequence)"),
            gameID: RemoteGameID(rawValue: "game"),
            sequenceNumber: sequence,
            actorPlayerID: RemotePlayerID(rawValue: "player"),
            move: RemoteMoveCodec.encode(Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4))),
            createdAt: Date(timeIntervalSince1970: Double(sequence)),
            protocolVersion: 1,
            previousPositionFingerprint: PositionFingerprint(rawValue: "before-\(sequence)"),
            resultingPositionFingerprint: PositionFingerprint(rawValue: "after-\(sequence)"),
            notificationSummary: "Move \(sequence)"
        )
    }
}
```

- [ ] **Step 2: Run fake transport tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/InMemoryRemoteGameTransportTests
```

Expected: fails because `InMemoryRemoteGameTransport` and `RemoteGameTransport` do not exist.

- [ ] **Step 3: Add transport protocol and fake**

Create `ChessTutor/Remote/RemoteGameTransport.swift`:

```swift
protocol RemoteGameTransport {
    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck
    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent]
}

actor InMemoryRemoteGameTransport: RemoteGameTransport {
    private var eventsByGame: [RemoteGameID: [RemoteMoveEvent]] = [:]

    func sendMove(_ event: RemoteMoveEvent) async throws -> RemoteMoveAck {
        var events = eventsByGame[event.gameID, default: []]
        if let existing = events.first(where: { $0.sequenceNumber == event.sequenceNumber }) {
            if existing == event {
                return RemoteMoveAck(
                    eventID: existing.id,
                    gameID: existing.gameID,
                    sequenceNumber: existing.sequenceNumber
                )
            }
            throw InMemoryRemoteGameTransportError.conflictingSequence(event.sequenceNumber)
        }

        events.append(event)
        events.sort { $0.sequenceNumber < $1.sequenceNumber }
        eventsByGame[event.gameID] = events
        return RemoteMoveAck(eventID: event.id, gameID: event.gameID, sequenceNumber: event.sequenceNumber)
    }

    func fetchMoves(gameID: RemoteGameID, after sequenceNumber: Int) async throws -> [RemoteMoveEvent] {
        eventsByGame[gameID, default: []]
            .filter { $0.sequenceNumber > sequenceNumber }
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
    }
}

enum InMemoryRemoteGameTransportError: Swift.Error, Equatable {
    case conflictingSequence(Int)
}
```

- [ ] **Step 4: Run fake transport tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/InMemoryRemoteGameTransportTests
```

Expected: `InMemoryRemoteGameTransportTests` pass.

- [ ] **Step 5: Commit**

```bash
git add ChessTutor/Remote/RemoteGameTransport.swift ChessTutorTests/Remote/InMemoryRemoteGameTransportTests.swift
git commit -m "Add remote game transport boundary"
```

## Task 6: GameSession Remote Turn Hooks

**Files:**
- Modify: `ChessTutor/Game/PlayerSeat.swift`
- Modify: `ChessTutor/Game/GameSession.swift`
- Test: `ChessTutorTests/Game/GameSessionTests.swift`

- [ ] **Step 1: Write failing GameSession tests**

Append these tests to `ChessTutorTests/Game/GameSessionTests.swift`:

```swift
func testRemotePlayerPieceCanBeInspectedWithoutMoveAffordances() {
    let session = GameSession()
    session.whitePlayer = .remote(playerID: "maya")

    session.select(Square(file: .e, rank: 2))

    XCTAssertEqual(session.selectedPieceInfo?.title, "White pawn")
    XCTAssertTrue(session.legalDestinations.isEmpty)
    XCTAssertNil(session.message)
}

func testRemotePlayerCannotMovePieceOnTheirTurn() {
    let session = GameSession()
    session.whitePlayer = .remote(playerID: "maya")

    session.select(Square(file: .e, rank: 2))
    let result = session.moveSelectedPiece(to: Square(file: .e, rank: 4))

    XCTAssertEqual(result, .illegal("It's not your turn."))
    XCTAssertEqual(session.message, "It's not your turn.")
}

func testFinishTurnReturnsCommittedMove() {
    let session = GameSession()

    session.select(Square(file: .e, rank: 2))
    _ = session.moveSelectedPiece(to: Square(file: .e, rank: 4))
    let committedMove = session.finishTurn()

    XCTAssertEqual(committedMove, Move(from: Square(file: .e, rank: 2), to: Square(file: .e, rank: 4)))
}
```

- [ ] **Step 2: Run GameSession tests and verify they fail**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests
```

Expected: fails because `PlayerSeat.remote` does not exist and `finishTurn` returns `Void`.

- [ ] **Step 3: Add remote player seats**

Modify `ChessTutor/Game/PlayerSeat.swift`:

```swift
enum PlayerSeat: Equatable, Sendable {
    case humanLocal
    case remote(playerID: String)

    var isLocal: Bool {
        self == .humanLocal
    }
}
```

- [ ] **Step 4: Add local-turn checks and committed move return**

Modify `GameSession`:

```swift
var localCanActForCurrentTurn: Bool {
    playerSeat(for: committedState.sideToMove).isLocal
}

private func playerSeat(for color: PieceColor) -> PlayerSeat {
    switch color {
    case .white:
        return whitePlayer
    case .black:
        return blackPlayer
    }
}
```

Update `select(_:)` so selecting a current-side remote piece keeps inspection but clears move affordances:

```swift
guard state.board[square]?.color == committedState.sideToMove else {
    selectedSquare = square
    legalMovesForSelection = []
    message = nil
    return
}

selectedSquare = square
legalMovesForSelection = assistSettings.showLegalMovesOnSelection && localCanActForCurrentTurn
    ? allowedMoves(forSelectionAt: square)
    : []
message = nil
```

Update `moveSelectedPiece(to:)` before computing allowed moves:

```swift
guard localCanActForCurrentTurn else {
    message = "It's not your turn."
    return .illegal("It's not your turn.")
}
```

Change `finishTurn` to return the committed move:

```swift
@discardableResult
func finishTurn() -> Move? {
    guard let tentativeMove else {
        message = "Make a move first."
        return nil
    }
    guard isLegal(tentativeMove) else {
        message = checkRuleViolationMessage
        return nil
    }

    if let capturedPiece = capturedPiece(for: tentativeMove, in: committedState) {
        committedCapturedPieces.append(
            CapturedPiece(
                id: capturedID(for: capturedPiece.piece, at: capturedPiece.square),
                piece: capturedPiece.piece,
                capturedAt: capturedPiece.square,
                state: .committed
            )
        )
    }
    committedState.apply(tentativeMove)
    self.tentativeMove = nil
    selectedSquare = nil
    legalMovesForSelection = []
    message = committedState.result == .ongoing ? nil : statusText
    return tentativeMove
}
```

- [ ] **Step 5: Run GameSession tests and verify they pass**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)' -only-testing:ChessTutorTests/GameSessionTests
```

Expected: `GameSessionTests` pass.

- [ ] **Step 6: Commit**

```bash
git add ChessTutor/Game/PlayerSeat.swift ChessTutor/Game/GameSession.swift ChessTutorTests/Game/GameSessionTests.swift
git commit -m "Add remote turn hooks to game session"
```

## Task 7: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
xcodebuild test -scheme ChessTutor -destination 'platform=iOS Simulator,name=iPad (A16)'
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Check formatting and tracked changes**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` exits 0. `git status --short` shows only intentional tracked changes before the final commit, or a clean tree after the final commit.

- [ ] **Step 3: Confirm architecture constraints**

Run:

```bash
rg "import CloudKit" ChessTutor/Remote ChessTutor/Game ChessTutor/Core
```

Expected: no matches. CloudKit is not part of this foundation slice.

- [ ] **Step 4: Commit any verification-only cleanup**

If the previous tasks already committed all changes and the tree is clean, skip this step. If a small cleanup is needed, commit it:

```bash
git add ChessTutor ChessTutorTests
git commit -m "Verify remote transport foundation"
```

## Handoff After This Plan

After this plan is implemented, the next plan should choose one of these follow-up slices:

1. `RemoteGameCoordinator` using the fake transport and in-memory state.
2. Codable file persistence for local player, known players, active game, move log, and outbox.
3. CloudKit adapter for accepted CKShare game records.
4. Product UI for `Play Remotely`, invite modal, and known-player flow.

The recommended next slice is `RemoteGameCoordinator` with fake transport. It connects the foundation pieces without introducing CloudKit or UI complexity.
