import Foundation
import XCTest
@testable import ChessTutor

/// Later-game development probes, separate from the frozen benchmark and opening regressions.
enum CoachingLaterGameBenchmark {
    static let history = CoachingPlaythroughBenchmark.history + [
        "c4e6", "f7e6", "g4e6", "f8f7", "f3g5", "h6g5", "e6f7", "h7h6",
        "f7c7", "g5g4", "c7d6", "h6h7", "d6c6", "b7c6", "f2f3", "g4f3",
        "f1f3", "a8f8", "f3f8", "h7g6", "a1f1", "e5e4", "d3e4", "c6c5",
        "f1f6", "g6g5", "f6d6", "c5c4", "d6d5", "g5g6", "d5c5", "c4c3",
        "b2c3", "g6g7", "f8a8", "g7f6", "c5c7", "a7a5", "c7a7", "f6e5",
        "a7a5", "e5e4", "a5h5", "e4e3", "h5h3", "e3d2", "c3c4", "d2c2",
        "c4c5", "c2b2", "c5c6", "b2b1", "c6c7", "b1c1", "c7c8q", "c1d2",
        "g1f2", "d2d1",
    ]

    static func corpus() throws -> CoachingQualityBenchmarkCorpus {
        let cases: [(String, Int, String?, [String], String)] = [
            ("l01-losing-queen-capture", 44, "d6c6", [
                "White's staged queen captures the knight on c6. Black's pawn on b7 can recapture on c6.",
                "This loses a queen for a knight; White's overall material advantage does not make that trade favorable.",
            ], "Explain the concrete cost of this staged capture; do not praise it as a safe free knight."),
            ("l02-winning-rook-capture", 50, "f3f8", [
                "White's rook can capture Black's only rook on f8. The black king on h7 cannot recapture on f8.",
                "After this capture Black has only a king and pawns. There is no immediate capture of the white rook.",
            ], "Recognize the winning rook capture and offer the child a keep/change choice."),
            ("l03-active-endgame-king", 88, "g1f2", [
                "The white king moves safely from g1 to f2; Black's king on d2 does not attack f2.",
                "From f2 the white king controls e1, e2 and e3, restricting the black king's escape.",
            ], "Explain a concrete benefit of bringing the king into the endgame, not opening-style advice to hide it."),
            ("l04-passed-pawn-help", 84, nil, [
                "White's passed pawn is on c6; c7 and c8 are empty. Black has only a king on b1 and cannot stop c7 followed by promotion next turn.",
                "No white piece can be captured on Black's next move in this position. White's pawn on a2 is protected by the rook on a8.",
            ], "Give an accessible endgame goal or discovery question, such as advancing the pawn toward promotion; do not invent urgent danger."),
            ("l05-pawn-promotion", 86, "c7c8q", [
                "White's pawn reaches c8 and promotes to a queen, giving check to Black's king on c1 along the c-file.",
                "This is not checkmate: Black can move its king to b1, b2, d1 or d2. Black cannot immediately capture the new queen.",
            ], "Recognize promotion and check accurately, without falsely announcing checkmate or an already committed move."),
            ("l06-mating-net-help", 90, nil, [
                "Black has only a king on d1. White has king f2, queen c8, rooks a8/h3 and pawns a2/g2/h2.",
                "Rh3-d3 is checkmate: the rook checks down the d-file, the queen covers c1/c2, and the king covers e1/e2.",
                "Qc8-c3 instead stalemates Black. Black is not in check and has no legal move after it.",
            ], "Coach toward trapping the lone king with an understandable question or goal; ordinary Help should leave some discovery, not dictate the exact mating move."),
            ("l07-staged-checkmate", 90, "h3d3", [
                "The staged Rh3-d3 checks Black's king on d1 and leaves no legal reply. It is checkmate if committed.",
                "White's queen on c8 covers c1 and c2, the rook on d3 covers d2, and the king on f2 covers e1 and e2.",
            ], "Recognize that this staged move is mate and explain it simply; offer committing the move rather than looking for unrelated captures."),
            ("l08-staged-stalemate", 90, "c8c3", [
                "After Qc8-c3 Black's king on d1 is not in check, but cannot move. This is stalemate, a draw, not checkmate or a win.",
                "White can choose a different move instead; Rh3-d3 would checkmate in the committed position.",
            ], "Explain the stalemate trap in child-friendly language and allow reconsideration; do not approve it as a win or merely safe."),
        ]
        let turns = try cases.map { id, plies, canonical, facts, purpose in
            let state = try state(after: plies)
            let move = try canonical.map { try legalMove($0, in: state) }
            let opened = ModelCoachingNeutralEpisodeEvent(sequence: 1, kind: .helpOpened, referencedIDs: [])
            let event = move.map {
                ModelCoachingNeutralEpisodeEvent(sequence: 2, kind: .moveStaged,
                                                 referencedIDs: [ModelCoachingPositionEncoder.moveID($0)])
            } ?? opened
            return CoachingQualityBenchmarkTurn(
                id: id, groupID: id, stepIndex: 1, split: .development,
                category: move == nil ? .quiet : .tentativeMove,
                snapshot: ModelCoachingNeutralSnapshot(
                    committedState: state, learner: state.sideToMove, positionRevision: plies,
                    selectedSquare: move?.to, tentativeMove: move,
                    latestEvent: event, episodeEvents: move == nil ? [opened] : [opened, event]
                ),
                graderBrief: CoachingQualityBenchmarkGraderBrief(
                    verifiedFacts: facts, coachingPurpose: purpose,
                    acceptableAlternatives: ["Any concise, accurate, age-appropriate explanation or question meeting the purpose; no exact wording is required."],
                    successCriteria: [purpose, "Staged-move feedback may explain the outcome directly and offer keep/change; it need not become another discovery question."],
                    severeFailureCriteria: ["Incorrect chess facts, treating stalemate as a win, claiming non-mating promotion is mate, approving a queen-for-knight loss, or requiring unavailable UI."]
                ), sourceTraceID: nil
            )
        }
        return CoachingQualityBenchmarkCorpus(independent: turns, sequences: [])
    }

