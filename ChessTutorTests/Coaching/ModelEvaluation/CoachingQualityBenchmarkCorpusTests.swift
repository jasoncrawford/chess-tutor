import CryptoKit
import Foundation
import XCTest
@testable import ChessTutor

/// A diagnostic replay of a real playthrough, separate from the frozen benchmark.
final class CoachingPlaythroughRegressionTests: XCTestCase {
    private struct Turn: Encodable {
        let id: String
        let group: String
        let step: Int
        let request: ModelCoachingNeutralRequest
    }

    func testPlaythroughFactsAndOptInExport() throws {
        let history = ["e2e4", "e7e5", "f1c4", "g8f6", "d2d3", "b8c6", "g1f3", "d7d6"]
        typealias Step = (ModelCoachingLearnerEventKind, [String], String?, String?)
        let episodes: [(String, Int, [Step])] = [
            ("opening", 0, [
                (.helpOpened, [], nil, nil),
                (.moveStaged, ["move:h2-h3"], "h3", "h2h3"),
                (.moveRemoved, ["move:h2-h3"], "e2", nil),
                (.moveStaged, ["move:e2-e4"], "e4", "e2e4"),
            ]),
            ("bishop", 2, [
                (.helpOpened, [], nil, nil),
                (.moveStaged, ["move:f1-c4"], "c4", "f1c4"),
            ]),
            ("danger", 4, [
                (.helpOpened, [], nil, nil),
                (.pieceSelected, ["piece:white:pawn:d2"], "d2", nil),
                (.pieceSelected, ["piece:white:pawn:e4"], "e4", nil),
                (.moveStaged, ["move:c4-f7"], "f7", "c4f7"),
                (.actionChosen, ["action:looksSafe"], "f7", "c4f7"),
                (.moveRemoved, ["move:c4-f7"], nil, nil),
                (.actionChosen, ["action:hint"], nil, nil),
                (.moveStaged, ["move:d2-d3"], "d3", "d2d3"),
            ]),
            ("black-knight", 5, [
                (.helpOpened, [], nil, nil),
                (.moveStaged, ["move:b8-c6"], "c6", "b8c6"),
            ]),
            ("white-knight", 6, [
                (.helpOpened, [], nil, nil),
                (.moveStaged, ["move:g1-f3"], "f3", "g1f3"),
            ]),
            ("castling", 8, [
                (.helpOpened, [], nil, nil),
                (.moveStaged, ["move:e1-g1:castle-kingside"], "g1", "e1g1"),
            ]),
        ]
        var turns: [Turn] = []
        for (group, plies, steps) in episodes {
            var state = GameState.startingPosition()
            for canonical in history.prefix(plies) {
                state.apply(try legalMove(canonical, in: state))
            }
            var events: [ModelCoachingNeutralEpisodeEvent] = []
            for (index, step) in steps.enumerated() {
                let event = ModelCoachingNeutralEpisodeEvent(
                    sequence: index + 1, kind: step.0, referencedIDs: step.1
                )
                events.append(event)
                let id = "\(group)-\(index + 1)"
                let snapshot = ModelCoachingNeutralSnapshot(
                    committedState: state,
                    learner: state.sideToMove,
                    positionRevision: plies,
                    selectedSquare: step.2.map(square),
                    tentativeMove: try step.3.map { try legalMove($0, in: state) },
                    latestEvent: event,
                    episodeEvents: events
                )
                let request = ModelCoachingNeutralRequestBuilder.build(
                    snapshot: snapshot, requestID: "playthrough:\(id)"
                )
                XCTAssertEqual(request.gameHistory.map(\.canonicalMove), Array(history.prefix(plies)))
                XCTAssertEqual(request.interaction.latestEvent, event)
                turns.append(Turn(id: id, group: group, step: index + 1, request: request))
            }
        }

        // Independent chess oracles: do not grade a model against its own explanation.
        var protected = GameState.startingPosition()
        for canonical in history.prefix(5) {
            protected.apply(try legalMove(canonical, in: protected))
        }
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("d3"), in: protected).contains(square("e4")))
        XCTAssertFalse(LegalMoveGenerator.controlledSquares(from: square("e4"), in: protected).contains(square("d3")))
        let losingCapture = try XCTUnwrap(turns.first { $0.id == "danger-4" })
        XCTAssertTrue(losingCapture.request.tentativeReplies.contains { $0.canonicalMove == "e8f7" })
        XCTAssertEqual(turns.first { $0.id == "danger-8" }?.request.interaction.tentativeMove?.canonicalMove, "d2d3")
        XCTAssertEqual(turns.first { $0.id == "castling-2" }?.request.interaction.tentativeMove?.san, "O-O")
        XCTAssertEqual(turns.count, 20)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(turns)
        if let directory = ProcessInfo.processInfo.environment["COACHING_PLAYTHROUGH_OUTPUT_DIR"] {
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("requests.json")
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "Do not overwrite retained evidence")
            try data.write(to: destination, options: .withoutOverwriting)
        }
    }

    private func legalMove(_ canonical: String, in state: GameState) throws -> Move {
        try XCTUnwrap(LegalMoveGenerator.allLegalMoves(in: state).first {
            ModelCoachingPositionEncoder.canonicalMove($0) == canonical
        }, "History and staged moves must be legal: \(canonical)")
    }

    private func square(_ name: String) -> Square {
        let bytes = Array(name.utf8)
        return Square(file: Square.File(rawValue: Int(bytes[0]) - 96)!, rank: Int(bytes[1]) - 48)
    }
}

