import CoreGraphics
import XCTest
@testable import ChessTutor

final class BoardGuidanceStyleTests: XCTestCase {
    func testCoverageSurfaceClassifiesEveryReachCombination() {
        XCTAssertEqual(
            CoverageSurfaceState(sideToMoveCovers: false, otherSideCovers: false),
            .neither
        )
        XCTAssertEqual(
            CoverageSurfaceState(sideToMoveCovers: true, otherSideCovers: false),
            .sideToMoveOnly
        )
        XCTAssertEqual(
            CoverageSurfaceState(sideToMoveCovers: false, otherSideCovers: true),
            .otherSideOnly
        )
        XCTAssertEqual(
            CoverageSurfaceState(sideToMoveCovers: true, otherSideCovers: true),
            .both
        )
    }

    func testTrajectoryLayoutKeepsArrowheadSmallRelativeToBoardCell() {
        let layout = GuidancePathLayout.make(
            from: CGPoint(x: 42, y: 42),
            to: CGPoint(x: 210, y: 42),
            cellSize: 84
        )

        XCTAssertLessThanOrEqual(layout.arrowheadLength, 84 * 0.16)
        XCTAssertGreaterThan(layout.shaftLength, layout.arrowheadLength * 4)
    }

    func testTrajectoryStopsClearOfPieceCenters() {
        let source = CGPoint(x: 42, y: 42)
        let destination = CGPoint(x: 126, y: 42)

        let layout = GuidancePathLayout.make(
            from: source,
            to: destination,
            cellSize: 84
        )

        XCTAssertGreaterThan(layout.start.x, source.x)
        XCTAssertLessThan(layout.tip.x, destination.x)
        XCTAssertGreaterThan(layout.shaftLength, 0)
        XCTAssertFalse(layout.arrowhead.contains(layout.start))
    }

    func testBoardGuidanceGeometryMapsSquaresToCellCenters() {
        let geometry = BoardGuidanceGeometry(
            side: 672,
            origin: CGPoint(x: 12, y: 20),
            viewingAngle: .normal
        )

        XCTAssertEqual(
            geometry.center(of: Square(file: .a, rank: 8)),
            CGPoint(x: 54, y: 62)
        )
        XCTAssertEqual(
            geometry.center(of: Square(file: .h, rank: 1)),
            CGPoint(x: 642, y: 650)
        )
    }

    func testReadableFootOffsetStaysBelowPieceThroughTabletopRotations() {
        let distance: CGFloat = 24
        let expectations: [(BoardViewingAngle, CGPoint)] = [
            (.normal, CGPoint(x: 0, y: 24)),
            (.clockwiseQuarterTurn, CGPoint(x: 24, y: 0)),
            (.halfTurn, CGPoint(x: 0, y: -24)),
            (.counterclockwiseQuarterTurn, CGPoint(x: -24, y: 0)),
        ]

        for (viewingAngle, expected) in expectations {
            let geometry = BoardGuidanceGeometry(
                side: 672,
                origin: .zero,
                viewingAngle: viewingAngle
            )
            let actual = geometry.readableFootOffset(distance: distance)

            XCTAssertEqual(actual.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.001)
        }
    }

    func testAmbientDangerBadgeIsMuchSmallerThanProminentBurst() {
        let style = BoardGuidanceStyle.current

        XCTAssertLessThanOrEqual(style.ambientDangerBadgeScale, 0.30)
        XCTAssertGreaterThan(
            style.prominentDangerBurstScale,
            style.ambientDangerBadgeScale * 2.5
        )
        XCTAssertGreaterThan(style.shieldScale, 0.16)
    }

    func testCompactDangerAndShieldShareReadableFootWhileProminentDangerStaysCentered() {
        let pieceCenter = CGPoint(x: 42, y: 42)
        let readableFootOffset = CGPoint(x: 0, y: 24)

        let layout = BoardPieceMarkerLayout.make(
            pieceCenter: pieceCenter,
            readableFootOffset: readableFootOffset
        )

        XCTAssertEqual(layout.prominentDangerCenter, pieceCenter)
        XCTAssertEqual(layout.ambientDangerCenter, CGPoint(x: 42, y: 66))
        XCTAssertEqual(layout.defenseCenter, layout.ambientDangerCenter)
    }

    func testCompactDangerIsForegroundAndProminentDangerIsBackground() {
        XCTAssertLessThan(
            BoardPieceMarkerLayer.prominentDanger.zIndex,
            BoardPieceMarkerLayer.piece.zIndex
        )
        XCTAssertGreaterThan(
            BoardPieceMarkerLayer.foregroundStatus.zIndex,
            BoardPieceMarkerLayer.piece.zIndex
        )
    }
}
