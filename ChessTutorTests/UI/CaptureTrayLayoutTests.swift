import XCTest
@testable import ChessTutor

final class CaptureTrayLayoutTests: XCTestCase {
    func testBoardCoordinateLabelsAreInsetClearOfFrame() {
        XCTAssertEqual(BoardCoordinateLabelStyle.current.padding, 9, accuracy: 0.01)
        XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.padding, 5)
        XCTAssertLessThan(BoardCoordinateLabelStyle.current.padding, 13)
    }

    func testBoardCoordinateHighlightsUseSeparateLightSquareContrast() {
        XCTAssertEqual(BoardCoordinateLabelStyle.current.normalOpacity, 0.60, accuracy: 0.01)
        XCTAssertEqual(BoardCoordinateLabelStyle.current.selectedLightSquareColor, .darkSquare)
        XCTAssertEqual(BoardCoordinateLabelStyle.current.selectedDarkSquareColor, .selectedSquare)
        XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.selectedLightSquareOpacity, 0.88)
        XCTAssertGreaterThan(BoardCoordinateLabelStyle.current.selectedDarkSquareOpacity, 0.88)
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

    func testSidebarSegmentsLeaveRoomForUtilityStripWithinBoardHeight() {
        let layout = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)

        XCTAssertEqual(layout.columnHeight, 760)
        XCTAssertEqual(layout.size(for: .messageAndDone).height, 192.64, accuracy: 0.01)
        XCTAssertEqual(layout.size(for: .selectedPiece).height, 240, accuracy: 0.01)
        XCTAssertEqual(layout.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
        XCTAssertEqual(layout.utilityStripHeight, 40)
        XCTAssertTrue(layout.showsColumnUtilityStrip)
        XCTAssertFalse(layout.showsCapturedPanelUtilityFooter)
    }

    func testHorizontalSidebarPutsUtilityActionsInsideCapturedPanel() {
        let layout = SidebarColumnLayout.make(for: 760, presentation: .horizontalSegments)

        XCTAssertEqual(layout.columnHeight, 760)
        XCTAssertEqual(layout.size(for: .capturedPieces).width, 246.67, accuracy: 0.01)
        XCTAssertEqual(layout.size(for: .capturedPieces).height, 246.67, accuracy: 0.01)
        XCTAssertEqual(layout.utilityStripHeight, 0)
        XCTAssertFalse(layout.showsColumnUtilityStrip)
        XCTAssertTrue(layout.showsCapturedPanelUtilityFooter)
        XCTAssertEqual(layout.capturedPanelUtilityFooterHeight, 36)
    }

    func testCoachingRegionDoesNotChangeCapturedPanelOrUtilityDimensions() {
        let vertical = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let horizontal = SidebarColumnLayout.make(for: 760, presentation: .horizontalSegments)

        XCTAssertEqual(vertical.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
        XCTAssertEqual(vertical.utilityStripHeight, 40, accuracy: 0.01)
        XCTAssertEqual(horizontal.size(for: .capturedPieces).width, 246.67, accuracy: 0.01)
        XCTAssertEqual(horizontal.size(for: .capturedPieces).height, 246.67, accuracy: 0.01)
        XCTAssertEqual(horizontal.capturedPanelUtilityFooterHeight, 36, accuracy: 0.01)
    }

    func testSelectedPiecePanelKeepsTwoLineSummariesWithinLandscapeSquare() {
        let columnLayout = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let layout = SelectedPiecePanelLayout.current

        XCTAssertGreaterThanOrEqual(layout.remainingSlack(inPanelLength: columnLayout.segmentLength), 12)
    }

    func testSelectedPiecePanelLayoutUsesInlineSquareBadge() {
        let layout = SelectedPiecePanelLayout.current

        XCTAssertEqual(layout.squareBadgeHeight, 22, accuracy: 0.01)
        XCTAssertEqual(layout.requiredContentHeight, 164, accuracy: 0.01)
    }

    func testSelectedPiecePanelCentersSelectedPieceContentVertically() {
        let columnLayout = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let layout = SelectedPiecePanelLayout.current
        let expectedInset = layout.remainingSlack(inPanelLength: columnLayout.segmentLength) / 2

        XCTAssertEqual(layout.verticalInset(inPanelLength: columnLayout.segmentLength), expectedInset, accuracy: 0.01)
    }

    func testSelectedPiecePanelFitsCoverageButtonWithoutGrowingPanel() {
        let column = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let layout = SelectedPiecePanelLayout.current

        XCTAssertEqual(column.size(for: .selectedPiece).height, 240, accuracy: 0.01)
        XCTAssertEqual(column.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
        XCTAssertEqual(layout.coverageButtonHeight, 36, accuracy: 0.01)
        XCTAssertEqual(layout.coverageButtonSpacing, 8, accuracy: 0.01)
        XCTAssertEqual(layout.coverageFooterHeight, 44, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(
            column.size(for: .selectedPiece).height - SidebarPanelMetrics.contentPadding * 2,
            layout.requiredContentHeight + layout.coverageButtonSpacing + layout.coverageButtonHeight
        )
    }

    func testCoverageButtonCopyMatchesExpandedState() {
        XCTAssertEqual(CoverageButtonPresentation(isVisible: false).title, "Show coverage")
        XCTAssertEqual(CoverageButtonPresentation(isVisible: true).title, "Hide coverage")
        XCTAssertEqual(CoverageButtonPresentation(isVisible: false).systemImage, "eye")
        XCTAssertEqual(CoverageButtonPresentation(isVisible: true).systemImage, "eye.slash")
    }

    func testSelectedPieceContentCompressesToFitSmallestHorizontalPanelWithCoverage() {
        let column = SidebarColumnLayout.make(for: 676, presentation: .horizontalSegments)
        let layout = SelectedPiecePanelLayout.current
        let contentHeight = column.size(for: .selectedPiece).height
            - SidebarPanelMetrics.contentPadding * 2
            - layout.coverageButtonSpacing
            - layout.coverageButtonHeight
        let fittedIconHeight = layout.fittedIconSlotHeight(inContentLength: contentHeight)

        XCTAssertLessThan(fittedIconHeight, layout.iconSlotHeight)
        XCTAssertGreaterThanOrEqual(fittedIconHeight, 68)
        XCTAssertLessThanOrEqual(
            fittedIconHeight + layout.selectedPieceSpacing + layout.textSlotHeight,
            contentHeight
        )
    }

    func testSelectedPiecePanelReservesFullHeightForTwoLineMovementSummary() {
        XCTAssertGreaterThanOrEqual(
            SelectedPiecePanelLayout.current.twoLineSummaryHeight,
            41
        )
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