final class CoachingQualityBenchmarkCorpusTests: XCTestCase {
    func testOptInExport() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["COACHING_QUALITY_BENCHMARK_OUTPUT_DIR"],
              !outputPath.isEmpty else {
            return
        }
        let sourceSHA = try XCTUnwrap(
            environment["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"],
            "Opt-in benchmark export requires a source SHA"
        )
        XCTAssertFalse(sourceSHA.isEmpty)
        try CoachingQualityBenchmarkExporter.write(
            to: URL(fileURLWithPath: outputPath, isDirectory: true),
            sourceGitSHA: sourceSHA
        )
    }

    func testV1HasExactIndependentSequenceAndSplitCounts() {
        let corpus = CoachingQualityBenchmarkCorpus.v1

        XCTAssertEqual(corpus.independent.count, 40)
        XCTAssertEqual(corpus.sequences.count, 10)
        XCTAssertEqual(corpus.sequences.flatMap(\.steps).count, 30)
        XCTAssertEqual(corpus.developmentTurns.count, 56)
        XCTAssertEqual(corpus.holdoutTurns.count, 14)
    }

    func testExportIsDeterministicAndOracleNeverEntersModelFacingCompilation() throws {
        let first = try CoachingQualityBenchmarkExporter.artifacts(
            sourceGitSHA: "deterministic-source"
        )
        let second = try CoachingQualityBenchmarkExporter.artifacts(
            sourceGitSHA: "deterministic-source"
        )
        XCTAssertEqual(first, second)

        for record in try decodeCases(first.casesJSONL) {
            let compilation = ModelCoachingChessNativeContextCompiler.compile(
                record.request,
                promptVersion: "tutor-v13"
            ).markdown
            let graderOnlyText = record.graderBrief.successCriteria
                + record.graderBrief.severeFailureCriteria
            for phrase in graderOnlyText where !phrase.isEmpty {
                XCTAssertFalse(
                    compilation.localizedCaseInsensitiveContains(phrase),
                    "\(record.id): leaked grader-only phrase: \(phrase)"
                )
            }
        }
    }

    func testV1UsesTheApprovedGroupInventoryAndBroadPositionCoverage() {
        let corpus = CoachingQualityBenchmarkCorpus.v1
        XCTAssertEqual(corpus.independent.map(\.groupID), Self.independentIDs)
        XCTAssertEqual(corpus.sequences.map(\.id), Self.sequenceIDs)
        XCTAssertEqual(Set(corpus.allTurns.map(\.id)).count, 70)
        XCTAssertEqual(Set(corpus.independent.map { fen(for: $0.snapshot.committedState) }).count, 25)
        XCTAssertEqual(
            Set(corpus.allTurns.map(\.category)),
            Set([.quiet, .danger, .capture, .tentativeMove, .interaction, .specialRule])
        )
    }

    func testSequenceStepsExpressTheApprovedInteractionProgressions() {
        let sequences = Dictionary(uniqueKeysWithValues: CoachingQualityBenchmarkCorpus.v1.sequences.map {
            ($0.id, $0.steps.map { $0.snapshot.latestEvent.kind })
        })
        let expected: [String: [ModelCoachingLearnerEventKind]] = [
            "s01-danger-selection-response": [.helpOpened, .pieceSelected, .moveStaged],
            "s02-danger-negative-answer": [.helpOpened, .actionChosen, .moveStaged],
            "s03-capture-none": [.helpOpened, .actionChosen, .moveStaged],
            "s04-safe-move-confirm": [.helpOpened, .moveStaged, .actionChosen],
            "s05-unsafe-move-retry": [.helpOpened, .moveStaged, .actionChosen],
            "s06-replace-move": [.helpOpened, .moveStaged, .moveReplaced],
            "s07-inspect-reply": [.helpOpened, .moveStaged, .squareInspected],
            "s08-hint-then-act": [.helpOpened, .actionChosen, .moveStaged],
            "s09-remove-and-stage": [.helpOpened, .moveStaged, .moveRemoved],
            "s10-close-and-reopen": [.helpOpened, .helpClosed, .helpReopened],
        ]
        XCTAssertEqual(sequences, expected)
        for sequence in CoachingQualityBenchmarkCorpus.v1.sequences {
            XCTAssertEqual(sequence.steps.map(\.stepIndex), [1, 2, 3], sequence.id)
            XCTAssertEqual(sequence.steps.map { $0.snapshot.episodeEvents.count }, [1, 2, 3], sequence.id)
        }
    }

    func testEveryHistoryReplaysLegallyAndEveryGraderBriefIsSubstantive() throws {
        for record in try decodeCases(
            CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "source").casesJSONL
        ) {
            var state = GameState.startingPosition()
            for historyMove in record.request.gameHistory {
                let legalMove = try XCTUnwrap(
                    LegalMoveGenerator.allLegalMoves(in: state).first {
                        ModelCoachingPositionEncoder.canonicalMove($0) == historyMove.canonicalMove
                    },
                    "\(record.id): illegal history move \(historyMove.canonicalMove)"
                )
                state.apply(legalMove)
            }
            XCTAssertEqual(fen(for: state), record.request.position.fen, record.id)
            XCTAssertEqual(record.request.positionRevision, record.request.gameHistory.count, record.id)
            XCTAssertGreaterThanOrEqual(record.graderBrief.verifiedFacts.count, 3, record.id)
            XCTAssertFalse(record.graderBrief.coachingPurpose.isEmpty, record.id)
            XCTAssertFalse(record.graderBrief.successCriteria.isEmpty, record.id)
            XCTAssertFalse(record.graderBrief.severeFailureCriteria.isEmpty, record.id)
            XCTAssertFalse(
                record.graderBrief.verifiedFacts.joined().localizedCaseInsensitiveContains("grader"),
                record.id
            )
        }
    }

    func testEveryRequestReferenceResolvesAndInitialPromptCompiles() throws {
        for record in try decodeCases(
            CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "source").casesJSONL
        ) {
            let request = record.request
            let knownReferences = Set(request.pieces.map(\.id))
                .union(request.legalMoves.map(\.id))
                .union(request.tentativeReplies.map(\.id))
                .union(request.interaction.tentativeMove.map { [$0.id] } ?? [])
            for episodeEvent in request.interaction.episodeEvents {
                for reference in episodeEvent.referencedIDs {
                    XCTAssertTrue(
                        reference.hasPrefix("action:") || knownReferences.contains(reference),
                        "\(record.id): unresolved event reference \(reference)"
                    )
                }
            }
            if let tentative = request.interaction.tentativeMove {
                XCTAssertTrue(tentative.isLegal, record.id)
                XCTAssertTrue(
                    request.legalMoves.contains { $0.id == tentative.id },
                    "\(record.id): tentative move is absent from legal moves"
                )
            }
            let initial = ModelCoachingChessNativeContextCompiler.compile(
                request,
                promptVersion: "tutor-v13"
            )
            XCTAssertFalse(initial.markdown.isEmpty, record.id)
        }
    }

    func testManifestBindsExactCaseBytesAndWriterRefusesOverwrite() throws {
        let artifacts = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "abc123")
        let manifest = try JSONDecoder().decode(
            CoachingQualityBenchmarkManifest.self,
            from: artifacts.manifestJSON
        )
        XCTAssertEqual(manifest.schemaVersion, "coaching-quality-benchmark-manifest.v1")
        XCTAssertEqual(manifest.sourceGitSHA, "abc123")
        XCTAssertEqual(manifest.independentGroupCount, 40)
        XCTAssertEqual(manifest.sequenceGroupCount, 10)
        XCTAssertEqual(manifest.turnCount, 70)
        XCTAssertEqual(manifest.developmentTurnCount, 56)
        XCTAssertEqual(manifest.holdoutTurnCount, 14)
        XCTAssertEqual(manifest.casesSHA256, sha256(artifacts.casesJSONL))

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }
        try CoachingQualityBenchmarkExporter.write(to: output, sourceGitSHA: "abc123")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: output.path).sorted(),
            ["benchmark-manifest.json", "cases.jsonl"]
        )
        XCTAssertThrowsError(
            try CoachingQualityBenchmarkExporter.write(to: output, sourceGitSHA: "abc123")
        ) { error in
            XCTAssertEqual(
                error as? CoachingQualityBenchmarkExportError,
                .nonemptyOutputDirectory
            )
        }
    }

    private func decodeCases(
        _ data: Data
    ) throws -> [CoachingQualityBenchmarkCaseRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map {
                try JSONDecoder().decode(
                    CoachingQualityBenchmarkCaseRecord.self,
                    from: Data($0.utf8)
                )
            }
    }

    private func fen(for state: GameState) -> String {
        ModelCoachingPositionEncoder.fen(for: state)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let independentIDs = [
        "q01-starting-position", "q02-quiet-midgame", "q03-quiet-castling",
        "d01-loose-bishop", "d02-defended-knight", "d03-recapturable-pawn",
        "d04-pinned-knight", "d05-answering-check", "d06-apparent-danger",
        "d07-two-dangers", "c01-safe-queen-capture", "c02-poisoned-bishop-capture",
        "c03-equal-exchange", "c04-no-safe-capture", "c05-mating-capture",
        "c06-en-passant", "m01-safe-development", "m02-ignored-danger",
        "m03-harmless-check-trade", "m04-replaced-knight", "m05-removed-move",
        "m06-promotion", "m07-castling", "m08-discovered-check",
        "i01-selected-attacked-piece", "i02-selected-blocked-rook",
        "i03-inspected-losing-queen", "i04-opening-hint", "i05-no-piece-needs-help",
        "i06-no-safe-capture", "i07-looks-safe", "i08-try-another-move",
        "h01-quiet-black-opening", "h02-defended-pawn", "h03-double-check",
        "h04-castling-check", "h05-stale-selection-replaced",
        "h06-benign-capture-safety", "h07-ambiguous-equal-trade", "h08-mate-in-one",
    ]

    private static let sequenceIDs = [
        "s01-danger-selection-response", "s02-danger-negative-answer",
        "s03-capture-none", "s04-safe-move-confirm", "s05-unsafe-move-retry",
        "s06-replace-move", "s07-inspect-reply", "s08-hint-then-act",
        "s09-remove-and-stage", "s10-close-and-reopen",
    ]
}
