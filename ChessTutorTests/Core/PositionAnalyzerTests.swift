import XCTest
@testable import ChessTutor

final class PositionAnalyzerTests: XCTestCase {
    func testIndexesMultipleThreatsAndLegalSupportersWithoutMutatingState() {
        let target = Square(file: .d, rank: 4)
        let supportingRook = Square(file: .d, rank: 1)
        let bishopAttacker = Square(file: .b, rank: 6)
        let knightAttacker = Square(file: .f, rank: 5)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .a, rank: 1): Piece(kind: .king, color: .white),
                    target: Piece(kind: .bishop, color: .white),
                    supportingRook: Piece(kind: .rook, color: .white),
                    Square(file: .h, rank: 8): Piece(kind: .king, color: .black),
                    bishopAttacker: Piece(kind: .bishop, color: .black),
                    knightAttacker: Piece(kind: .knight, color: .black),
                ]
            ),
            sideToMove: .white
        )
        let before = state

        let analysis = PositionAnalyzer.analyze(state)

        XCTAssertEqual(
            Set(analysis.threats(targeting: target).map(\.source)),
            [bishopAttacker, knightAttacker]
        )
        XCTAssertEqual(analysis.supporters(of: target), [supportingRook])
        XCTAssertTrue(analysis.coverage(for: .white).contains(target))
        XCTAssertTrue(analysis.coverage(for: .black).contains(target))
        XCTAssertEqual(state, before)
    }

    func testPinnedPieceKeepsBroadCoverageWithoutCreatingIllegalThreat() {
        let pinnedRook = Square(file: .e, rank: 2)
        let target = Square(file: .d, rank: 2)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    pinnedRook: Piece(kind: .rook, color: .white),
                    target: Piece(kind: .pawn, color: .black),
                    Square(file: .e, rank: 8): Piece(kind: .rook, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let analysis = PositionAnalyzer.analyze(state)

        XCTAssertTrue(analysis.coverage(for: .white).contains(target))
        XCTAssertFalse(
            analysis.threats(targeting: target).contains { relation in
                relation.source == pinnedRook
            }
        )
    }

    func testEnPassantThreatTargetsPawnWhileDestinationIsLandingSquare() {
        let whitePawn = Square(file: .e, rank: 5)
        let blackPawn = Square(file: .d, rank: 5)
        let landing = Square(file: .d, rank: 6)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    whitePawn: Piece(kind: .pawn, color: .white),
                    blackPawn: Piece(kind: .pawn, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white,
            enPassantTarget: landing
        )

        let relation = PositionAnalyzer.analyze(state).threats(targeting: blackPawn).first

        XCTAssertEqual(
            relation,
            ThreatRelation(source: whitePawn, target: blackPawn, destination: landing, color: .white)
        )
    }

    func testCastlingIsCoverageButNotThreatOrSupport() {
        let king = Square(file: .e, rank: 1)
        let destination = Square(file: .g, rank: 1)
        let state = GameState(
            board: Board(
                pieces: [
                    king: Piece(kind: .king, color: .white),
                    Square(file: .h, rank: 1): Piece(kind: .rook, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white,
            castlingRights: CastlingRights(whiteKingside: true)
        )

        let analysis = PositionAnalyzer.analyze(state)

        XCTAssertTrue(
            analysis.allowedMoves(from: king).contains(
                Move(from: king, to: destination, special: .castleKingside)
            )
        )
        XCTAssertTrue(analysis.coverage(for: .white).contains(destination))
        XCTAssertTrue(analysis.threats(targeting: destination).isEmpty)
        XCTAssertTrue(analysis.supporters(of: destination).isEmpty)
    }

    func testPromotionMovesProduceOneCoverageSquare() {
        let pawn = Square(file: .a, rank: 7)
        let destination = Square(file: .a, rank: 8)
        let state = GameState(
            board: Board(
                pieces: [
                    Square(file: .e, rank: 1): Piece(kind: .king, color: .white),
                    pawn: Piece(kind: .pawn, color: .white),
                    Square(file: .e, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let analysis = PositionAnalyzer.analyze(state)

        XCTAssertEqual(analysis.allowedMoves(from: pawn).filter { $0.to == destination }.count, 4)
        XCTAssertTrue(analysis.coverage(for: .white).contains(destination))
    }

    func testCheckedKingIsThreatenedButNeverDefended() {
        let whiteKing = Square(file: .e, rank: 1)
        let checkingRook = Square(file: .e, rank: 8)
        let state = GameState(
            board: Board(
                pieces: [
                    whiteKing: Piece(kind: .king, color: .white),
                    Square(file: .f, rank: 3): Piece(kind: .knight, color: .white),
                    checkingRook: Piece(kind: .rook, color: .black),
                    Square(file: .a, rank: 8): Piece(kind: .king, color: .black),
                ]
            ),
            sideToMove: .white
        )

        let analysis = PositionAnalyzer.analyze(state)

        XCTAssertEqual(Set(analysis.threats(targeting: whiteKing).map(\.source)), [checkingRook])
        XCTAssertFalse(analysis.defendedSquares.contains(whiteKing))
    }

    func testAnalyzerAllowedMovesMatchGeneratorForEverySource() {
        let state = GameState.startingPosition()
        let analysis = PositionAnalyzer.analyze(state)

        for (source, piece) in state.board.pieces {
            XCTAssertEqual(
                Set(analysis.allowedMoves(from: source)),
                Set(LegalMoveGenerator.allowedMoves(for: source, by: piece.color, in: state))
            )

            let expectedCoverage = Set(
                LegalMoveGenerator.allowedMoves(for: source, by: piece.color, in: state).map(\.to)
            ).union(
                LegalMoveGenerator.controlledSquares(for: source, by: piece.color, in: state)
            )
            XCTAssertTrue(expectedCoverage.isSubset(of: analysis.coverage(for: piece.color)))
        }
    }
}
