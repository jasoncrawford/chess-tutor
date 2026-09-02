import CryptoKit
import Foundation
@testable import ChessTutor

enum CoachingQualityBenchmarkSplit: String, Codable, Equatable {
    case development
    case holdout
}

enum CoachingQualityBenchmarkCategory: String, Codable, Equatable {
    case quiet
    case danger
    case capture
    case tentativeMove
    case interaction
    case specialRule
}

struct CoachingQualityBenchmarkGraderBrief: Codable, Equatable {
    let verifiedFacts: [String]
    let coachingPurpose: String
    let acceptableAlternatives: [String]
    let successCriteria: [String]
    let severeFailureCriteria: [String]
}

struct CoachingQualityBenchmarkTurn: Equatable {
    let id: String
    let groupID: String
    let stepIndex: Int
    let split: CoachingQualityBenchmarkSplit
    let category: CoachingQualityBenchmarkCategory
    let snapshot: ModelCoachingNeutralSnapshot
    let graderBrief: CoachingQualityBenchmarkGraderBrief
    let sourceTraceID: String?
}

struct CoachingQualityBenchmarkSequence: Equatable {
    let id: String
    let split: CoachingQualityBenchmarkSplit
    let steps: [CoachingQualityBenchmarkTurn]
}

struct CoachingQualityBenchmarkCaseRecord: Codable, Equatable {
    let schemaVersion: String
    let id: String
    let groupID: String
    let stepIndex: Int
    let split: CoachingQualityBenchmarkSplit
    let category: CoachingQualityBenchmarkCategory
    let request: ModelCoachingNeutralRequest
    let graderBrief: CoachingQualityBenchmarkGraderBrief
    let sourceTraceID: String?
}

struct CoachingQualityBenchmarkCorpus {
    let independent: [CoachingQualityBenchmarkTurn]
    let sequences: [CoachingQualityBenchmarkSequence]

    var developmentTurns: [CoachingQualityBenchmarkTurn] {
        allTurns.filter { $0.split == .development }
    }

    var holdoutTurns: [CoachingQualityBenchmarkTurn] {
        allTurns.filter { $0.split == .holdout }
    }

    var allTurns: [CoachingQualityBenchmarkTurn] {
        independent + sequences.flatMap(\.steps)
    }

    static let v1 = CoachingQualityBenchmarkCorpus(
        independent: BenchmarkFixtureFactory.independent,
        sequences: BenchmarkFixtureFactory.sequences
    )
}

struct CoachingQualityBenchmarkManifest: Codable, Equatable {
    let schemaVersion: String
    let sourceGitSHA: String
    let independentGroupCount: Int
    let sequenceGroupCount: Int
    let turnCount: Int
    let developmentTurnCount: Int
    let holdoutTurnCount: Int
    let turnIDs: [String]
    let casesSHA256: String
}

struct CoachingQualityBenchmarkArtifacts: Equatable {
    let casesJSONL: Data
    let manifestJSON: Data
}

enum CoachingQualityBenchmarkExportError: Error, Equatable {
    case nonemptyOutputDirectory
    case outputPathIsNotDirectory
}

