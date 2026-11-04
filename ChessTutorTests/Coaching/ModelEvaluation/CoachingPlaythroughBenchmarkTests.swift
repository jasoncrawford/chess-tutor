import Foundation
import XCTest
@testable import ChessTutor

/// Versioned development regressions, deliberately separate from the frozen benchmark.
enum CoachingPlaythroughBenchmark {
    static let history = [
        "e2e4", "e7e5", "f1c4", "g8f6", "d2d3", "b8c6", "g1f3", "d7d6",
        "e1g1", "f8e7", "b1c3", "e8g8", "c1g5", "h7h6", "g5f6", "e7f6",
        "c3d5", "d8d7", "d5f6", "g7f6", "f3h4", "g8h7", "d1h5", "f6f5",
        "e4f5", "d7e7", "f5f6", "e7f6", "h4f3", "c8g4", "h5g4", "f6e6",
    ]

    static func corpus() throws -> CoachingQualityBenchmarkCorpus {
        let cases: [(String, Int, String?, [String], String, String)] = [
            ("p01-one-way-defense", 4, "d2d3", [
                "After d3, the white pawn on d3 protects e4; the pawn on e4 does not protect d3.",
                "The black knight on f6 attacks e4. After ...Nxe4, d3xe4 can recapture it.",
            ], "Explain the staged pawn's concrete defensive consequence without claiming mutual protection.", "22bdd2592aa2"),
            ("p02-no-forced-defense", 6, "g1f3", [
                "After Nf3 the knight attacks e5, but Black's knight on c6 already defends e5.",
                "Black is not forced to make a new defensive move. Nf3 clears g1 for later kingside castling.",
            ], "Explain one true consequence of the staged knight move; do not invent a forced reply.", "playthrough:white-knight-2"),
            ("p03-bishop-consequence", 2, "f1c4", [
                "After Bc4 the white bishop attacks Black's pawn on f7 along c4-d5-e6-f7.",
                "Black's king on e8 defends f7; this attack does not win a free pawn.",
            ], "Explain one observable consequence, not just that the bishop joins the game.", "playthrough:bishop-2"),
            ("p04-knight-consequence", 5, "b8c6", [
                "After ...Nc6 the black knight on c6 defends the black pawn on e5.",
                "The knight also controls d4. White's pawn on e4 attacks d5 and f5, not e5.",
            ], "Explain one observable consequence, not merely that the knight develops near the middle.", "playthrough:black-knight-2"),
            ("p05-losing-bishop-capture", 4, "c4f7", [
                "Bxf7+ captures a pawn with check, but Black can play Kxf7 and win the bishop.",
                "The pawn gain and check do not make this a safe or favorable trade.",
            ], "Explain the concrete risk of the child's staged capture without approving it as safe.", "playthrough:danger-4"),
            ("p06-queen-for-bishop", 32, "c4e6", [
                "Bxe6 wins Black's queen. Black can reply f7xe6 and recapture the bishop.",
                "A queen for a bishop is a favorable material trade; a possible recapture alone does not make it bad.",
            ], "Follow the staged capture and explain the favorable trade, rather than returning to piece identification.", "fbad7006219e"),
            ("p07-defended-piece-answer", 32, nil, [
                "The selected white bishop on c4 is attacked by Black's queen on e6, but White's pawn on d3 defends it.",
                "White's queen on g4 is attacked by the same black queen and is not defended.",
            ], "Respond to the selected bishop accurately; do not confuse attacked with lost or ignore the child's answer.", "4bc150ba1f3e"),
            ("p08-replaced-move", 24, "e4f5", [
                "The child replaced Qxh6+ with exf5. The queen remains on h5, not h6.",
                "The new white pawn on f5 is protected by White's knight on h4.",
                "The obsolete Qxh6+ would lose the queen to Black's king on h7; this is not the current move.",
            ], "Discuss the new pawn capture, not the removed queen capture or an earlier coaching question.", "playthrough:hosted-24"),
        ]
        let turns = try cases.map { id, plies, canonical, facts, purpose, trace in
            let state = try state(after: plies)
            let move = try canonical.map { try legalMove($0, in: state) }
            var events = [ModelCoachingNeutralEpisodeEvent(sequence: 1, kind: .helpOpened, referencedIDs: [])]
            if id == "p08-replaced-move" {
                events.append(.init(sequence: 2, kind: .moveStaged, referencedIDs: ["move:h5-h6"]))
            }
            let kind: ModelCoachingLearnerEventKind = id == "p07-defended-piece-answer" ? .pieceSelected
                : id == "p08-replaced-move" ? .moveReplaced : .moveStaged
            let refs = move.map { ["move:\(ModelCoachingPositionEncoder.squareName($0.from))-\(ModelCoachingPositionEncoder.squareName($0.to))"] } ?? ["piece:white:bishop:c4"]
            let event = ModelCoachingNeutralEpisodeEvent(sequence: events.count + 1, kind: kind, referencedIDs: refs)
            events.append(event)
            return CoachingQualityBenchmarkTurn(
                id: id, groupID: id, stepIndex: 1, split: .development,
                category: move == nil ? .interaction : .tentativeMove,
                snapshot: ModelCoachingNeutralSnapshot(
                    committedState: state, learner: state.sideToMove, positionRevision: plies,
                    selectedSquare: move?.to ?? square("c4"), tentativeMove: move,
                    latestEvent: event, episodeEvents: events
                ),
                graderBrief: CoachingQualityBenchmarkGraderBrief(
                    verifiedFacts: facts, coachingPurpose: purpose,
                    acceptableAlternatives: ["Any concise, accurate explanation or useful question satisfying the purpose; no specific wording is required."],
                    successCriteria: [
                        purpose,
                        "Staged-move feedback may explain directly and offer a keep/change choice; it need not become another discovery question.",
                        "For development moves, generic praise alone without an observable consequence is at most 3 in coaching judgment; this is not by itself a severe or factual error.",
                    ],
                    severeFailureCriteria: ["Invented or reversed chess facts, approval of a clearly losing trade, advice for the obsolete move, or unavailable UI."]
                ), sourceTraceID: trace
            )
        }
        return CoachingQualityBenchmarkCorpus(independent: turns, sequences: [])
    }

