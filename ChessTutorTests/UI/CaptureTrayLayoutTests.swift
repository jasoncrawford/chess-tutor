import XCTest
@testable import ChessTutor

final class CaptureTrayLayoutTests: XCTestCase {
    func testCaptureGuidanceUsesPieceShapedGlowInsteadOfSquareHalo() {
        XCTAssertTrue(CaptureGuidanceStyle.current.showsPieceGlow)
        XCTAssertFalse(CaptureGuidanceStyle.current.showsSquareHalo)
    }

    func testCaptureGuidanceGlowUsesSoftUnderPieceRim() {
        XCTAssertGreaterThan(CaptureGuidanceGlowStyle.current.scale, 1)
        XCTAssertGreaterThan(CaptureGuidanceGlowStyle.current.blurRadius, 4)
        XCTAssertGreaterThanOrEqual(CaptureGuidanceGlowStyle.current.opacity, 0.84)
        XCTAssertGreaterThanOrEqual(CaptureGuidanceGlowStyle.current.rimOpacity, 0.34)
        XCTAssertLessThan(CaptureGuidanceGlowStyle.current.rimOpacity, CaptureGuidanceGlowStyle.current.opacity)
    }

    func testPlaySurfaceUsesSameLayoutInBothDeviceOrientations() {
        let landscape = PlaySurfaceLayout.make(for: CGSize(width: 1024, height: 768))
        let portrait = PlaySurfaceLayout.make(for: CGSize(width: 768, height: 1024))

        XCTAssertEqual(landscape.tabletopSize, CGSize(width: 1024, height: 768))
        XCTAssertEqual(portrait.tabletopSize, landscape.tabletopSize)
        XCTAssertEqual(landscape.boardSide, 676)
        XCTAssertEqual(portrait.boardSide, landscape.boardSide)
    }

    func testPlaySurfaceKeepsBoardAndSidebarEdgesAligned() {
        let layout = PlaySurfaceLayout.make(for: CGSize(width: 1180, height: 820))

        XCTAssertEqual(layout.boardSide, 760)
        XCTAssertEqual(layout.sidePanelHeight, layout.boardSide)
        XCTAssertEqual(layout.contentSize, CGSize(width: 1048, height: 760))
    }

    func testSidebarSegmentsFillBoardHeightWithExistingGaps() {
        let layout = SidebarColumnLayout.make(for: 760)

        XCTAssertEqual(layout.columnHeight, 760)
        XCTAssertEqual(layout.segmentLength, 245.33, accuracy: 0.01)
    }

    func testSelectedPiecePanelKeepsTwoLineSummariesWithinLandscapeSquare() {
        let columnLayout = SidebarColumnLayout.make(for: 760)
        let layout = SelectedPiecePanelLayout.current

        XCTAssertGreaterThanOrEqual(layout.remainingSlack(inPanelLength: columnLayout.segmentLength), 12)
    }

    func testSelectedPiecePanelCentersSelectedPieceContentVertically() {
        let columnLayout = SidebarColumnLayout.make(for: 760)
        let layout = SelectedPiecePanelLayout.current
        let expectedInset = layout.remainingSlack(inPanelLength: columnLayout.segmentLength) / 2

        XCTAssertEqual(layout.verticalInset(inPanelLength: columnLayout.segmentLength), expectedInset, accuracy: 0.01)
    }

    func testCaptureTrayStartsWithLargePieces() {
        let layout = CaptureTrayLayout.make(for: 3, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 3)
        XCTAssertEqual(layout.pieceSize, 56)
    }

    func testCaptureTrayShrinksSingleRowBeforeWrapping() {
        let layout = CaptureTrayLayout.make(for: 5, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 5)
        XCTAssertEqual(layout.pieceSize, 37.6, accuracy: 0.01)
    }

    func testCaptureTrayWrapsToAtLeastFourColumns() {
        let layout = CaptureTrayLayout.make(for: 6, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 6)
        XCTAssertEqual(layout.pieceSize, 30.67, accuracy: 0.01)
    }

    func testCaptureTrayFillsRowsBeforeWrappingAgain() {
        let layout = CaptureTrayLayout.make(for: 15, in: CGSize(width: 204, height: 85))

        XCTAssertEqual(layout.columns, 8)
        XCTAssertEqual(layout.pieceSize, 22)
    }

    func testCaptureTrayReservesSpaceForCountBadge() {
        let layout = CaptureTrayLayout.make(
            widthMultipliers: [
                CaptureTrayGroup.countBadgeWidthMultiplier,
                1,
                1,
                1,
                1
            ],
            in: CGSize(width: 204, height: 85)
        )

        XCTAssertEqual(layout.pieceSize, 34.94, accuracy: 0.01)
        XCTAssertEqualArray(layout.itemWidths, [48.22, 34.94, 34.94, 34.94, 34.94], accuracy: 0.01)
    }

    func testCaptureTrayKeepsTwoGroupsCompact() {
        let layout = CaptureTrayLayout.make(
            widthMultipliers: [1, 1],
            in: CGSize(width: 204, height: 85)
        )

        XCTAssertEqual(layout.pieceSize, 56)
        XCTAssertEqual(layout.itemWidths, [56, 56])
    }

    func testCaptureTrayGroupsDuplicatePieceKindsInFirstOccurrenceOrder() {
        let groups = CaptureTrayGroup.groups(for: [
            captured(.bishop, id: "bishop-1"),
            captured(.pawn, id: "pawn-1"),
            captured(.bishop, id: "bishop-2"),
            captured(.knight, id: "knight-1")
        ])

        XCTAssertEqual(groups.map(\.kind), [.bishop, .pawn, .knight])
        XCTAssertEqual(groups.map { $0.pieces.map(\.id) }, [
            ["bishop-1", "bishop-2"],
            ["pawn-1"],
            ["knight-1"]
        ])
    }

    func testCaptureTrayShowsCountsAfterTwoPiecesOfAnyKind() {
        let groups = CaptureTrayGroup.groups(for: [
            captured(.queen, id: "queen-1"),
            captured(.queen, id: "queen-2"),
            captured(.queen, id: "queen-3")
        ])

        XCTAssertEqual(groups.first?.countText, "x3")
    }

    func testCaptureTrayDoesNotShowCountsForTwoPieces() {
        let twoPawnGroup = CaptureTrayGroup.groups(for: [
            captured(.pawn, id: "pawn-1"),
            captured(.pawn, id: "pawn-2")
        ])
        let rookGroup = CaptureTrayGroup.groups(for: [
            captured(.rook, id: "rook-1"),
            captured(.rook, id: "rook-2")
        ])

        XCTAssertNil(twoPawnGroup.first?.countText)
        XCTAssertNil(rookGroup.first?.countText)
    }

    private func captured(_ kind: Piece.Kind, id: String) -> CapturedPiece {
        CapturedPiece(
            id: id,
            piece: Piece(kind: kind, color: .black),
            capturedAt: Square(file: .a, rank: 1),
            state: .committed
        )
    }

    private func XCTAssertEqualArray(
        _ actual: [CGFloat],
        _ expected: [CGFloat],
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualValue, expectedValue) in zip(actual, expected) {
            XCTAssertEqual(actualValue, expectedValue, accuracy: accuracy, file: file, line: line)
        }
    }
}