    static func state(after plies: Int) throws -> GameState {
        precondition((0...history.count).contains(plies))
        var state = GameState.startingPosition()
        for canonical in history.prefix(plies) { state.apply(try legalMove(canonical, in: state)) }
        return state
    }

    static func legalMove(_ canonical: String, in state: GameState) throws -> Move {
        try XCTUnwrap(LegalMoveGenerator.allLegalMoves(in: state).first {
            ModelCoachingPositionEncoder.canonicalMove($0) == canonical
        }, "Illegal recorded move after \(state.moveHistory.count) plies: \(canonical)")
    }
}

final class CoachingLaterGameBenchmarkTests: XCTestCase {
    func testLegalReplayAndExportKeepFullHistoryWithoutGraderLeakage() throws {
        let corpus = try CoachingLaterGameBenchmark.corpus()
        let first = try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true)
        XCTAssertEqual(first, try CoachingQualityBenchmarkExporter.artifacts(sourceGitSHA: "test", corpus: corpus, regression: true))
        let manifest = try JSONDecoder().decode(CoachingQualityBenchmarkManifest.self, from: first.manifestJSON)
        XCTAssertEqual(8, manifest.turnCount)
        XCTAssertEqual(0, manifest.holdoutTurnCount)
        for turn in corpus.allTurns {
            let request = ModelCoachingNeutralRequestBuilder.build(snapshot: turn.snapshot, requestID: turn.id)
            XCTAssertEqual(Array(CoachingLaterGameBenchmark.history.prefix(turn.snapshot.positionRevision)), request.gameHistory.map(\.canonicalMove))
            XCTAssertGreaterThanOrEqual(request.gameHistory.count, 44)
            let prompt = ModelCoachingChessNativeContextCompiler.compile(request, promptVersion: "tutor-v13").markdown
            XCTAssertFalse(prompt.contains(turn.graderBrief.coachingPurpose))
            XCTAssertFalse(prompt.contains("Staged-move feedback may explain"))
        }
    }

    func testPromotionAndTerminalOutcomesMatchRules() throws {
        let square = CoachingPlaythroughBenchmark.square
        let turns = try CoachingLaterGameBenchmark.corpus().allTurns
        let requests = turns.map { ModelCoachingNeutralRequestBuilder.build(snapshot: $0.snapshot, requestID: $0.id) }
        XCTAssertTrue(requests[0].tentativeReplies.contains { $0.canonicalMove == "b7c6" })
        XCTAssertFalse(requests[1].tentativeReplies.contains { $0.destinationSquare == "f8" })
        let king = try CoachingLaterGameBenchmark.state(after: 89)
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("f2"), in: king).contains(square("e1")))
        XCTAssertTrue(LegalMoveGenerator.controlledSquares(from: square("f2"), in: king).contains(square("e2")))
        var beforePromotion = try CoachingLaterGameBenchmark.state(after: 84)
        beforePromotion.sideToMove = .black
        XCTAssertFalse(LegalMoveGenerator.allLegalMoves(in: beforePromotion).contains {
            LegalMoveGenerator.capture(for: $0, in: beforePromotion) != nil
        })
        XCTAssertEqual("promote-queen", requests[4].interaction.tentativeMove?.special)
        XCTAssertEqual(true, requests[4].interaction.tentativeMove?.givesCheck)
        XCTAssertEqual(false, requests[4].interaction.tentativeMove?.givesCheckmate)
        XCTAssertTrue(requests[4].tentativeReplies.isEmpty) // Quiet king escapes are deliberately not listed.
        let promoted = try CoachingLaterGameBenchmark.state(after: 87)
        XCTAssertEqual(Piece(kind: .queen, color: .white), promoted.board[square("c8")])
        XCTAssertEqual(Set(["c1b1", "c1b2", "c1d1", "c1d2"]), Set(LegalMoveGenerator.allLegalMoves(in: promoted).map(ModelCoachingPositionEncoder.canonicalMove)))
        let final = try CoachingLaterGameBenchmark.state(after: 90)
        XCTAssertEqual("R1Q5/8/8/8/8/7R/P4KPP/3k4 w - - 3 46", ModelCoachingPositionEncoder.fen(for: final))
        var mate = final
        mate.apply(try CoachingLaterGameBenchmark.legalMove("h3d3", in: final))
        XCTAssertEqual(.checkmate(winner: .white), mate.result)
        var draw = final
        draw.apply(try CoachingLaterGameBenchmark.legalMove("c8c3", in: final))
        XCTAssertEqual(.stalemate, draw.result)
        XCTAssertFalse(LegalMoveGenerator.isKingInCheck(.black, in: draw.board))
    }

    func testOptInExport() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["COACHING_LATER_GAME_BENCHMARK_OUTPUT_DIR"], !path.isEmpty else { return }
        try CoachingQualityBenchmarkExporter.write(
            to: URL(fileURLWithPath: path), sourceGitSHA: XCTUnwrap(env["COACHING_QUALITY_BENCHMARK_SOURCE_SHA"]),
            corpus: CoachingLaterGameBenchmark.corpus(), regression: true
        )
    }
}
