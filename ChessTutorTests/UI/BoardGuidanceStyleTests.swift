import CoreGraphics
import SwiftUI
import UIKit
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

    @MainActor
    func testCoverageSurfaceAppearanceDoesNotDependOnUnderlyingSquareColor() {
        let states: [CoverageSurfaceState] = [
            .neither,
            .sideToMoveOnly,
            .otherSideOnly,
            .both,
        ]

        for state in states {
            XCTAssertEqual(
                renderedCoveragePixels(state: state, baseColor: AppTheme.lightSquare),
                renderedCoveragePixels(state: state, baseColor: AppTheme.darkSquare),
                "\(state) inherited the underlying board-square color"
            )
        }
    }

    @MainActor
    func testCoverageBoardRendersEveryInternalSquareBoundary() {
        let session = GameSession(
            state: GameState(board: Board(), sideToMove: .white)
        )
        session.toggleCoverage()
        let side = 128
        let interiorPoint = (24, 24)
        let internalBoundaryPoints = (1..<8).flatMap { index in
            let coordinate = index * side / 8
            return [(coordinate, 24), (24, coordinate)]
        }
        let points = [interiorPoint] + internalBoundaryPoints
        let pixels = renderedPixels(
            content: CoverageBoardRenderingHarness(session: session),
            side: side,
            points: points
        )
        let interiorPixel = pixels[0]
        let boundaryPixels = pixels.dropFirst()

        XCTAssertTrue(
            boundaryPixels.allSatisfy { pixel in
                let redShift = Int(pixel[0]) - Int(interiorPixel[0])
                let greenShift = Int(pixel[1]) - Int(interiorPixel[1])
                let blueShift = Int(pixel[2]) - Int(interiorPixel[2])
                return greenShift < redShift && blueShift < redShift
            },
            "Every internal boundary should carry the board-frame tint"
        )
    }

    @MainActor
    private func renderedCoveragePixels(
        state: CoverageSurfaceState,
        baseColor: Color
    ) -> [[UInt8]] {
        let side = 16
        let points = state == .both ? [(3, 3), (12, 12)] : [(8, 8)]
        return renderedPixels(
            content: ZStack {
                Rectangle().fill(baseColor)
                CoverageSurfaceView(state: state)
            },
            side: side,
            points: points
        )
    }

    @MainActor
    private func renderedPixels<Content: View>(
        content: Content,
        side: Int,
        points: [(Int, Int)]
    ) -> [[UInt8]] {
        let renderer = ImageRenderer(
            content: content.frame(width: CGFloat(side), height: CGFloat(side))
        )
        renderer.scale = 1

        guard let image = renderer.uiImage?.cgImage else {
            XCTFail("View did not render")
            return []
        }

        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        return points.map { x, y in
            let offset = (y * side + x) * 4
            return Array(bytes[offset..<(offset + 4)])
        }
    }

    func testCoverageRenderingPolicyQuietsAmbientBoardButKeepsContextProminent() {
        let coveragePolicy = CoverageMapRenderingPolicy(isCoverageVisible: true)

        XCTAssertFalse(coveragePolicy.showsCoordinates)
        XCTAssertFalse(coveragePolicy.showsAmbientThreats)
        XCTAssertEqual(coveragePolicy.pieceOpacity(isContextual: true), 1)
        XCTAssertLessThan(coveragePolicy.pieceOpacity(isContextual: false), 1)

        let normalPolicy = CoverageMapRenderingPolicy(isCoverageVisible: false)
        XCTAssertTrue(normalPolicy.showsCoordinates)
        XCTAssertTrue(normalPolicy.showsAmbientThreats)
        XCTAssertEqual(normalPolicy.pieceOpacity(isContextual: false), 1)
    }

    func testCoverageContextContainsOnlySelectedRelationships() {
        let selected = Square(file: .c, rank: 4)
        let destination = Square(file: .f, rank: 7)
        let attacker = Square(file: .b, rank: 6)
        let supporter = Square(file: .e, rank: 3)
        let unrelated = Square(file: .h, rank: 8)
        let guidance = BoardGuidancePresentation(
            sideToMove: .white,
            threatenedSquares: [selected],
            prominentThreatSquares: [selected],
            defendedSquares: [selected],
            visibleDefenseSquares: [selected],
            selectedSquare: selected,
            selectedPaths: [
                BoardGuidancePath(
                    source: selected,
                    destination: destination,
                    captureSquare: destination,
                    color: .white,
                    role: .allowed
                ),
                BoardGuidancePath(
                    source: attacker,
                    destination: selected,
                    captureSquare: selected,
                    color: .black,
                    role: .attacker
                ),
            ],
            supporterSquares: [supporter],
            coverage: BoardCoveragePresentation(
                sideToMove: .white,
                sideToMoveSquares: [selected, destination, unrelated],
                otherSideSquares: [selected, attacker]
            )
        )

        let contextualSquares = CoverageContext.squares(in: guidance)

        XCTAssertTrue(contextualSquares.isSuperset(of: [
            selected,
            destination,
            attacker,
            supporter,
        ]))
        XCTAssertFalse(contextualSquares.contains(unrelated))
    }

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

@MainActor
private struct CoverageBoardRenderingHarness: View {
    @Namespace private var captureNamespace
    let session: GameSession

    var body: some View {
        ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: .normal,
            readableRotationDegrees: 0,
            isCaptureTestModeEnabled: false
        )
    }
}
