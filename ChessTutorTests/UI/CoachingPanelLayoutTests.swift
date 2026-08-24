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
        XCTAssertEqual(
            layout.tabletopContentSize,
            CGSize(
                width: layout.tabletopRegionSize.width - 32,
                height: layout.tabletopRegionSize.height - 32
            )
        )
        XCTAssertEqual(
            layout.physicalContentSize,
            CGSize(
                width: layout.physicalRegionSize.width - 32,
                height: layout.physicalRegionSize.height - 32
            )
        )
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

    func testPhysicalAxisSelectsCompactPanelComposition() {
        let tall = CoachingPanelLayout.make(
            sidebar: .make(for: 760, presentation: .verticalColumn)
        )
        let wide = CoachingPanelLayout.make(
            sidebar: .make(for: 760, presentation: .horizontalSegments)
        )

        XCTAssertEqual(tall.composition, .tall)
        XCTAssertEqual(wide.composition, .wide)
        XCTAssertEqual(tall.composition.routineTabletopAxis, .horizontal)
        XCTAssertEqual(wide.composition.routineTabletopAxis, .vertical)
        XCTAssertEqual(tall.composition.actionTabletopAxis, .vertical)
        XCTAssertEqual(wide.composition.actionTabletopAxis, .horizontal)
    }

    func testPermanentUATFixtureSizesExerciseBothPhysicalCompositions() {
        let tall = CoachingPanelLayout(
            tabletopRegionSize: CGSize(width: 260, height: 446),
            physicalRegionSize: CGSize(width: 260, height: 446),
            physicalAxis: .vertical
        )
        let wide = CoachingPanelLayout(
            tabletopRegionSize: CGSize(width: 246.67, height: 503.34),
            physicalRegionSize: CGSize(width: 503.34, height: 246.67),
            physicalAxis: .horizontal
        )

        XCTAssertEqual(tall.composition, .tall)
        XCTAssertEqual(tall.tabletopContentSize, CGSize(width: 228, height: 414))
        XCTAssertEqual(wide.composition, .wide)
        XCTAssertEqual(wide.physicalContentSize, CGSize(width: 471.34, height: 214.67))
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

    func testFeedbackResponseKeepsCurrentAskAvailableToBothPanelCompositions() {
        let presentation = LocalCoachingExplanationSource().presentation(
            for: coachingContext(
                prompt: .wakeChoosePiece(purpose: .openingDevelopment(firstMove: true)),
                feedback: .blockedWakePiece(piece: .rook, blocker: .pawn),
                actions: [.hint, .stop]
            )
        )
        let compositions = [
            CoachingPanelLayout.make(sidebar: .make(for: 760, presentation: .verticalColumn)),
            CoachingPanelLayout.make(sidebar: .make(for: 760, presentation: .horizontalSegments)),
        ].map(\.composition)

        XCTAssertEqual(compositions, [.tall, .wide])
        XCTAssertEqual(
            presentation.observation,
            "Your pawn blocks that rook."
        )
        XCTAssertEqual(
            presentation.primaryMessage,
            "A center pawn or knight is a simple way to start."
        )
        XCTAssertEqual(
            presentation.instruction,
            "Tap a center pawn or knight."
        )
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
        let interaction = CoachingInteractionSnapshot(
            selectedSquare: nil,
            tentativeMove: nil,
            positionRevision: CoachingTestFixtures.startingPositionAdvice
                .evaluation.request.positionRevision
        )
        var session = CoachingSession(
            learner: .white,
            interaction: interaction,
            initialContext: .start
        )
        session.receive(
            CoachingTestFixtures.startingPositionAdvice,
            interaction: interaction
        )

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
        feedback: CoachingFeedback? = nil,
        actions: [CoachingAction]
    ) -> CoachingPresentationContext {
        CoachingPresentationContext(
            prompt: prompt,
            feedback: feedback,
            learner: .white,
            hint: nil,
            missesAtCurrentLevel: 0,
            routine: [.safeCleared, .takeCleared, .wakeCurrent],
            actions: actions,
            boardTask: .none,
            focus: .empty
        )
    }

}
