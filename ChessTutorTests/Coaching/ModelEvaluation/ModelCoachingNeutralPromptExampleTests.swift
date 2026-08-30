import CryptoKit
import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingNeutralPromptExampleTests: XCTestCase {
    func testFixturesContainExactlyEightProductionShapedVisibleSnapshots() {
        let fixtures = ModelCoachingNeutralPromptExamples.fixtures

        XCTAssertEqual(
            fixtures.map(\.id),
            [
                "01-quiet-help",
                "02-attacked-piece",
                "03-selected-piece",
                "04-replaced-tentative-move",
                "05-tactical-reply",
                "06-inspected-reply",
                "07-answering-check",
                "08-long-history",
            ]
        )
        XCTAssertEqual(Set(fixtures.map(\.id)).count, 8)
        XCTAssertEqual(fixtures.count, 8)
        XCTAssertTrue(fixtures.allSatisfy { $0.visibility == .visible })
        XCTAssertEqual(fixtures.map(\.fileName), fixtures.map { "\($0.id).md" })
        XCTAssertTrue(fixtures.allSatisfy { fixture in
            Set(Mirror(reflecting: fixture).children.compactMap(\.label))
                == ["id", "fileName", "visibility", "snapshot"]
        })

        let requests = fixtures.map {
            ModelCoachingNeutralRequestBuilder.build(snapshot: $0.snapshot, requestID: $0.id)
        }
        XCTAssertEqual(requests[0].position.fen, ModelCoachingPositionEncoder.fen(for: .startingPosition()))
        XCTAssertTrue(requests[1].occupiedSquareRelationships.contains {
            $0.kind == .attacks
                && $0.sourcePieceReference == "piece:black:pawn:e4"
                && $0.targetPieceReference == "piece:white:knight:f3"
        })
        XCTAssertNil(requests[1].interaction.selectedPieceReference)
        XCTAssertEqual(requests[2].interaction.selectedPieceReference, "piece:white:knight:f3")
        XCTAssertEqual(requests[3].interaction.latestEvent.kind, .moveReplaced)
        XCTAssertEqual(requests[3].interaction.tentativeMove?.canonicalMove, "g1f3")
        XCTAssertTrue(requests[4].tentativeReplies.contains { $0.capturePieceReference != nil })
        XCTAssertEqual(requests[5].interaction.latestEvent.kind, .squareInspected)
        XCTAssertEqual(
            requests[5].interaction.latestEvent.referencedIDs,
            ["piece:white:bishop:c4"]
        )
        XCTAssertTrue(
            ModelCoachingNeutralContextCompiler.compile(
                requests[5],
                promptVersion: "tutor-v5"
            ).markdown.contains("Inspected reply:")
        )
        XCTAssertTrue(
            LegalMoveGenerator.isKingInCheck(
                .white,
                in: fixtures[6].snapshot.committedState.board
            )
        )
        XCTAssertEqual(requests[6].interaction.tentativeMove?.canonicalMove, "b5e2")
        XCTAssertEqual(
            requests[7].gameHistory.map(\.displayNotation),
            ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6"]
        )
    }

    func testArtifactsAreDeterministicAndCarryExactRequestCompilationAndHashes() throws {
        let first = try ModelCoachingNeutralPromptExampleExporter.artifacts()
        let second = try ModelCoachingNeutralPromptExampleExporter.artifacts()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.userPrompts.keys.sorted(), ModelCoachingNeutralPromptExamples.fixtures.map(\.fileName))

        let records = try decodeRecords(first.examplesJSONL)
        XCTAssertEqual(records.count, 8)
        XCTAssertEqual(records.map(\.id), ModelCoachingNeutralPromptExamples.fixtures.map(\.id))

        for (fixture, record) in zip(ModelCoachingNeutralPromptExamples.fixtures, records) {
            let expectedRequest = ModelCoachingNeutralRequestBuilder.build(
                snapshot: fixture.snapshot,
                requestID: fixture.id
            )
            let expectedCompilation = ModelCoachingNeutralContextCompiler.compile(
                expectedRequest,
                promptVersion: "tutor-v5"
            )
            let promptData = try XCTUnwrap(first.userPrompts[fixture.fileName])

            XCTAssertEqual(record.visibility, .visible)
            XCTAssertEqual(record.request, expectedRequest)
            XCTAssertEqual(record.compilation, expectedCompilation)
            XCTAssertEqual(promptData, Data(expectedCompilation.markdown.utf8))
            XCTAssertEqual(record.requestSHA256, sha256(try sortedJSON(expectedRequest)))
            XCTAssertEqual(record.userPromptSHA256, sha256(promptData))
        }

        let manifest = try JSONDecoder().decode(
            ModelCoachingNeutralPromptPreviewManifest.self,
            from: first.manifestJSON
        )
        XCTAssertEqual(manifest.schemaVersion, "model-coaching-neutral-preview-manifest.v1")
        XCTAssertEqual(manifest.promptVersion, "tutor-v5")
        XCTAssertEqual(manifest.requestSchemaVersion, "model-coaching-neutral-request.v1")
        XCTAssertEqual(manifest.contextSchemaVersion, "model-coaching-neutral-context.v1")
        XCTAssertEqual(manifest.exampleIDs, records.map(\.id))
        XCTAssertEqual(manifest.systemPromptSHA256, sha256(first.systemPrompt))
        XCTAssertEqual(manifest.examplesJSONLSHA256, sha256(first.examplesJSONL))
        XCTAssertEqual(manifest.examples, records.map {
            ModelCoachingNeutralPromptPreviewManifest.Example(
                id: $0.id,
                fileName: $0.fileName,
                requestSHA256: $0.requestSHA256,
                userPromptSHA256: $0.userPromptSHA256
            )
        })
    }

    func testArtifactsRejectAnInvalidOrHiddenLookingFixtureID() throws {
        let fixture = try XCTUnwrap(ModelCoachingNeutralPromptExamples.fixtures.first)
        let invalid = ModelCoachingNeutralPromptFixture(
            id: "hidden-case",
            fileName: "hidden-case.md",
            visibility: .visible,
            snapshot: fixture.snapshot
        )

        XCTAssertThrowsError(
            try ModelCoachingNeutralPromptExampleExporter.artifacts(fixtures: [invalid])
        ) { error in
            XCTAssertEqual(error as? ModelCoachingNeutralPromptExportError, .invalidFixtureSet)
        }
    }

    func testWriterRefusesToOverwriteNonemptyDirectory() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("neutral-prompt-preview-nonempty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try Data("keep".utf8).write(to: outputURL.appendingPathComponent("existing.txt"))

        XCTAssertThrowsError(
            try ModelCoachingNeutralPromptExampleExporter.write(to: outputURL)
        ) { error in
            XCTAssertEqual(error as? ModelCoachingNeutralPromptExportError, .nonemptyOutputDirectory)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputURL.path), ["existing.txt"])
    }

    func testOptInWriterProducesOnlyDeclaredByteIdenticalFiles() throws {
        let artifacts = try ModelCoachingNeutralPromptExampleExporter.artifacts()
        guard let outputPath = configuredValue(
            "COACHING_NEUTRAL_PREVIEW_DIR",
            in: ProcessInfo.processInfo.environment
        ) else {
            return
        }
        let outputURL = outputPath.hasPrefix("/")
            ? URL(fileURLWithPath: outputPath, isDirectory: true)
            : repositoryRoot.appendingPathComponent(outputPath, isDirectory: true)

        try ModelCoachingNeutralPromptExampleExporter.write(to: outputURL)

        XCTAssertEqual(
            try relativeFilePaths(in: outputURL),
            [
                "examples.jsonl",
                "preview-manifest.json",
                "system-prompt.md",
                "user-prompts/01-quiet-help.md",
                "user-prompts/02-attacked-piece.md",
                "user-prompts/03-selected-piece.md",
                "user-prompts/04-replaced-tentative-move.md",
                "user-prompts/05-tactical-reply.md",
                "user-prompts/06-inspected-reply.md",
                "user-prompts/07-answering-check.md",
                "user-prompts/08-long-history.md",
            ]
        )
        XCTAssertEqual(try Data(contentsOf: outputURL.appendingPathComponent("examples.jsonl")), artifacts.examplesJSONL)
        XCTAssertEqual(
            try Data(contentsOf: outputURL.appendingPathComponent("preview-manifest.json")),
            artifacts.manifestJSON
        )
        XCTAssertEqual(try Data(contentsOf: outputURL.appendingPathComponent("system-prompt.md")), artifacts.systemPrompt)
        for (fileName, expectedData) in artifacts.userPrompts {
            XCTAssertEqual(
                try Data(contentsOf: outputURL.appendingPathComponent("user-prompts/\(fileName)")),
                expectedData
            )
        }
    }

    private func decodeRecords(_ data: Data) throws -> [ModelCoachingNeutralPromptExampleRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(ModelCoachingNeutralPromptExampleRecord.self, from: Data($0.utf8)) }
    }

    private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func configuredValue(_ key: String, in environment: [String: String]) -> String? {
        guard let value = environment[key], !value.isEmpty, !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    private func relativeFilePaths(in directory: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys
        )!
        return try enumerator.compactMap { element -> String? in
            let url = try XCTUnwrap(element as? URL)
            guard try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else {
                return nil
            }
            return String(url.path.dropFirst(directory.path.count + 1))
        }.sorted()
    }

    private func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

