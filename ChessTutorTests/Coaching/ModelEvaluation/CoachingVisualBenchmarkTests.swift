import Foundation
import XCTest
@testable import ChessTutor

enum CoachingVisualBenchmark {
    static let manifestVersion = "coaching-quality-visual-regression-manifest.v1"
    static let visualCriteria = "Grade every linked phrase against the displayed piece or square, including same-kind pieces. Judge arrows as part of the advice: correct direction, no discovery spoilers, visible draft origin. Prefer simple words and useful references over coordinate-heavy prose. Plain words are sufficient when unambiguous; do not reward decoration. No mandatory Try another move detour."

    static func corpus() throws -> CoachingQualityBenchmarkCorpus {
        let experience = try CoachingExperienceBenchmark.corpus().allTurns
        let definitions = [("v01-opening", "e04-opening-discovery"), ("v04-move-hint", "e05-requested-hint"),
            ("v05-draft-revision", "e14-revise-staged-knight"), ("v06-empty-square", "e13-calm-center-pawn"),
            ("v07-defended-target", "e02-explain-answer"), ("v08-flank-pawn", "e10-black-flank-pawn")]
        var independent = try definitions.map { id, sourceID in
            let source = try XCTUnwrap(experience.first { $0.id == sourceID })
            return CoachingQualityBenchmarkTurn(id: id, groupID: id, stepIndex: 1, split: .development,
                category: source.category, snapshot: source.snapshot,
                graderBrief: .init(verifiedFacts: source.graderBrief.verifiedFacts,
                    coachingPurpose: source.graderBrief.coachingPurpose, acceptableAlternatives: source.graderBrief.acceptableAlternatives,
                    successCriteria: source.graderBrief.successCriteria + [visualCriteria],
                    severeFailureCriteria: source.graderBrief.severeFailureCriteria + ["Linking a different piece or revealing the answer in a discovery question."]), sourceTraceID: sourceID)
        }
        let square = CoachingPlaythroughBenchmark.square
        let state = GameState(board: Board(pieces: [
            square("e1"): Piece(kind: .king, color: .white), square("e8"): Piece(kind: .king, color: .black),
            square("b1"): Piece(kind: .knight, color: .white), square("g1"): Piece(kind: .knight, color: .white),
            square("b8"): Piece(kind: .rook, color: .black),
        ]), sideToMove: .white)
        let events: [ModelCoachingNeutralEpisodeEvent] = [
            .init(sequence: 1, kind: .helpOpened, referencedIDs: []),
            .init(sequence: 2, kind: .pieceSelected, referencedIDs: ["piece:white:knight:g1"]),
            .init(sequence: 3, kind: .pieceSelected, referencedIDs: ["piece:white:knight:b1"]),
        ]
        func dangerTurn(id: String, group: String, step: Int, event: ModelCoachingNeutralEpisodeEvent,
                        history: [ModelCoachingNeutralEpisodeEvent], selected: Square?, purpose: String) -> CoachingQualityBenchmarkTurn {
            .init(id: id, groupID: group, stepIndex: step, split: .development, category: .danger,
                snapshot: .init(committedState: state, learner: .white, positionRevision: 0,
                    selectedSquare: selected, tentativeMove: nil, latestEvent: event, episodeEvents: history),
                graderBrief: .init(verifiedFacts: ["Black's rook on b8 attacks White's knight on b1. White's knight on g1 is not attacked. White is not in check."],
                    coachingPurpose: purpose, acceptableAlternatives: ["Concise, calm advice preserving the player's choice."],
                    successCriteria: [visualCriteria, purpose], severeFailureCriteria: ["Confusing the two knights, reversing the rook attack, or revealing the answer while asking for it."]), sourceTraceID: nil)
        }
        let steps = events.enumerated().map { index, event in
            dangerTurn(id: "v02-threat-\(index + 1)", group: "v02-threat", step: index + 1, event: event,
                history: Array(events.prefix(index + 1)), selected: index == 0 ? nil : square(index == 1 ? "g1" : "b1"),
                purpose: index == 0 ? "Invite the child to tap the endangered knight, without highlighting it."
                    : index == 1 ? "The child chose the safe knight. Gently redirect attention, without praising a wrong answer or revealing the target."
                    : "The child found the attacked knight. Acknowledge it and explain the rook's attack before inviting a saving move. Links and a correctly directed attack arrow may help.")
        }
        let hint = ModelCoachingNeutralEpisodeEvent(sequence: 2, kind: .actionChosen, referencedIDs: ["action:hint"])
        independent.insert(dangerTurn(id: "v03-source-hint", group: "v03-source-hint", step: 1, event: hint,
            history: [events[0], hint], selected: nil,
            purpose: "The child requested a clue. If retaining the endangered-piece question, link only the attacking rook as a source clue, not either knight or an arrow. A full reveal must switch to stageMove."), at: 1)
        return .init(independent: independent, sequences: [.init(id: "v02-threat", split: .development, steps: steps)])
    }
}

final class CoachingVisualBenchmarkTests: XCTestCase {
    func testInventoryUsesRealRulesAndKeepsPrivateVisualRubricOutOfPrompt() throws {
        let corpus = try CoachingVisualBenchmark.corpus()
        XCTAssertEqual(7, corpus.independent.count)
        XCTAssertEqual(1, corpus.sequences.count)
        XCTAssertEqual(10, corpus.allTurns.count)
        for turn in corpus.allTurns {
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: turn.id)
            XCTAssertFalse(request.pieces.isEmpty)
            let prompt = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(prompt.contains("Grade every linked phrase"))
        }
        let threat = try XCTUnwrap(corpus.sequences.first?.steps.first)
        let request = ModelCoachingNeutralRequestBuilder.build(snapshot: threat.snapshot, requestID: "threat")
        XCTAssertTrue(request.occupiedSquareRelationships.contains {
            $0.kind == .attacks && $0.sourcePieceReference == "piece:black:rook:b8" && $0.targetPieceReference == "piece:white:knight:b1"
        })
    }

    func testOptInExport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["COACHING_VISUAL_BENCHMARK_OUTPUT_DIR"], !path.isEmpty else { return }
        try CoachingQualityBenchmarkExporter.write(to: URL(fileURLWithPath: path),
            sourceGitSHA: XCTUnwrap(env["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"]), corpus: CoachingVisualBenchmark.corpus(),
            regression: true, preserveVerifiedFacts: true, regressionSchemaVersion: CoachingVisualBenchmark.manifestVersion)
    }
}
