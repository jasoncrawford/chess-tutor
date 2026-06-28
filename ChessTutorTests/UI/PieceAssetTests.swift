import XCTest
@testable import ChessTutor

final class PieceAssetTests: XCTestCase {
    func testWhitePieceAssetNames() {
        XCTAssertEqual(Piece(kind: .king, color: .white).assetName, "PieceWhiteKing")
        XCTAssertEqual(Piece(kind: .queen, color: .white).assetName, "PieceWhiteQueen")
        XCTAssertEqual(Piece(kind: .rook, color: .white).assetName, "PieceWhiteRook")
        XCTAssertEqual(Piece(kind: .bishop, color: .white).assetName, "PieceWhiteBishop")
        XCTAssertEqual(Piece(kind: .knight, color: .white).assetName, "PieceWhiteKnight")
        XCTAssertEqual(Piece(kind: .pawn, color: .white).assetName, "PieceWhitePawn")
    }

    func testBlackPieceAssetNames() {
        XCTAssertEqual(Piece(kind: .king, color: .black).assetName, "PieceBlackKing")
        XCTAssertEqual(Piece(kind: .queen, color: .black).assetName, "PieceBlackQueen")
        XCTAssertEqual(Piece(kind: .rook, color: .black).assetName, "PieceBlackRook")
        XCTAssertEqual(Piece(kind: .bishop, color: .black).assetName, "PieceBlackBishop")
        XCTAssertEqual(Piece(kind: .knight, color: .black).assetName, "PieceBlackKnight")
        XCTAssertEqual(Piece(kind: .pawn, color: .black).assetName, "PieceBlackPawn")
    }
}