enum ModelCoachingNeutralPromptExampleVisibility: String, Codable, Equatable {
    case visible
}

struct ModelCoachingNeutralPromptFixture: Equatable {
    let id: String
    let fileName: String
    let visibility: ModelCoachingNeutralPromptExampleVisibility
    let snapshot: ModelCoachingNeutralSnapshot
}

enum ModelCoachingNeutralPromptExamples {
    static let fixtures: [ModelCoachingNeutralPromptFixture] = [
        fixture(
            id: "01-quiet-help",
            snapshot: snapshot(
                state: .startingPosition(),
                learner: .white,
                positionRevision: 0,
                events: [event(1, .helpOpened)]
            )
        ),
        fixture(
            id: "02-attacked-piece",
            snapshot: snapshot(
                state: attackedKnightState(),
                learner: .white,
                positionRevision: 1,
                events: [event(1, .helpOpened)]
            )
        ),
        fixture(
            id: "03-selected-piece",
            snapshot: snapshot(
                state: attackedKnightState(),
                learner: .white,
                positionRevision: 1,
                selectedSquare: square("f3"),
                events: [
                    event(1, .helpOpened),
                    event(2, .pieceSelected, ["piece:white:knight:f3"]),
                ]
            )
        ),
        fixture(
            id: "04-replaced-tentative-move",
            snapshot: snapshot(
                state: .startingPosition(),
                learner: .white,
                positionRevision: 0,
                selectedSquare: square("f3"),
                tentativeMove: move("g1", "f3"),
                events: [
                    event(1, .helpOpened),
                    event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(move("h2", "h4"))]),
                    event(3, .moveReplaced, [ModelCoachingPositionEncoder.moveID(move("g1", "f3"))]),
                ]
            )
        ),
        fixture(
            id: "05-tactical-reply",
            snapshot: snapshot(
                state: state(
                    sideToMove: .white,
                    pieces: [
                        "g1": Piece(kind: .king, color: .white),
                        "c4": Piece(kind: .bishop, color: .white),
                        "h8": Piece(kind: .king, color: .black),
                        "a6": Piece(kind: .pawn, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 4,
                selectedSquare: square("b5"),
                tentativeMove: move("c4", "b5"),
                events: [
                    event(1, .helpOpened),
                    event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(move("c4", "b5"))]),
                ]
            )
        ),
        fixture(
            id: "06-inspected-reply",
            snapshot: snapshot(
                state: state(
                    sideToMove: .black,
                    pieces: [
                        "g1": Piece(kind: .king, color: .white),
                        "c4": Piece(kind: .bishop, color: .white),
                        "h8": Piece(kind: .king, color: .black),
                        "e7": Piece(kind: .pawn, color: .black),
                    ]
                ),
                learner: .black,
                positionRevision: 5,
                selectedSquare: square("e6"),
                tentativeMove: move("e7", "e6"),
                events: [
                    event(1, .helpOpened),
                    event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(move("e7", "e6"))]),
                    event(3, .squareInspected, ["piece:white:bishop:c4"]),
                ]
            )
        ),
        fixture(
            id: "07-answering-check",
            snapshot: snapshot(
                state: state(
                    sideToMove: .white,
                    pieces: [
                        "e1": Piece(kind: .king, color: .white),
                        "b5": Piece(kind: .bishop, color: .white),
                        "a8": Piece(kind: .king, color: .black),
                        "e8": Piece(kind: .rook, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 6,
                selectedSquare: square("e2"),
                tentativeMove: move("b5", "e2"),
                events: [
                    event(1, .helpOpened),
                    event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(move("b5", "e2"))]),
                ]
            )
        ),
        fixture(
            id: "08-long-history",
            snapshot: snapshot(
                state: replaying([
                    "e2e4", "e7e5", "g1f3", "b8c6",
                    "f1b5", "a7a6", "b5a4", "g8f6",
                ]),
                learner: .white,
                positionRevision: 8,
                events: [event(1, .helpOpened)]
            )
        ),
    ]

    private static func fixture(
        id: String,
        snapshot: ModelCoachingNeutralSnapshot
    ) -> ModelCoachingNeutralPromptFixture {
        ModelCoachingNeutralPromptFixture(
            id: id,
            fileName: "\(id).md",
            visibility: .visible,
            snapshot: snapshot
        )
    }

    private static func snapshot(
        state: GameState,
        learner: PieceColor,
        positionRevision: Int,
        selectedSquare: Square? = nil,
        tentativeMove: Move? = nil,
        events: [ModelCoachingNeutralEpisodeEvent]
    ) -> ModelCoachingNeutralSnapshot {
        ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: learner,
            positionRevision: positionRevision,
            selectedSquare: selectedSquare,
            tentativeMove: tentativeMove,
            latestEvent: events.last!,
            episodeEvents: events
        )
    }

    private static func attackedKnightState() -> GameState {
        state(
            sideToMove: .white,
            pieces: [
                "g1": Piece(kind: .king, color: .white),
                "f3": Piece(kind: .knight, color: .white),
                "h8": Piece(kind: .king, color: .black),
                "e4": Piece(kind: .pawn, color: .black),
            ]
        )
    }

    private static func state(
        sideToMove: PieceColor,
        pieces: [String: Piece]
    ) -> GameState {
        GameState(
            board: Board(pieces: Dictionary(uniqueKeysWithValues: pieces.map { (square($0.key), $0.value) })),
            sideToMove: sideToMove
        )
    }

    private static func replaying(_ canonicalMoves: [String]) -> GameState {
        canonicalMoves.reduce(into: GameState.startingPosition()) { state, canonicalMove in
            let legalMove = LegalMoveGenerator.allLegalMoves(in: state).first {
                ModelCoachingPositionEncoder.canonicalMove($0) == canonicalMove
            }!
            state.apply(legalMove)
        }
    }

    private static func event(
        _ sequence: Int,
        _ kind: ModelCoachingLearnerEventKind,
        _ referencedIDs: [String] = []
    ) -> ModelCoachingNeutralEpisodeEvent {
        ModelCoachingNeutralEpisodeEvent(
            sequence: sequence,
            kind: kind,
            referencedIDs: referencedIDs
        )
    }

    private static func move(_ from: String, _ to: String) -> Move {
        Move(from: square(from), to: square(to))
    }

    private static func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }
}