enum CoachingQualityBenchmarkExporter {
    static func artifacts(sourceGitSHA: String) throws -> CoachingQualityBenchmarkArtifacts {
        let corpus = CoachingQualityBenchmarkCorpus.v1
        let records = corpus.allTurns.map { turn in
            let request = ModelCoachingNeutralRequestBuilder.build(
                snapshot: turn.snapshot,
                requestID: "benchmark:\(turn.id)"
            )
            return CoachingQualityBenchmarkCaseRecord(
                schemaVersion: "coaching-quality-benchmark-case.v1",
                id: turn.id,
                groupID: turn.groupID,
                stepIndex: turn.stepIndex,
                split: turn.split,
                category: turn.category,
                request: request,
                graderBrief: enriched(turn.graderBrief, withFactsFrom: request),
                sourceTraceID: turn.sourceTraceID
            )
        }
        let casesJSONL = try jsonl(records)
        let manifest = CoachingQualityBenchmarkManifest(
            schemaVersion: "coaching-quality-benchmark-manifest.v1",
            sourceGitSHA: sourceGitSHA,
            independentGroupCount: corpus.independent.count,
            sequenceGroupCount: corpus.sequences.count,
            turnCount: records.count,
            developmentTurnCount: corpus.developmentTurns.count,
            holdoutTurnCount: corpus.holdoutTurns.count,
            turnIDs: records.map(\.id),
            casesSHA256: sha256(casesJSONL)
        )
        var manifestJSON = try encoder.encode(manifest)
        manifestJSON.append(0x0A)
        return CoachingQualityBenchmarkArtifacts(
            casesJSONL: casesJSONL,
            manifestJSON: manifestJSON
        )
    }

