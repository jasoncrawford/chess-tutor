import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingChessNativeBroadEvaluationTests: XCTestCase {
    private let expectedIDs = [
        "b01-quiet-midgame-help",
        "b02-loose-bishop-danger",
        "b03-defended-knight",
        "b04-safe-queen-capture",
        "b05-poisoned-bishop-capture",
        "b06-equal-bishop-knight-exchange",
        "b07-pinned-knight-selection",
        "b08-safe-development",
        "b09-ignored-bishop-danger",
        "b10-harmless-check-trade",
        "b11-inspected-losing-queen-capture",
        "b12-replaced-knight-move",
        "b13-recapturable-pawn",
    ]

    func testBroadFixturesHaveExactOrderAndDistinctPositions() throws {
        let fixtures = ModelCoachingChessNativeBroadEvaluationExamples.fixtures
        let broadFENs = Set(fixtures.map { fen(for: $0.snapshot.committedState) })
        let canonicalFENs = Set(ModelCoachingNeutralPromptExamples.fixtures.map {
            fen(for: $0.snapshot.committedState)
        })

        XCTAssertEqual(fixtures.map(\.id), expectedIDs)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, expectedIDs.count)
        XCTAssertTrue(fixtures.allSatisfy { $0.visibility == .visible })
        XCTAssertEqual(broadFENs.count, expectedIDs.count)
        XCTAssertTrue(broadFENs.isDisjoint(with: canonicalFENs))
    }

    func testArtifactsAreDeterministicAndBoundToProductionCompilations() throws {
        let first = try ModelCoachingChessNativeBroadEvaluationExporter.artifacts()
        let second = try ModelCoachingChessNativeBroadEvaluationExporter.artifacts()
        let records = try decodeRecords(first.examplesJSONL)

        XCTAssertEqual(first, second)
        XCTAssertEqual(records.map(\.id), expectedIDs)
        XCTAssertEqual(first.userPrompts.keys.sorted(), expectedIDs.map { "\($0).md" })

        for (fixture, record) in zip(
            ModelCoachingChessNativeBroadEvaluationExamples.fixtures,
            records
        ) {
            let request = ModelCoachingNeutralRequestBuilder.build(
                snapshot: fixture.snapshot,
                requestID: fixture.id
            )
            let compilation = ModelCoachingChessNativeContextCompiler.compile(
                request,
                promptVersion: "tutor-v6"
            )
            XCTAssertEqual(record.request, request, fixture.id)
            XCTAssertEqual(record.compilation, compilation, fixture.id)
            XCTAssertEqual(
                first.userPrompts[fixture.fileName],
                Data(compilation.markdown.utf8),
                fixture.id
            )
        }
    }

    func testEveryCommittedHistoryReplaysLegallyToExportedFEN() throws {
        let records = try decodeRecords(
            ModelCoachingChessNativeBroadEvaluationExporter.artifacts().examplesJSONL
        )

        for record in records {
            var state = GameState.startingPosition()
            for historyMove in record.request.gameHistory {
                let move = try XCTUnwrap(
                    LegalMoveGenerator.allLegalMoves(in: state).first {
                        ModelCoachingPositionEncoder.canonicalMove($0)
                            == historyMove.canonicalMove
                    },
                    "\(record.id): illegal history move \(historyMove.canonicalMove)"
                )
                state.apply(move)
            }
            XCTAssertEqual(fen(for: state), record.request.position.fen, record.id)
            XCTAssertEqual(record.request.positionRevision, record.request.gameHistory.count)
        }
    }

    func testBroadCasesExposeExactCurrentInteractionsAndScopedReplies() throws {
        let records = Dictionary(uniqueKeysWithValues: try decodeRecords(
            ModelCoachingChessNativeBroadEvaluationExporter.artifacts().examplesJSONL
        ).map { ($0.id, $0) })

        XCTAssertEqual(records["b01-quiet-midgame-help"]?.request.interaction.latestEvent.kind, .helpOpened)
        XCTAssertEqual(records["b07-pinned-knight-selection"]?.request.interaction.latestEvent.kind, .pieceSelected)
        XCTAssertEqual(records["b07-pinned-knight-selection"]?.request.interaction.selectedSquare, "c3")
        XCTAssertEqual(records["b11-inspected-losing-queen-capture"]?.request.interaction.latestEvent.kind, .squareInspected)
        XCTAssertEqual(
            records["b11-inspected-losing-queen-capture"]?.request.interaction.latestEvent.referencedIDs,
            ["piece:black:queen:f6"]
        )
        XCTAssertEqual(records["b12-replaced-knight-move"]?.request.interaction.latestEvent.kind, .moveReplaced)
        XCTAssertEqual(records["b13-recapturable-pawn"]?.request.interaction.latestEvent.kind, .moveStaged)
        XCTAssertEqual(records["b13-recapturable-pawn"]?.request.interaction.tentativeMove?.canonicalMove, "a2a3")
        let recapturablePawnReplies = records["b13-recapturable-pawn"]?.request.tentativeReplies ?? []
        XCTAssertTrue(recapturablePawnReplies.contains {
            $0.canonicalMove == "f8a3"
                && $0.directRelationships.contains {
                    $0.phase == .afterReply
                        && $0.kind == .attacks
                        && $0.sourcePiece.square == "b2"
                        && $0.targetPiece.square == "a3"
                }
        })

        let expectedReplies: [String: Set<String>] = [
            "b05-poisoned-bishop-capture": ["e8f7"],
            "b06-equal-bishop-knight-exchange": ["b7c6", "d7c6"],
            "b09-ignored-bishop-danger": ["h6g5"],
            "b10-harmless-check-trade": ["b4d2"],
            "b11-inspected-losing-queen-capture": ["f8b4", "f6f3"],
        ]
        for (identifier, replies) in expectedReplies {
            let actual = Set(records[identifier]?.request.tentativeReplies.map(\.canonicalMove) ?? [])
            XCTAssertEqual(actual, replies, identifier)
        }

        let inspectedCompilation = try XCTUnwrap(
            records["b11-inspected-losing-queen-capture"]?.compilation.markdown
        )
        XCTAssertTrue(inspectedCompilation.contains("Matching immediate replies: Qxf3"))
        XCTAssertFalse(inspectedCompilation.contains("Bb4+"))
    }

    func testExportContainsNoAnswerTraceHiddenOrAliasMaterial() throws {
        let artifacts = try ModelCoachingChessNativeBroadEvaluationExporter.artifacts()
        let text = String(decoding: artifacts.examplesJSONL, as: UTF8.self)
            + String(decoding: artifacts.manifestJSON, as: UTF8.self)
            + String(decoding: artifacts.systemPrompt, as: UTF8.self)
            + artifacts.userPrompts.values.map { String(decoding: $0, as: UTF8.self) }.joined()
        let forbidden = [
            #"\b(?:relationship|move|piece|action)-[0-9]+\b"#,
            #"\b(?:oracle|hidden|trace)\b"#,
            #"\"(?:response|output|assistant)[^\"]*\"\s*:"#,
        ]

        for pattern in forbidden {
            XCTAssertNil(text.range(of: pattern, options: [.regularExpression, .caseInsensitive]), pattern)
        }
        for identifier in ModelCoachingNeutralPromptExamples.fixtures.map(\.id) {
            XCTAssertFalse(text.contains(identifier), identifier)
        }
    }

    func testOptInWriterProducesExactPacket() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "COACHING_CHESS_NATIVE_BROAD_PREVIEW_DIR"
        ], !outputPath.isEmpty else {
            return
        }
        let outputURL = outputPath.hasPrefix("/")
            ? URL(fileURLWithPath: outputPath, isDirectory: true)
            : repositoryRoot.appendingPathComponent(outputPath, isDirectory: true)
        let artifacts = try ModelCoachingChessNativeBroadEvaluationExporter.artifacts()

        try ModelCoachingChessNativeBroadEvaluationExporter.write(to: outputURL)

        let expectedPaths = [
            "examples.jsonl",
            "preview-manifest.json",
            "system-prompt.md",
        ] + expectedIDs.map { "user-prompts/\($0).md" }
        XCTAssertEqual(try relativeFilePaths(in: outputURL), expectedPaths.sorted())
        XCTAssertEqual(
            try Data(contentsOf: outputURL.appendingPathComponent("examples.jsonl")),
            artifacts.examplesJSONL
        )
        XCTAssertEqual(
            try Data(contentsOf: outputURL.appendingPathComponent("preview-manifest.json")),
            artifacts.manifestJSON
        )
        for (fileName, expected) in artifacts.userPrompts {
            XCTAssertEqual(
                try Data(contentsOf: outputURL.appendingPathComponent("user-prompts/\(fileName)")),
                expected
            )
        }
    }

    private func decodeRecords(
        _ data: Data
    ) throws -> [ModelCoachingChessNativePromptExampleRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map {
                try JSONDecoder().decode(
                    ModelCoachingChessNativePromptExampleRecord.self,
                    from: Data($0.utf8)
                )
            }
    }

    private func fen(for state: GameState) -> String {
        ModelCoachingPositionEncoder.fen(for: state)
    }

    private func relativeFilePaths(in root: URL) throws -> [String] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        )!
        return try enumerator.compactMap { value -> String? in
            let url = value as! URL
            guard try url.resourceValues(forKeys: keys).isRegularFile == true else {
                return nil
            }
            return String(url.path.dropFirst(root.path.count + 1))
        }.sorted()
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

