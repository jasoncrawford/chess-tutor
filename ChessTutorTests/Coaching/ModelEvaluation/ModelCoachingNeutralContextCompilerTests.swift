import CryptoKit
import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingNeutralContextCompilerTests: XCTestCase {
    func testStartingPositionUsesFixedSectionsAndNeutralRuleVocabulary() {
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: .startingPosition(),
                learner: .white,
                positionRevision: 0,
                selectedSquare: nil,
                tentativeMove: nil,
                latestEvent: event(1, .helpOpened),
                episodeEvents: [event(1, .helpOpened)]
            ),
            requestID: "neutral-start"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        XCTAssertEqual(compilation.schemaVersion, "model-coaching-neutral-context.v1")
        XCTAssertEqual(compilation.promptVersion, "tutor-v5")
        XCTAssertEqual(compilation.requestID, "neutral-start")
        XCTAssertEqual(compilation.positionRevision, 0)
        XCTAssertEqual(
            markdownHeadings(in: compilation.markdown),
            [
                "# Chess coaching situation",
                "## Game",
                "## Current help episode",
                "## Rule facts",
                "## Available interactions",
            ]
        )
        XCTAssertTrue(compilation.markdown.contains("Side to move: White"))
        XCTAssertTrue(compilation.markdown.contains(request.position.fen))
        XCTAssertTrue(compilation.markdown.contains("Moves: none"))
        XCTAssertTrue(compilation.markdown.contains("1. helpOpened"))
        XCTAssertTrue(compilation.markdown.contains("White is not in check."))

        [
            "Selected move ideas",
            "Danger scan",
            "Safe captures",
            "useful",
            "purpose",
            "expected response",
        ].forEach { forbidden in
            XCTAssertFalse(compilation.markdown.contains(forbidden), "unexpected phrase: \(forbidden)")
        }
    }

    func testNoSelectionIncludesOpponentAttackOnLearnersOccupiedPiece() throws {
        let attackID = "relationship:attack:piece:black:pawn:e4->piece:white:knight:f3"
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state(
                    sideToMove: .white,
                    pieces: [
                        square("g1"): Piece(kind: .king, color: .white),
                        square("f3"): Piece(kind: .knight, color: .white),
                        square("h8"): Piece(kind: .king, color: .black),
                        square("e4"): Piece(kind: .pawn, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 1,
                selectedSquare: nil,
                tentativeMove: nil,
                latestEvent: event(1, .helpOpened),
                episodeEvents: [event(1, .helpOpened)]
            ),
            requestID: "neutral-attacked-knight"
        )
        XCTAssertTrue(request.occupiedSquareRelationships.contains { $0.id == attackID })

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )
        let attackAlias = try alias(for: attackID, in: compilation)

        XCTAssertTrue(
            compilation.markdown.contains(
                "\(attackAlias) (Black pawn on e4 attacks White knight on f3)"
            )
        )
        XCTAssertFalse(compilation.markdown.contains("relationship:attack:"))
    }

    func testSelectionScopeIncludesOnlySelectedPieceMovesAndRelatedRelationships() throws {
        let knight = square("f3")
        let knightID = "piece:white:knight:f3"
        let selectedPieceDefendsOtherID = "relationship:defend:piece:white:knight:f3->piece:white:king:g1"
        let state = state(
            sideToMove: .white,
            pieces: [
                square("g1"): Piece(kind: .king, color: .white),
                knight: Piece(kind: .knight, color: .white),
                square("g2"): Piece(kind: .bishop, color: .white),
                square("g8"): Piece(kind: .king, color: .black),
                square("e4"): Piece(kind: .pawn, color: .black),
            ]
        )
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state,
                learner: .white,
                positionRevision: 3,
                selectedSquare: knight,
                tentativeMove: nil,
                latestEvent: event(3, .pieceSelected, [knightID]),
                episodeEvents: [event(1, .helpOpened), event(3, .pieceSelected, [knightID])]
            ),
            requestID: "neutral-selected-knight"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        let selectedMoveIDs = Set(
            request.legalMoves
                .filter { $0.sourcePieceReference == knightID }
                .map(\.id)
        )
        let nonSelectedQuietMove = try XCTUnwrap(
            request.legalMoves.first {
                $0.sourcePieceReference != knightID && $0.capturePieceReference == nil && !$0.givesCheck
            }
        )

        XCTAssertTrue(compilation.markdown.contains("Selected piece:"))
        for stableID in selectedMoveIDs {
            let alias = try alias(for: stableID, in: compilation)
            XCTAssertTrue(compilation.markdown.contains(alias), "missing selected move alias for \(stableID)")
        }
        XCTAssertFalse(compilation.referenceBindings.contains { $0.stableID == nonSelectedQuietMove.id })
        XCTAssertFalse(compilation.markdown.contains(nonSelectedQuietMove.san))

        let attackID = "relationship:attack:piece:black:pawn:e4->piece:white:knight:f3"
        let defendID = "relationship:defend:piece:white:bishop:g2->piece:white:knight:f3"
        let attackAlias = try alias(for: attackID, in: compilation)
        let defendAlias = try alias(for: defendID, in: compilation)
        XCTAssertTrue(compilation.markdown.contains(attackAlias))
        XCTAssertTrue(compilation.markdown.contains(defendAlias))
        XCTAssertFalse(compilation.referenceBindings.contains { $0.stableID == selectedPieceDefendsOtherID })
        XCTAssertFalse(compilation.markdown.contains("White knight on f3 defends White king on g1"))
    }

    func testTentativeMoveScopeIncludesTentativeMoveAndEveryCriticalReply() throws {
        let tentativeMove = Move(from: square("f1"), to: square("e2"))
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state(
                    sideToMove: .white,
                    pieces: [
                        square("e1"): Piece(kind: .king, color: .white),
                        square("f1"): Piece(kind: .bishop, color: .white),
                        square("h8"): Piece(kind: .king, color: .black),
                        square("e8"): Piece(kind: .rook, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 4,
                selectedSquare: nil,
                tentativeMove: tentativeMove,
                latestEvent: event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
                episodeEvents: [
                    event(1, .helpOpened),
                    event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
                ]
            ),
            requestID: "neutral-tentative-bishop-block"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        XCTAssertTrue(compilation.markdown.contains("Tentative move:"))
        XCTAssertTrue(compilation.markdown.contains("Be2"))

        for reply in request.tentativeReplies {
            let alias = try alias(for: reply.id, in: compilation)
            XCTAssertTrue(compilation.markdown.contains(alias), "missing reply alias for \(reply.id)")
        }
    }

    func testInspectedReplyScopeIncludesReplyAndDirectRelationships() throws {
        let tentativeMove = Move(from: square("f1"), to: square("e2"))
        let inspectedPieceID = "piece:black:rook:e8"
        let inspectedReplyID = "move:e8-e2"
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state(
                    sideToMove: .white,
                    pieces: [
                        square("e1"): Piece(kind: .king, color: .white),
                        square("f1"): Piece(kind: .bishop, color: .white),
                        square("h8"): Piece(kind: .king, color: .black),
                        square("e8"): Piece(kind: .rook, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 5,
                selectedSquare: square("e2"),
                tentativeMove: tentativeMove,
                latestEvent: event(5, .squareInspected, [inspectedPieceID]),
                episodeEvents: [
                    event(1, .helpOpened),
                    event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
                    event(5, .squareInspected, [inspectedPieceID]),
                ]
            ),
            requestID: "neutral-inspected-reply"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        let replyAlias = try alias(for: inspectedReplyID, in: compilation)
        let directCheckAlias = try alias(
            for: "relationship:check:piece:black:rook:e8->piece:white:king:e1",
            in: compilation
        )

        XCTAssertTrue(compilation.markdown.contains("Inspected reply:"))
        XCTAssertTrue(compilation.markdown.contains(replyAlias))
        XCTAssertTrue(compilation.markdown.contains(directCheckAlias))
        XCTAssertFalse(compilation.markdown.contains("piece:white:bishop:f1"))
    }

    func testActionChosenLinesPreserveAliasedCanonicalActionReferences() throws {
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: .startingPosition(),
                learner: .white,
                positionRevision: 1,
                selectedSquare: nil,
                tentativeMove: nil,
                latestEvent: event(2, .actionChosen, ["action:looksSafe"]),
                episodeEvents: [
                    event(1, .helpOpened),
                    event(2, .actionChosen, ["action:looksSafe"]),
                ]
            ),
            requestID: "neutral-action-history"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        let looksSafeAlias = try alias(for: "action:looksSafe", in: compilation)
        XCTAssertTrue(compilation.markdown.contains("2. actionChosen [\(looksSafeAlias)]"))
        XCTAssertTrue(compilation.referenceBindings.contains {
            $0.stableID == "action:looksSafe" && $0.category == .action
        })
    }

    func testAvailableActionBindingsUseCanonicalRawValueStableIDs() throws {
        let tentativeMove = Move(from: square("f1"), to: square("e2"))
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state(
                    sideToMove: .white,
                    pieces: [
                        square("e1"): Piece(kind: .king, color: .white),
                        square("f1"): Piece(kind: .bishop, color: .white),
                        square("h8"): Piece(kind: .king, color: .black),
                        square("e8"): Piece(kind: .rook, color: .black),
                    ]
                ),
                learner: .white,
                positionRevision: 4,
                selectedSquare: nil,
                tentativeMove: tentativeMove,
                latestEvent: event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
                episodeEvents: [
                    event(1, .helpOpened),
                    event(4, .moveStaged, [ModelCoachingPositionEncoder.moveID(tentativeMove)]),
                ]
            ),
            requestID: "neutral-canonical-actions"
        )

        let compilation = ModelCoachingNeutralContextCompiler.compile(
            request,
            promptVersion: "tutor-v5"
        )

        XCTAssertTrue(compilation.referenceBindings.contains { $0.stableID == "action:hint" })
        XCTAssertTrue(compilation.referenceBindings.contains { $0.stableID == "action:playMove" })
        XCTAssertTrue(compilation.referenceBindings.contains { $0.stableID == "action:tryAnotherMove" })
        XCTAssertFalse(compilation.referenceBindings.contains { $0.stableID == "action:play-move" })
        XCTAssertFalse(compilation.referenceBindings.contains { $0.stableID == "action:try-another-move" })
    }

    func testCompilerRemainsDeterministicAcrossEightPlyHistory() {
        let moves = [
            Move(from: square("e2"), to: square("e4")),
            Move(from: square("e7"), to: square("e5")),
            Move(from: square("g1"), to: square("f3")),
            Move(from: square("b8"), to: square("c6")),
            Move(from: square("f1"), to: square("b5")),
            Move(from: square("a7"), to: square("a6")),
            Move(from: square("b5"), to: square("a4")),
            Move(from: square("g8"), to: square("f6")),
        ]
        var state = GameState.startingPosition()
        moves.forEach { state.apply($0) }
        let request = ModelCoachingNeutralRequestBuilder.build(
            snapshot: ModelCoachingNeutralSnapshot(
                committedState: state,
                learner: .white,
                positionRevision: moves.count,
                selectedSquare: nil,
                tentativeMove: nil,
                latestEvent: event(8, .helpOpened),
                episodeEvents: [event(8, .helpOpened)]
            ),
            requestID: "neutral-history"
        )

        let first = ModelCoachingNeutralContextCompiler.compile(request, promptVersion: "tutor-v5")
        let second = ModelCoachingNeutralContextCompiler.compile(request, promptVersion: "tutor-v5")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let firstBytes = try! encoder.encode(first)
        let secondBytes = try! encoder.encode(second)

        XCTAssertEqual(firstBytes, secondBytes)
        XCTAssertEqual(sha256(first.markdown), sha256(second.markdown))
        XCTAssertTrue(
            first.markdown.contains(request.gameHistory.map(\.displayNotation).joined(separator: " "))
        )
        XCTAssertEqual(first.markdown.components(separatedBy: request.position.fen).count - 1, 1)
        XCTAssertFalse(first.markdown.contains("[truncated]"))
    }

    func testCompilerSourceAndGeneratedLinesStayOutsideLegacyPolicyBoundaries() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "ChessTutor/Coaching/ModelEvaluation/ModelCoachingNeutralContextCompiler.swift"
            ),
            encoding: .utf8
        )

        [
            "ModelCoachingContextCompiler",
            "ModelCoachingSemanticOracle",
            "MaterialTacticalEvaluator",
            "CoachingStage",
            "CoachingMoveOrigin",
            "CompactContext",
        ].forEach { forbidden in
            XCTAssertFalse(source.contains(forbidden), "unexpected dependency in compiler: \(forbidden)")
        }

        let requests = [
            ModelCoachingNeutralRequestBuilder.build(
                snapshot: ModelCoachingNeutralSnapshot(
                    committedState: .startingPosition(),
                    learner: .white,
                    positionRevision: 0,
                    selectedSquare: nil,
                    tentativeMove: nil,
                    latestEvent: event(1, .helpOpened),
                    episodeEvents: [event(1, .helpOpened)]
                ),
                requestID: "audit-start"
            ),
            ModelCoachingNeutralRequestBuilder.build(
                snapshot: ModelCoachingNeutralSnapshot(
                    committedState: state(
                        sideToMove: .white,
                        pieces: [
                            square("g1"): Piece(kind: .king, color: .white),
                            square("f3"): Piece(kind: .knight, color: .white),
                            square("g2"): Piece(kind: .bishop, color: .white),
                            square("g8"): Piece(kind: .king, color: .black),
                            square("e4"): Piece(kind: .pawn, color: .black),
                        ]
                    ),
                    learner: .white,
                    positionRevision: 3,
                    selectedSquare: square("f3"),
                    tentativeMove: nil,
                    latestEvent: event(3, .pieceSelected, ["piece:white:knight:f3"]),
                    episodeEvents: [event(1, .helpOpened), event(3, .pieceSelected, ["piece:white:knight:f3"])]
                ),
                requestID: "audit-selected"
            ),
        ]

        let forbiddenPhrases = [
            "best",
            "useful",
            "important",
            "purpose",
            "needs help",
            "looks safe",
            "what to teach",
            "danger scan",
            "safe captures",
            "selected move ideas",
        ]

        for request in requests {
            let markdown = ModelCoachingNeutralContextCompiler.compile(
                request,
                promptVersion: "tutor-v5"
            ).markdown.lowercased()
            for phrase in forbiddenPhrases {
                XCTAssertFalse(markdown.contains(phrase), "unexpected phrase: \(phrase)")
            }
        }
    }

    private func markdownHeadings(in markdown: String) -> [String] {
        markdown
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("#") }
    }

    private func alias(
        for stableID: String,
        in compilation: ModelCoachingNeutralContextCompilation
    ) throws -> String {
        try XCTUnwrap(compilation.referenceBindings.first { $0.stableID == stableID }?.alias)
    }

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func event(
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

    private func state(
        sideToMove: PieceColor,
        pieces: [Square: Piece]
    ) -> GameState {
        GameState(board: Board(pieces: pieces), sideToMove: sideToMove)
    }

    private func square(_ algebraic: String) -> Square {
        let characters = Array(algebraic.utf8)
        return Square(
            file: Square.File(rawValue: Int(characters[0]) - 96)!,
            rank: Int(String(UnicodeScalar(characters[1])))!
        )
    }
}
