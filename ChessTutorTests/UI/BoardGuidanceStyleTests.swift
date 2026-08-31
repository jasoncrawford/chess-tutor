import CoreGraphics
import XCTest
@testable import ChessTutor

final class BoardGuidanceStyleTests: XCTestCase {
    func testTrajectoryRenderingKeepsOnlyFarthestPathOnEachRay() {
        let source = Square(file: .d, rank: 4)
        let rightNear = guidancePath(
            from: source,
            to: Square(file: .f, rank: 4)
        )
        let rightFar = guidancePath(
            from: source,
            to: Square(file: .h, rank: 4),
            captureSquare: Square(file: .h, rank: 4)
        )
        let left = guidancePath(
            from: source,
            to: Square(file: .a, rank: 4)
        )
        let up = guidancePath(
            from: source,
            to: Square(file: .d, rank: 8)
        )

        let visible = GuidancePathRenderingPolicy.visiblePaths(
            in: [rightNear, rightFar, left, up]
        )

        XCTAssertEqual(visible, [rightFar, left, up])
        XCTAssertEqual(
            visible.first(where: { $0.destination == rightFar.destination })?.captureSquare,
            rightFar.captureSquare
        )
    }

    func testTrajectoryRenderingDoesNotMergeDifferentSourcesRolesOrColors() {
        let source = Square(file: .d, rank: 4)
        let allowedWhite = guidancePath(
            from: source,
            to: Square(file: .h, rank: 4)
        )
        let attackerWhite = guidancePath(
            from: source,
            to: Square(file: .g, rank: 4),
            role: .attacker
        )
        let allowedBlack = guidancePath(
            from: source,
            to: Square(file: .f, rank: 4),
            color: .black
        )
        let otherSource = guidancePath(
            from: Square(file: .c, rank: 4),
            to: Square(file: .h, rank: 4)
        )

        let visible = GuidancePathRenderingPolicy.visiblePaths(
            in: [allowedWhite, attackerWhite, allowedBlack, otherSource]
        )

        XCTAssertEqual(visible, [allowedWhite, attackerWhite, allowedBlack, otherSource])
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
        let destination = CGPoint(x: 294, y: 42)

        let layout = GuidancePathLayout.make(
            from: source,
            to: destination,
            cellSize: 84
        )

        XCTAssertGreaterThan(layout.start.x, source.x)
        XCTAssertLessThan(layout.tip.x, destination.x)
        XCTAssertEqual(
            destination.x - layout.tip.x,
            84 * 0.22,
            accuracy: 0.001
        )
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

    private func guidancePath(
        from source: Square,
        to destination: Square,
        captureSquare: Square? = nil,
        color: PieceColor = .white,
        role: BoardGuidancePath.Role = .allowed
    ) -> BoardGuidancePath {
        BoardGuidancePath(
            source: source,
            destination: destination,
            captureSquare: captureSquare,
            color: color,
            role: role
        )
    }
}