enum ModelCoachingChessNativeBroadEvaluationExamples {
    static let fixtures: [ModelCoachingNeutralPromptFixture] = [
        fixture(
            id: "b01-quiet-midgame-help",
            history: [
                "e2e4", "e7e5", "g1f3", "b8c6", "f1c4",
                "g8f6", "d2d3", "f8e7", "e1g1", "e8g8",
            ],
            events: [event(1, .helpOpened)]
        ),
        fixture(
            id: "b02-loose-bishop-danger",
            history: ["d2d4", "d7d5", "c1f4", "e7e5"],
            events: [event(1, .helpOpened)]
        ),
        fixture(
            id: "b03-defended-knight",
            history: ["e2e4", "e7e5", "b1c3", "f8b4"],
            events: [event(1, .helpOpened)]
        ),
        fixture(
            id: "b04-safe-queen-capture",
            history: ["e2e4", "e7e5", "g1f3", "d8h4"],
            events: [event(1, .helpOpened)]
        ),
        fixture(
            id: "b05-poisoned-bishop-capture",
            history: ["e2e4", "e7e5", "f1c4", "g8f6"],
            selectedSquare: square("f7"),
            tentativeMove: move("c4", "f7"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("c4", "f7")]),
            ]
        ),
        fixture(
            id: "b06-equal-bishop-knight-exchange",
            history: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"],
            selectedSquare: square("c6"),
            tentativeMove: move("b5", "c6"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("b5", "c6")]),
            ]
        ),
        fixture(
            id: "b07-pinned-knight-selection",
            history: ["e2e4", "e7e5", "b1c3", "f8b4", "d2d3", "g8f6"],
            selectedSquare: square("c3"),
            events: [
                event(1, .helpOpened),
                event(2, .pieceSelected, ["piece:white:knight:c3"]),
            ]
        ),
        fixture(
            id: "b08-safe-development",
            history: ["d2d4", "d7d5", "g1f3", "g8f6"],
            selectedSquare: square("c3"),
            tentativeMove: move("b1", "c3"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("b1", "c3")]),
            ]
        ),
        fixture(
            id: "b09-ignored-bishop-danger",
            history: ["d2d4", "d7d5", "c1g5", "h7h6"],
            selectedSquare: square("a3"),
            tentativeMove: move("a2", "a3"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("a2", "a3")]),
            ]
        ),
        fixture(
            id: "b10-harmless-check-trade",
            history: ["d2d4", "e7e5", "d4e5", "f8b4"],
            selectedSquare: square("d2"),
            tentativeMove: move("c1", "d2"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("c1", "d2")]),
            ]
        ),
        fixture(
            id: "b11-inspected-losing-queen-capture",
            history: ["e2e4", "e7e5", "g1f3", "d8f6"],
            selectedSquare: square("d3"),
            tentativeMove: move("d2", "d3"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("d2", "d3")]),
                event(3, .squareInspected, ["piece:black:queen:f6"]),
            ]
        ),
        fixture(
            id: "b12-replaced-knight-move",
            history: ["g1f3", "d7d5", "f3e5", "f7f6"],
            selectedSquare: square("f3"),
            tentativeMove: move("e5", "f3"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("h2", "h3")]),
                event(3, .moveReplaced, [moveID("e5", "f3")]),
            ]
        ),
        fixture(
            id: "b13-recapturable-pawn",
            history: ["g1f3", "e7e6"],
            selectedSquare: square("a3"),
            tentativeMove: move("a2", "a3"),
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [moveID("a2", "a3")]),
            ]
        ),
    ]

    private static func fixture(
        id: String,
        history: [String],
        selectedSquare: Square? = nil,
        tentativeMove: Move? = nil,
        events: [ModelCoachingNeutralEpisodeEvent]
    ) -> ModelCoachingNeutralPromptFixture {
        ModelCoachingNeutralPromptFixture(
            id: id,
            fileName: "\(id).md",
            visibility: .visible,
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: replaying(history),
                learner: .white,
                positionRevision: history.count,
                selectedSquare: selectedSquare,
                tentativeMove: tentativeMove,
                latestEvent: events.last!,
                episodeEvents: events
            )
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

    private static func moveID(_ from: String, _ to: String) -> String {
        ModelCoachingPositionEncoder.moveID(move(from, to))
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

enum ModelCoachingChessNativeBroadEvaluationExporter {
    static func artifacts() throws -> ModelCoachingChessNativePromptExampleArtifacts {
        try ModelCoachingChessNativePromptArtifactFactory.artifacts(
            fixtures: ModelCoachingChessNativeBroadEvaluationExamples.fixtures
        )
    }

    static func write(to outputURL: URL) throws {
        try ModelCoachingChessNativePromptArtifactFactory.write(
            try artifacts(),
            to: outputURL
        )
    }
}