struct ModelCoachingNeutralPromptExampleRecord: Codable, Equatable {
    let id: String
    let fileName: String
    let visibility: ModelCoachingNeutralPromptExampleVisibility
    let request: ModelCoachingNeutralRequest
    let compilation: ModelCoachingNeutralContextCompilation
    let requestSHA256: String
    let userPromptSHA256: String
}

struct ModelCoachingNeutralPromptPreviewManifest: Codable, Equatable {
    struct Example: Codable, Equatable {
        let id: String
        let fileName: String
        let requestSHA256: String
        let userPromptSHA256: String
    }

    let schemaVersion: String
    let promptVersion: String
    let requestSchemaVersion: String
    let contextSchemaVersion: String
    let exampleIDs: [String]
    let systemPromptSHA256: String
    let examplesJSONLSHA256: String
    let examples: [Example]
}

struct ModelCoachingNeutralPromptExampleArtifacts: Equatable {
    let examplesJSONL: Data
    let manifestJSON: Data
    let systemPrompt: Data
    let userPrompts: [String: Data]
}

enum ModelCoachingNeutralPromptExportError: Error, Equatable {
    case invalidFixtureSet
    case nonemptyOutputDirectory
    case outputPathIsNotDirectory
}

enum ModelCoachingNeutralPromptExampleExporter {
    static func artifacts(
        fixtures: [ModelCoachingNeutralPromptFixture] = ModelCoachingNeutralPromptExamples.fixtures
    ) throws -> ModelCoachingNeutralPromptExampleArtifacts {
        guard fixtures.map(\.id) == ModelCoachingNeutralPromptExamples.fixtures.map(\.id),
              Set(fixtures.map(\.id)).count == 8,
              fixtures.allSatisfy({ $0.visibility == .visible }),
              fixtures.map(\.fileName) == fixtures.map({ "\($0.id).md" }) else {
            throw ModelCoachingNeutralPromptExportError.invalidFixtureSet
        }

        let systemPrompt = try Data(contentsOf: systemPromptURL)
        var records: [ModelCoachingNeutralPromptExampleRecord] = []
        var userPrompts: [String: Data] = [:]

        for fixture in fixtures {
            let request = ModelCoachingNeutralRequestBuilder.build(
                snapshot: fixture.snapshot,
                requestID: fixture.id
            )
            let compilation = ModelCoachingNeutralContextCompiler.compile(
                request,
                promptVersion: "tutor-v5"
            )
            let requestData = try sortedJSON(request)
            let userPrompt = Data(compilation.markdown.utf8)
            let record = ModelCoachingNeutralPromptExampleRecord(
                id: fixture.id,
                fileName: fixture.fileName,
                visibility: fixture.visibility,
                request: request,
                compilation: compilation,
                requestSHA256: sha256(requestData),
                userPromptSHA256: sha256(userPrompt)
            )
            records.append(record)
            userPrompts[fixture.fileName] = userPrompt
        }

        let examplesJSONL = try jsonl(records)
        let manifest = ModelCoachingNeutralPromptPreviewManifest(
            schemaVersion: "model-coaching-neutral-preview-manifest.v1",
            promptVersion: "tutor-v5",
            requestSchemaVersion: "model-coaching-neutral-request.v1",
            contextSchemaVersion: "model-coaching-neutral-context.v1",
            exampleIDs: records.map(\.id),
            systemPromptSHA256: sha256(systemPrompt),
            examplesJSONLSHA256: sha256(examplesJSONL),
            examples: records.map {
                ModelCoachingNeutralPromptPreviewManifest.Example(
                    id: $0.id,
                    fileName: $0.fileName,
                    requestSHA256: $0.requestSHA256,
                    userPromptSHA256: $0.userPromptSHA256
                )
            }
        )
        var manifestJSON = try sortedJSON(manifest)
        manifestJSON.append(0x0A)

        return ModelCoachingNeutralPromptExampleArtifacts(
            examplesJSONL: examplesJSONL,
            manifestJSON: manifestJSON,
            systemPrompt: systemPrompt,
            userPrompts: userPrompts
        )
    }

