import UIKit
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

    func testPieceAssetsAreBundled() {
        for piece in allPieces {
            XCTAssertNotNil(
                UIImage(named: piece.assetName, in: Bundle.main, compatibleWith: nil),
                "Missing bundled image asset named \(piece.assetName)"
            )
        }
    }

    func testChessArtLicenseNoticeIsBundled() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "ChessArt-MIT", withExtension: "txt"),
            "Missing bundled Chess Art MIT license notice"
        )
    }

    func testAboutAttributionNamesCelticPieceSource() {
        let aboutText = [
            AboutAttribution.pieceCredit,
            AboutAttribution.pieceSource,
            AboutAttribution.pieceLicense,
        ].joined(separator: " ")

        XCTAssertTrue(aboutText.contains("Maurizio Monge"))
        XCTAssertTrue(aboutText.contains("Chess Art"))
        XCTAssertTrue(aboutText.contains("MIT License"))
    }

    func testAppBuildInfoFormatsVersionBuildAndRevision() {
        let buildInfo = AppBuildInfo(
            version: "1.2",
            build: "45",
            revision: "5d254f957834"
        )

        XCTAssertEqual(buildInfo.versionDisplayText, "Version 1.2 (Build 45)")
        XCTAssertEqual(buildInfo.revisionDisplayText, "Revision 5d254f957834")
    }

    func testAppBuildInfoFallsBackWhenRevisionIsMissing() {
        let buildInfo = AppBuildInfo(version: "1.2", build: "45", revision: nil)

        XCTAssertEqual(buildInfo.versionDisplayText, "Version 1.2 (Build 45)")
        XCTAssertEqual(buildInfo.revisionDisplayText, "Revision Unknown")
    }

    func testGameControlsPresentationKeepsRareActionsVisibleButSecondaryDuringPlay() {
        let presentation = GameControlsPresentation(result: .ongoing)

        XCTAssertEqual(presentation.primaryAction, .done)
        XCTAssertEqual(presentation.secondaryActions, [.newGame, .about])
    }

    func testGameControlsPresentationPromotesNewGameAfterCheckmate() {
        let presentation = GameControlsPresentation(result: .checkmate(winner: .black))

        XCTAssertEqual(presentation.primaryAction, .newGame)
        XCTAssertEqual(presentation.secondaryActions, [.about])
    }

    private var allPieces: [Piece] {
        [
            Piece(kind: .king, color: .white),
            Piece(kind: .queen, color: .white),
            Piece(kind: .rook, color: .white),
            Piece(kind: .bishop, color: .white),
            Piece(kind: .knight, color: .white),
            Piece(kind: .pawn, color: .white),
            Piece(kind: .king, color: .black),
            Piece(kind: .queen, color: .black),
            Piece(kind: .rook, color: .black),
            Piece(kind: .bishop, color: .black),
            Piece(kind: .knight, color: .black),
            Piece(kind: .pawn, color: .black),
        ]
    }
}
