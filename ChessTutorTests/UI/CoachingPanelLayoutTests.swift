import XCTest
@testable import ChessTutor

final class CoachingPanelLayoutTests: XCTestCase {
    func testVerticalCoachingRegionSpansMessageAndSelectedSlots() {
        let sidebar = SidebarColumnLayout.make(for: 760, presentation: .verticalColumn)
        let layout = CoachingPanelLayout.make(sidebar: sidebar)

        XCTAssertEqual(
            layout.tabletopRegionSize.height,
            sidebar.size(for: .messageAndDone).height
                + SidebarColumnLayout.segmentSpacing
                + sidebar.size(for: .selectedPiece).height,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.physicalRegionSize, layout.tabletopRegionSize)
        XCTAssertEqual(layout.physicalAxis, .vertical)
        XCTAssertEqual(sidebar.size(for: .capturedPieces).height, 255.36, accuracy: 0.01)
    }

    func testHorizontalCoachingRegionUsesTwoAdjacentSlots() {
        let sidebar = SidebarColumnLayout.make(for: 760, presentation: .horizontalSegments)
        let segment = sidebar.size(for: .selectedPiece)
        let layout = CoachingPanelLayout.make(sidebar: sidebar)

        XCTAssertEqual(
            layout.tabletopRegionSize.height,
            segment.height * 2 + SidebarColumnLayout.segmentSpacing,
            accuracy: 0.01
        )
        XCTAssertEqual(
            layout.physicalRegionSize.width,
            segment.width * 2 + SidebarColumnLayout.segmentSpacing,
            accuracy: 0.01
        )
        XCTAssertEqual(layout.physicalRegionSize.height, segment.height, accuracy: 0.01)
        XCTAssertEqual(layout.physicalAxis, .horizontal)
        XCTAssertTrue(sidebar.showsCapturedPanelUtilityFooter)
    }

    func testCoachingRegionsKeepCapturedPiecesFirstInReversedTabletopOrder() {
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.clockwiseQuarterTurn.sidebarSegmentsInTabletopOrder
            ),
            [.capturedPieces, .coaching]
        )
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.halfTurn.sidebarSegmentsInTabletopOrder
            ),
            [.capturedPieces, .coaching]
        )
    }

    func testCoachingRegionsKeepCapturedPiecesLastInForwardTabletopOrder() {
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.normal.sidebarSegmentsInTabletopOrder
            ),
            [.coaching, .capturedPieces]
        )
        XCTAssertEqual(
            CoachingPanelLayout.sidebarRegions(
                inTabletopOrder: BoardViewingAngle.counterclockwiseQuarterTurn.sidebarSegmentsInTabletopOrder
            ),
            [.coaching, .capturedPieces]
        )
    }

    func testConversationPrecedesActionsInAccessibilityOrder() {
        XCTAssertEqual(
            CoachingPanelAccessibilityOrder.elements,
            [.headline, .instruction, .routine, .actions]
        )
        XCTAssertEqual(CoachingPanelAccessibilityOrder.sortPriority(for: .headline), 4)
        XCTAssertEqual(CoachingPanelAccessibilityOrder.sortPriority(for: .instruction), 3)
        XCTAssertEqual(CoachingPanelAccessibilityOrder.sortPriority(for: .routine), 2)
        XCTAssertEqual(CoachingPanelAccessibilityOrder.sortPriority(for: .actions), 1)
    }

    func testAuthoredActionOrderAndProminenceReachPanelUnchanged() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .safeLocate,
                actions: [.noAnswer, .hint, .stop]
            )
        )

        XCTAssertEqual(presentation.actions.map(\.action), [.noAnswer, .hint, .stop])
        XCTAssertEqual(presentation.actions.map(\.prominence), [.primary, .secondary, .quiet])
    }

    func testCompletionKeepsDoneKeepLookingAndStopActions() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .complete(origin: .wake, idea: .develops(piece: .knight)),
                actions: [.done, .keepLooking, .stop]
            )
        )

        XCTAssertEqual(presentation.actions.map(\.action), [.done, .keepLooking, .stop])
        XCTAssertEqual(presentation.actions.map(\.prominence), [.primary, .secondary, .quiet])
    }

    func testActiveCoachingPresentationAlwaysRetainsAuthoredStopAction() {
        var session = CoachingSession(learner: .white)
        session.receive(CoachingTestFixtures.startingPositionAdvice)

        XCTAssertTrue(session.presentation?.actions.contains { $0.action == .stop } == true)
    }

    func testOnlyDoneRoutesReturnedMoveToCommitCallback() {
        let move = Move(
            from: Square(file: .e, rank: 2),
            to: Square(file: .e, rank: 4)
        )

        XCTAssertEqual(CoachingActionRouting.committedMove(for: .done, returnedMove: move), move)
        XCTAssertNil(CoachingActionRouting.committedMove(for: .keepLooking, returnedMove: move))
        XCTAssertNil(CoachingActionRouting.committedMove(for: .stop, returnedMove: move))
        XCTAssertNil(CoachingActionRouting.committedMove(for: .done, returnedMove: nil))
    }

    private func coachingContext(
        prompt: CoachingPrompt,
        actions: [CoachingAction]
    ) -> CoachingPresentationContext {
        CoachingPresentationContext(
            prompt: prompt,
            feedback: nil,
            learner: .white,
            hintLevel: 0,
            missesAtCurrentLevel: 0,
            routine: [.safeCleared, .takeCleared, .wakeCurrent],
            actions: actions,
            boardTask: .none,
            focus: .empty
        )
    }
}