    static func write(to outputURL: URL, sourceGitSHA: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw CoachingQualityBenchmarkExportError.outputPathIsNotDirectory
            }
            guard try fileManager.contentsOfDirectory(atPath: outputURL.path).isEmpty else {
                throw CoachingQualityBenchmarkExportError.nonemptyOutputDirectory
            }
        }
        let parent = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(
            ".\(outputURL.lastPathComponent).tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: temporary) }
        let artifacts = try artifacts(sourceGitSHA: sourceGitSHA)
        try artifacts.casesJSONL.write(
            to: temporary.appendingPathComponent("cases.jsonl"),
            options: .atomic
        )
        try artifacts.manifestJSON.write(
            to: temporary.appendingPathComponent("benchmark-manifest.json"),
            options: .atomic
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: temporary, to: outputURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func jsonl<T: Encodable>(_ values: [T]) throws -> Data {
        var result = Data()
        for value in values {
            result.append(try encoder.encode(value))
            result.append(0x0A)
        }
        return result
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func enriched(
        _ brief: CoachingQualityBenchmarkGraderBrief,
        withFactsFrom request: ModelCoachingNeutralRequest
    ) -> CoachingQualityBenchmarkGraderBrief {
        let piecesByID = Dictionary(uniqueKeysWithValues: request.pieces.map { ($0.id, $0) })
        let learnerColor = request.position.sideToMove
        let attackedLearnerPieces = Set(request.occupiedSquareRelationships.compactMap {
            relationship -> String? in
            guard relationship.kind == .attacks,
                  let source = piecesByID[relationship.sourcePieceReference],
                  let target = piecesByID[relationship.targetPieceReference],
                  source.color != learnerColor,
                  target.color == learnerColor else {
                return nil
            }
            return "\(target.kind) on \(target.square)"
        }).sorted()
        let legalCaptures = request.legalMoves.filter { $0.capturePieceReference != nil }
        var facts = [
            "Side to move: \(request.position.sideToMove).",
            "Position status: \(request.position.status).",
            "Committed history length: \(request.gameHistory.count) plies.",
            "Latest learner event: \(request.interaction.latestEvent.kind.rawValue).",
            "Legal learner moves: \(request.legalMoves.count).",
            "Legal learner captures: \(legalCaptures.count).",
            attackedLearnerPieces.isEmpty
                ? "Attacked learner pieces: none."
                : "Attacked learner pieces: \(attackedLearnerPieces.joined(separator: ", ")).",
        ]
        if let selected = request.interaction.selectedPieceReference {
            facts.append("Selected piece: \(selected).")
        } else {
            facts.append("Selected piece: none.")
        }
        if let tentative = request.interaction.tentativeMove {
            facts.append(
                "Tentative move: \(tentative.canonicalMove); legal: \(tentative.isLegal)."
            )
            facts.append("Forcing immediate replies: \(request.tentativeReplies.count).")
        } else {
            facts.append("Tentative move: none.")
        }
        return CoachingQualityBenchmarkGraderBrief(
            verifiedFacts: facts,
            coachingPurpose: brief.coachingPurpose,
            acceptableAlternatives: brief.acceptableAlternatives,
            successCriteria: brief.successCriteria,
            severeFailureCriteria: brief.severeFailureCriteria
        )
    }
}

private enum BenchmarkFixtureFactory {
    static let developmentIndependentIDs = [
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
    ]

    static let holdoutIndependentIDs = [
        "h01-quiet-black-opening", "h02-defended-pawn", "h03-double-check",
        "h04-castling-check", "h05-stale-selection-replaced",
        "h06-benign-capture-safety", "h07-ambiguous-equal-trade", "h08-mate-in-one",
    ]

    static let developmentSequenceIDs = [
        "s01-danger-selection-response", "s02-danger-negative-answer",
        "s03-capture-none", "s04-safe-move-confirm", "s05-unsafe-move-retry",
        "s06-replace-move", "s07-inspect-reply", "s08-hint-then-act",
    ]

    static let holdoutSequenceIDs = [
        "s09-remove-and-stage", "s10-close-and-reopen",
    ]

    static let independent: [CoachingQualityBenchmarkTurn] = [
        independent("q01-starting-position", .development, .quiet, neutral("01-quiet-help")),
        independent("q02-quiet-midgame", .development, .quiet, broad("b01-quiet-midgame-help")),
        independent("q03-quiet-castling", .development, .quiet, neutral("08-long-history")),
        independent("d01-loose-bishop", .development, .danger, broad("b02-loose-bishop-danger")),
        independent("d02-defended-knight", .development, .danger, broad("b03-defended-knight")),
        independent("d03-recapturable-pawn", .development, .danger, broad("b13-recapturable-pawn")),
        independent("d04-pinned-knight", .development, .danger, broad("b07-pinned-knight-selection")),
        independent("d05-answering-check", .development, .danger, neutral("07-answering-check")),
        independent("d06-apparent-danger", .development, .danger, neutral("06-inspected-reply")),
        independent("d07-two-dangers", .development, .danger, neutral("02-attacked-piece")),
        independent("c01-safe-queen-capture", .development, .capture, broad("b04-safe-queen-capture")),
        independent("c02-poisoned-bishop-capture", .development, .capture, broad("b05-poisoned-bishop-capture")),
        independent("c03-equal-exchange", .development, .capture, broad("b06-equal-bishop-knight-exchange")),
        independent("c04-no-safe-capture", .development, .capture, neutral("05-tactical-reply")),
        independent("c05-mating-capture", .development, .specialRule, matingSnapshot()),
        independent("c06-en-passant", .development, .specialRule, enPassantSnapshot()),
        independent("m01-safe-development", .development, .tentativeMove, broad("b08-safe-development")),
        independent("m02-ignored-danger", .development, .tentativeMove, broad("b09-ignored-bishop-danger")),
        independent("m03-harmless-check-trade", .development, .tentativeMove, broad("b10-harmless-check-trade")),
        independent("m04-replaced-knight", .development, .tentativeMove, broad("b12-replaced-knight-move")),
        independent("m05-removed-move", .development, .interaction, removedMoveSnapshot()),
        independent("m06-promotion", .development, .specialRule, promotionSnapshot()),
        independent("m07-castling", .development, .specialRule, castlingSnapshot()),
        independent("m08-discovered-check", .development, .specialRule, discoveredCheckSnapshot()),
        independent("i01-selected-attacked-piece", .development, .interaction, neutral("03-selected-piece")),
        independent("i02-selected-blocked-rook", .development, .interaction, selectedRookSnapshot()),
        independent("i03-inspected-losing-queen", .development, .interaction, broad("b11-inspected-losing-queen-capture")),
        independent("i04-opening-hint", .development, .interaction, actionSnapshot(on: neutral("01-quiet-help").committedState, action: "hint")),
        independent("i05-no-piece-needs-help", .development, .interaction, actionSnapshot(on: neutral("01-quiet-help").committedState, action: "noPieceNeedsHelp")),
        independent("i06-no-safe-capture", .development, .interaction, actionSnapshot(on: broad("b01-quiet-midgame-help").committedState, action: "noSafeCapture")),
        independent("i07-looks-safe", .development, .interaction, actionAfterTentative(broad("b08-safe-development"), action: "looksSafe")),
        independent("i08-try-another-move", .development, .interaction, actionAfterTentative(broad("b09-ignored-bishop-danger"), action: "tryAnotherMove")),
        independent("h01-quiet-black-opening", .holdout, .quiet, blackOpeningSnapshot()),
        independent("h02-defended-pawn", .holdout, .danger, broad("b13-recapturable-pawn")),
        independent("h03-double-check", .holdout, .specialRule, broad("b10-harmless-check-trade")),
        independent("h04-castling-check", .holdout, .specialRule, castlingSnapshot()),
        independent("h05-stale-selection-replaced", .holdout, .interaction, neutral("04-replaced-tentative-move")),
        independent("h06-benign-capture-safety", .holdout, .capture, broad("b06-equal-bishop-knight-exchange")),
        independent("h07-ambiguous-equal-trade", .holdout, .capture, broad("b05-poisoned-bishop-capture")),
        independent("h08-mate-in-one", .holdout, .specialRule, matingSnapshot()),
    ]

    static let sequences: [CoachingQualityBenchmarkSequence] = [
        dangerSelectionSequence(),
        dangerNegativeSequence(),
        captureNoneSequence(),
        safeMoveSequence(),
        unsafeMoveSequence(),
        replaceMoveSequence(),
        inspectReplySequence(),
        hintThenActSequence(),
        removeMoveSequence(),
        closeReopenSequence(),
    ]

    private static func independent(
        _ id: String,
        _ split: CoachingQualityBenchmarkSplit,
        _ category: CoachingQualityBenchmarkCategory,
        _ snapshot: ModelCoachingNeutralSnapshot
    ) -> CoachingQualityBenchmarkTurn {
        CoachingQualityBenchmarkTurn(
            id: id,
            groupID: id,
            stepIndex: 1,
            split: split,
            category: category,
            snapshot: snapshot,
            graderBrief: brief(for: category),
            sourceTraceID: nil
        )
    }

    private static func sequence(
        id: String,
        split: CoachingQualityBenchmarkSplit,
        category: CoachingQualityBenchmarkCategory,
        state: GameState,
        selectedSquares: [String?],
        tentativeMoves: [Move?],
        events: [ModelCoachingNeutralEpisodeEvent]
    ) -> CoachingQualityBenchmarkSequence {
        let steps = events.indices.map { index in
            let stepEvents = Array(events.prefix(index + 1))
            return CoachingQualityBenchmarkTurn(
                id: "\(id)-\(String(format: "%02d", index + 1))",
                groupID: id,
                stepIndex: index + 1,
                split: split,
                category: category,
                snapshot: snapshot(
                    state: state,
                    selectedSquare: selectedSquares[index],
                    tentativeMove: tentativeMoves[index],
                    events: stepEvents
                ),
                graderBrief: brief(for: category),
                sourceTraceID: nil
            )
        }
        return CoachingQualityBenchmarkSequence(id: id, split: split, steps: steps)
    }

    private static func dangerSelectionSequence() -> CoachingQualityBenchmarkSequence {
        let state = neutral("02-attacked-piece").committedState
        let staged = legalMove("f3g1", in: state)
        return sequence(
            id: "s01-danger-selection-response", split: .development, category: .danger,
            state: state,
            selectedSquares: [nil, "f3", "g1"],
            tentativeMoves: [nil, nil, staged],
            events: [
                event(1, .helpOpened),
                event(2, .pieceSelected, ["piece:white:knight:f3"]),
                event(3, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
            ]
        )
    }

    private static func dangerNegativeSequence() -> CoachingQualityBenchmarkSequence {
        let state = neutral("02-attacked-piece").committedState
        let staged = legalMove("f3g1", in: state)
        return sequence(
            id: "s02-danger-negative-answer", split: .development, category: .danger,
            state: state,
            selectedSquares: [nil, nil, "g1"],
            tentativeMoves: [nil, nil, staged],
            events: [
                event(1, .helpOpened),
                event(2, .actionChosen, ["action:noPieceNeedsHelp"]),
                event(3, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
            ]
        )
    }

    private static func captureNoneSequence() -> CoachingQualityBenchmarkSequence {
        let state = GameState.startingPosition()
        let staged = legalMove("e2e4", in: state)
        return sequence(
            id: "s03-capture-none", split: .development, category: .capture,
            state: state,
            selectedSquares: [nil, nil, "e4"],
            tentativeMoves: [nil, nil, staged],
            events: [
                event(1, .helpOpened),
                event(2, .actionChosen, ["action:noSafeCapture"]),
                event(3, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
            ]
        )
    }

    private static func safeMoveSequence() -> CoachingQualityBenchmarkSequence {
        let base = broad("b08-safe-development")
        let staged = legalMove("b1c3", in: base.committedState)
        return sequence(
            id: "s04-safe-move-confirm", split: .development, category: .tentativeMove,
            state: base.committedState,
            selectedSquares: [nil, "c3", "c3"],
            tentativeMoves: [nil, staged, staged],
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
                event(3, .actionChosen, ["action:looksSafe"]),
            ]
        )
    }

    private static func unsafeMoveSequence() -> CoachingQualityBenchmarkSequence {
        let base = broad("b09-ignored-bishop-danger")
        let staged = legalMove("a2a3", in: base.committedState)
        return sequence(
            id: "s05-unsafe-move-retry", split: .development, category: .tentativeMove,
            state: base.committedState,
            selectedSquares: [nil, "a3", "a3"],
            tentativeMoves: [nil, staged, staged],
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
                event(3, .actionChosen, ["action:tryAnotherMove"]),
            ]
        )
    }

    private static func replaceMoveSequence() -> CoachingQualityBenchmarkSequence {
        let state = broad("b12-replaced-knight-move").committedState
        let first = legalMove("h2h3", in: state)
        let replacement = legalMove("e5f3", in: state)
        return sequence(
            id: "s06-replace-move", split: .development, category: .tentativeMove,
            state: state,
            selectedSquares: [nil, "h3", "f3"],
            tentativeMoves: [nil, first, replacement],
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(first)]),
                event(3, .moveReplaced, [ModelCoachingPositionEncoder.moveID(replacement)]),
            ]
        )
    }

    private static func inspectReplySequence() -> CoachingQualityBenchmarkSequence {
        let state = broad("b11-inspected-losing-queen-capture").committedState
        let staged = legalMove("d2d3", in: state)
        return sequence(
            id: "s07-inspect-reply", split: .development, category: .tentativeMove,
            state: state,
            selectedSquares: [nil, "d3", "d3"],
            tentativeMoves: [nil, staged, staged],
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
                event(3, .squareInspected, ["piece:black:queen:f6"]),
            ]
        )
    }

    private static func hintThenActSequence() -> CoachingQualityBenchmarkSequence {
        let state = GameState.startingPosition()
        let staged = legalMove("e2e4", in: state)
        return sequence(
            id: "s08-hint-then-act", split: .development, category: .interaction,
            state: state,
            selectedSquares: [nil, nil, "e4"],
            tentativeMoves: [nil, nil, staged],
            events: [
                event(1, .helpOpened),
                event(2, .actionChosen, ["action:hint"]),
                event(3, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
            ]
        )
    }

    private static func removeMoveSequence() -> CoachingQualityBenchmarkSequence {
        let state = GameState.startingPosition()
        let staged = legalMove("e2e4", in: state)
        return sequence(
            id: "s09-remove-and-stage", split: .holdout, category: .interaction,
            state: state,
            selectedSquares: [nil, "e4", nil],
            tentativeMoves: [nil, staged, nil],
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)]),
                event(3, .moveRemoved, [ModelCoachingPositionEncoder.moveID(staged)]),
            ]
        )
    }

    private static func closeReopenSequence() -> CoachingQualityBenchmarkSequence {
        sequence(
            id: "s10-close-and-reopen", split: .holdout, category: .interaction,
            state: GameState.startingPosition(),
            selectedSquares: [nil, nil, nil],
            tentativeMoves: [nil, nil, nil],
            events: [
                event(1, .helpOpened),
                event(2, .helpClosed),
                event(3, .helpReopened),
            ]
        )
    }

    private static func brief(
        for category: CoachingQualityBenchmarkCategory
    ) -> CoachingQualityBenchmarkGraderBrief {
        let purpose: String
        let success: [String]
        let severe: [String]
        switch category {
        case .quiet:
            purpose = "Offer one useful beginner thought without inventing urgency or prescribing an exact move."
            success = ["The response encourages discovery and fits a position with no immediate emergency."]
            severe = ["The response invents a hanging piece, forced tactic, check, or mandatory move."]
        case .danger:
            purpose = "Help the learner notice and reason about the most relevant immediate danger."
            success = ["The response accurately distinguishes a real threat from a defended or harmless attack."]
            severe = ["The response misses check, claims a safe piece is lost, or identifies the wrong color or piece."]
        case .capture:
            purpose = "Help the learner assess whether a capture is available and what the opponent can do next."
            success = ["The response treats recaptures and exchanges accurately without revealing more than needed."]
            severe = ["The response invents a capture, overlooks an encoded recapture, or calls a losing capture safe."]
        case .tentativeMove:
            purpose = "Respond to the currently staged move and help the learner evaluate it before committing."
            success = ["The response follows the latest move and gives one answerable next step."]
            severe = ["The response discusses a superseded move or approves a move contradicted by an immediate reply."]
        case .interaction:
            purpose = "Follow the learner's latest tap, answer, revision, or help action without repeating a resolved step."
            success = ["The response acknowledges the latest interaction and advances one coherent step."]
            severe = ["The response ignores the latest event, repeats a resolved question, or offers no possible next action."]
        case .specialRule:
            purpose = "Explain the relevant check, mate, castling, en-passant, or promotion consequence simply and accurately."
            success = ["The response handles the special rule correctly in beginner-friendly language."]
            severe = ["The response misstates legality, check, checkmate, castling, en-passant, or promotion."]
        }
        return CoachingQualityBenchmarkGraderBrief(
            verifiedFacts: [],
            coachingPurpose: purpose,
            acceptableAlternatives: ["Any concise, accurate coaching turn that preserves learner agency."],
            successCriteria: success,
            severeFailureCriteria: severe
        )
    }

    private static func neutral(_ id: String) -> ModelCoachingNeutralSnapshot {
        ModelCoachingNeutralPromptExamples.fixtures.first { $0.id == id }!.snapshot
    }

    private static func broad(_ id: String) -> ModelCoachingNeutralSnapshot {
        ModelCoachingChessNativeBroadEvaluationExamples.fixtures.first { $0.id == id }!.snapshot
    }

    private static func removedMoveSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = GameState.startingPosition()
        let removed = legalMove("e2e4", in: state)
        return snapshot(
            state: state,
            events: [
                event(1, .helpOpened),
                event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(removed)]),
                event(3, .moveRemoved, [ModelCoachingPositionEncoder.moveID(removed)]),
            ]
        )
    }

    private static func matingSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = replaying(["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6"])
        return snapshot(state: state, events: [event(1, .helpOpened)])
    }

    private static func enPassantSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = replaying(["e2e4", "a7a6", "e4e5", "d7d5"])
        let staged = legalMove("e5d6", in: state)
        return snapshot(
            state: state,
            selectedSquare: "d6",
            tentativeMove: staged,
            events: [event(1, .helpOpened), event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)])]
        )
    }

    private static func promotionSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = replaying(["a2a4", "h7h5", "a4a5", "h5h4", "a5a6", "h4h3", "a6b7", "h3g2"])
        let staged = legalMove("b7a8q", in: state)
        return snapshot(
            state: state,
            selectedSquare: "a8",
            tentativeMove: staged,
            events: [event(1, .helpOpened), event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)])]
        )
    }

    private static func castlingSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = neutral("08-long-history").committedState
        let staged = legalMove("e1g1", in: state)
        return snapshot(
            state: state,
            selectedSquare: "g1",
            tentativeMove: staged,
            events: [event(1, .helpOpened), event(2, .moveStaged, [ModelCoachingPositionEncoder.moveID(staged)])]
        )
    }

    private static func discoveredCheckSnapshot() -> ModelCoachingNeutralSnapshot {
        let state = replaying(["e2e4", "d7d5", "e4d5", "d8d5", "b1c3"])
        return snapshot(state: state, learner: .black, events: [event(1, .helpOpened)])
    }

    private static func selectedRookSnapshot() -> ModelCoachingNeutralSnapshot {
        snapshot(
            state: GameState.startingPosition(),
            selectedSquare: "a1",
            events: [event(1, .helpOpened), event(2, .pieceSelected, ["piece:white:rook:a1"])]
        )
    }

    private static func actionSnapshot(on state: GameState, action: String) -> ModelCoachingNeutralSnapshot {
        snapshot(
            state: state,
            events: [event(1, .helpOpened), event(2, .actionChosen, ["action:\(action)"])]
        )
    }

    private static func actionAfterTentative(
        _ base: ModelCoachingNeutralSnapshot,
        action: String
    ) -> ModelCoachingNeutralSnapshot {
        let events = base.episodeEvents + [
            event(base.episodeEvents.count + 1, .actionChosen, ["action:\(action)"])
        ]
        return snapshot(
            state: base.committedState,
            selectedSquare: base.selectedSquare.map(ModelCoachingPositionEncoder.squareName),
            tentativeMove: base.tentativeMove,
            events: events
        )
    }

    private static func blackOpeningSnapshot() -> ModelCoachingNeutralSnapshot {
        snapshot(
            state: replaying(["e2e4"]),
            learner: .black,
            events: [event(1, .helpOpened)]
        )
    }

    private static func snapshot(
        state: GameState,
        learner: PieceColor = .white,
        selectedSquare: String? = nil,
        tentativeMove: Move? = nil,
        events: [ModelCoachingNeutralEpisodeEvent]
    ) -> ModelCoachingNeutralSnapshot {
        ModelCoachingNeutralSnapshot(
            committedState: state,
            learner: learner,
            positionRevision: state.moveHistory.count,
            selectedSquare: selectedSquare.map(square),
            tentativeMove: tentativeMove,
            latestEvent: events.last!,
            episodeEvents: events
        )
    }

    private static func replaying(_ canonicalMoves: [String]) -> GameState {
        canonicalMoves.reduce(into: GameState.startingPosition()) { state, canonicalMove in
            state.apply(legalMove(canonicalMove, in: state))
        }
    }

    private static func legalMove(_ canonicalMove: String, in state: GameState) -> Move {
        LegalMoveGenerator.allLegalMoves(in: state).first {
            ModelCoachingPositionEncoder.canonicalMove($0) == canonicalMove
        }!
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

    private static func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }
}
