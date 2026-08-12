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
    private func renderedCoveragePixels(
        state: CoverageSurfaceState,
        baseColor: Color
    ) -> [[UInt8]] {
        let side = 16
        let renderer = ImageRenderer(
            content: ZStack {
                Rectangle().fill(baseColor)
                CoverageSurfaceView(state: state)
            }
            .frame(width: CGFloat(side), height: CGFloat(side))
        )
        renderer.scale = 1

        guard let image = renderer.uiImage?.cgImage else {
            XCTFail("Coverage surface did not render")
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

        let points = state == .both ? [(3, 3), (12, 12)] : [(8, 8)]
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