    static func write(to outputURL: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ModelCoachingNeutralPromptExportError.outputPathIsNotDirectory
            }
            guard try fileManager.contentsOfDirectory(atPath: outputURL.path).isEmpty else {
                throw ModelCoachingNeutralPromptExportError.nonemptyOutputDirectory
            }
        } else {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        let artifacts = try artifacts()
        let userPromptsURL = outputURL.appendingPathComponent("user-prompts", isDirectory: true)
        try fileManager.createDirectory(at: userPromptsURL, withIntermediateDirectories: false)
        try artifacts.examplesJSONL.write(
            to: outputURL.appendingPathComponent("examples.jsonl"),
            options: .atomic
        )
        try artifacts.manifestJSON.write(
            to: outputURL.appendingPathComponent("preview-manifest.json"),
            options: .atomic
        )
        try artifacts.systemPrompt.write(
            to: outputURL.appendingPathComponent("system-prompt.md"),
            options: .atomic
        )
        for (fileName, data) in artifacts.userPrompts.sorted(by: { $0.key < $1.key }) {
            try data.write(to: userPromptsURL.appendingPathComponent(fileName), options: .atomic)
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var systemPromptURL: URL {
        repositoryRoot.appendingPathComponent("Tools/CoachingEval/prompts/tutor-v5.md")
    }

    private static func jsonl<T: Encodable>(_ values: [T]) throws -> Data {
        var data = Data()
        for value in values {
            data.append(try sortedJSON(value))
            data.append(0x0A)
        }
        return data
    }

    private static func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