    static func state(after plies: Int) throws -> GameState {
        var result = GameState.startingPosition()
        for canonical in history.prefix(plies) { result.apply(try legalMove(canonical, in: result)) }
        return result
    }

    private static func legalMove(_ canonical: String, in state: GameState) throws -> Move {
        try XCTUnwrap(LegalMoveGenerator.allLegalMoves(in: state).first {
            ModelCoachingPositionEncoder.canonicalMove($0) == canonical
        }, "Recorded move must be legal: \(canonical)")
    }

    static func square(_ name: String) -> Square {
        let bytes = Array(name.utf8)
        return Square(file: Square.File(rawValue: Int(bytes[0]) - 96)!, rank: Int(bytes[1]) - 48)
    }
}

final class CoachingPlaythroughBenchmarkTests: XCTestCase {
    func testExportHasEightIndependentDevelopmentCasesAndNoGraderLeakage() throws {
        let corpus = try CoachingPlaythroughBenchmark.corpus()
        let exported = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true)
        let again = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true)
        XCTAssertEqual(exported, again)
        let manifest = try JSONDecoder().decode(CoachingQualityBenchmarkManifest.self, from: exported.manifestJSON)
        XCTAssertEqual("coaching-quality-playthrough-regression-manifest.v1", manifest.schemaVersion)
        XCTAssertEqual(8, manifest.turnCount)
        XCTAssertEqual(8, manifest.developmentTurnCount)
        XCTAssertEqual(0, manifest.holdoutTurnCount)
        XCTAssertEqual(0, manifest.sequenceGroupCount)
        for turn in corpus.allTurns {
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: turn.id)
            XCTAssertEqual(Array(CoachingPlaythroughBenchmark.history.prefix(turn.snapshot.positionRevision)), request.gameHistory.map(\.canonicalMove))
            let markdown = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(markdown.contains(turn.graderBrief.coachingPurpose))
            XCTAssertFalse(markdown.contains("at most 3 in coaching judgment"))
        }
    }

    func testIndependentFactsAndCurrentMoveMatchActualRules() throws {
        let square = CoachingPlaythroughBenchmark.square
        let protected = try CoachingPlaythroughBenchmark.state(after: 5)
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("d3"), in: protected).contains(square("e4")))
        XCTAssertFalse(LegalMoveGenerator.controlledSquares(from: square("e4"), in: protected).contains(square("d3")))
        let knight = try CoachingPlaythroughBenchmark.state(after: 7)
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("c6"), in: knight).contains(square("e5")))
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("f3"), in: knight).contains(square("e5")))
        let turns = try CoachingPlaythroughBenchmark.corpus().allTurns
        let requests = turns.map { ModelCoachingNeutralRequestBuilder.build(snapshot: $0.snapshot, requestID: $0.id) }
        XCTAssertTrue(requests[4].tentativeReplies.contains { $0.canonicalMove == "e8f7" })
        XCTAssertTrue(requests[5].tentativeReplies.contains { $0.canonicalMove == "f7e6" })
        XCTAssertEqual("r4r2/ppp2p1k/2npq2p/4p3/2B3Q1/3P1N2/PPP2PPP/R4RK1 w - - 1 17", requests[5].position.fen)
        XCTAssertEqual(.pieceSelected, requests[6].interaction.latestEvent.kind)
        XCTAssertEqual("c4", requests[6].interaction.selectedSquare)
        XCTAssertEqual(.moveReplaced, requests[7].interaction.latestEvent.kind)
        XCTAssertEqual("e4f5", requests[7].interaction.tentativeMove?.canonicalMove)
        XCTAssertTrue(requests[7].pieces.contains { $0.square == "h5" && $0.kind == "queen" && $0.color == "white" })
    }

    func testOptInExport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["COACHING_PLAYTHROUGH_BENCHMARK_OUTPUT_DIR"] else { return }
        let source = try XCTUnwrap(env["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"])
        try CoachingQualityBenchmarkExporter.write(to: URL(fileURLWithPath: path), sourceGitSHA: source,
                                                  corpus: CoachingPlaythroughBenchmark.corpus(), regression: true)
    }
}
