import SwiftUI
import UIKit
import XCTest
@testable import ChessTutor

final class CoachingPanelLayoutTests: XCTestCase {
    @MainActor
    func testThinkingTilesAreCenteredInTheOpenReplyArea() throws {
        for frame in try thinkingFrames() {
            let greenPixels = (0..<(228 * 310)).filter { pixel in
                let offset = pixel * 4
                let red = Double(frame[offset])
                let green = Double(frame[offset + 1])
                let blue = Double(frame[offset + 2])
                return green > red * 1.15 && green > blue * 1.05
            }
            let xs = greenPixels.map { $0 % 228 }
            let ys = greenPixels.map { $0 / 228 }
            let minX = try XCTUnwrap(xs.min())
            let maxX = try XCTUnwrap(xs.max())
            let minY = try XCTUnwrap(ys.min())
            let maxY = try XCTUnwrap(ys.max())
            XCTAssertEqual(Double(minX + maxX) / 2, 114, accuracy: 5)
            // Allow the small vertical lift of the bouncing tiles.
            XCTAssertEqual(Double(minY + maxY) / 2, 155, accuracy: 14)
        }
    }

    @MainActor
    func testThinkingPanelHonorsSystemMotionPreference() throws {
        let frames = try thinkingFrames()
        if UIAccessibility.isReduceMotionEnabled {
            XCTAssertEqual(frames[0], frames[1])
            XCTAssertEqual(frames[0], frames[2])
        } else {
            assertVisibleMotion(frames)
        }
    }

    @MainActor
    func testThinkingRendererVisiblyAnimatesWhenMotionIsAllowed() throws {
        assertVisibleMotion(try thinkingFrames(indicatorReduceMotion: false))
    }

    private func assertVisibleMotion(_ frames: [[UInt8]], file: StaticString = #filePath, line: UInt = #line) {
        let changedBytes = frames.dropFirst().map { frame in
            zip(frames[0], frame).filter { abs(Int($0) - Int($1)) > 16 }.count
        }
        XCTAssertGreaterThan(changedBytes.max() ?? 0, 100,
                             "Waiting should visibly move in the reply area, not just change an icon's opacity.",
                             file: file, line: line)
    }

    @MainActor
    func testThinkingRemainsVisibleAndStillWithReduceMotion() throws {
        let frames = try thinkingFrames(indicatorReduceMotion: true)
        XCTAssertGreaterThan(frames[0].filter { $0 < 200 }.count, 100,
                             "Reduced motion should still show a waiting indicator.")
        for frame in frames.dropFirst() {
            XCTAssertEqual(frame, frames[0])
        }
    }

    @MainActor
    private func thinkingFrames(indicatorReduceMotion: Bool? = nil) throws -> [[UInt8]] {
        let panel = CoachingPanelView(
            session: GameSession(),
            presentation: HostedCoachingPresentationProjector().presentation(for: .thinking, pulseID: 0),
            layout: CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 260, height: 446),
                physicalRegionSize: CGSize(width: 260, height: 446),
                physicalAxis: .vertical
            ),
            readableRotationDegrees: 0,
            onCommittedMove: { _ in }
        )
        .environment(\.colorScheme, .light)
        .background(Color.white)
        // Reduce Motion is a read-only system environment value. Exercise the
        // same renderer with its real input, without changing simulator settings.
        let content: AnyView
        if let indicatorReduceMotion {
            content = AnyView(VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 50)
                CoachingThinkingIndicator(reduceMotion: indicatorReduceMotion)
                Spacer()
            }.frame(width: 228, height: 414, alignment: .topLeading).background(Color.white))
        } else {
            content = AnyView(panel)
        }
        let host = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 228, height: 414))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return try [0.15, 0.23, 0.31].enumerated().map { index, delay in
            RunLoop.current.run(until: Date().addingTimeInterval(delay))
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Thinking reduced=\(String(describing: indicatorReduceMotion)) frame=\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Inspect the reply area, excluding the heading and action buttons.
            let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 0, y: 50, width: 228, height: 310)))
            // A cropped CGImage can share its original backing provider. Copy
            // just the visible crop into owned pixels before comparing frames.
            var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: crop.width, height: crop.height,
                    bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            return pixels
        }
    }

    @MainActor
    func testCoachingFeedbackRendersAtBodySizeAndStillScalesWithDynamicType() throws {
        let standard = try renderedTextLineHeights(dynamicTypeSize: .large)
        let accessible = try renderedTextLineHeights(dynamicTypeSize: .accessibility3)

        // Use identical copy in the feedback and instruction so their actual
        // rendered glyph heights reveal an accidental headline-sized response.
        XCTAssertEqual(standard.count, 3)
        XCTAssertEqual(accessible.count, 3)
        guard standard.count == 3, accessible.count == 3 else { return }
        XCTAssertGreaterThan(standard[0], standard[1], "Coach must read as a heading, not a faint caption.")
        XCTAssertGreaterThan(accessible[0], accessible[1])
        XCTAssertEqual(standard[1], standard[2], accuracy: 1)
        XCTAssertEqual(accessible[1], accessible[2], accuracy: 1)
        XCTAssertGreaterThan(accessible[1], standard[1])
    }

    @MainActor
    private func renderedTextLineHeights(dynamicTypeSize: DynamicTypeSize) throws -> [Double] {
        let presentation = CoachingPresentation(
            primaryMessage: "A safe pawn.",
            instruction: "A safe pawn.",
            hint: nil,
            routine: [],
            actions: [],
            boardTask: .none,
            focus: .empty
        )
        let panel = CoachingPanelView(
            session: GameSession(),
            presentation: presentation,
            layout: CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 260, height: 446),
                physicalRegionSize: CGSize(width: 260, height: 446),
                physicalAxis: .vertical
            ),
            readableRotationDegrees: 0,
            onCommittedMove: { _ in }
        )
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .environment(\.colorScheme, .light)
        .background(Color.white)
        // ImageRenderer omits UIKit-backed content such as this ScrollView.
        // Host the real panel in a window so the test measures the visible text.
        let host = UIHostingController(rootView: panel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 228, height: 414))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "Coaching typography \(dynamicTypeSize)"
        add(attachment)
        let image = try XCTUnwrap(renderedImage.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Inspect the heading and conversation, excluding the actions below.
        var lineHeights: [Double] = []
        var previousInkRow: Int?
        for y in 0..<min(height, 160) {
            let hasInk = (0..<width).contains { x in
                let offset = (y * width + x) * 4
                // Measure neutral text ink, not the green icon. Some bulb
                // pixels are dark enough to pass the brightness test alone.
                return bytes[offset] < 100 && bytes[offset + 1] < 100
                    && bytes[offset + 2] < 100
                    && abs(Int(bytes[offset]) - Int(bytes[offset + 1])) < 12
            }
            guard hasInk else { continue }
            if let previousInkRow, y - previousInkRow <= 2 {
                // Antialiasing can leave a single faint row within a glyph.
                // Include it in the glyph bounds, not as a separate text line.
                lineHeights[lineHeights.count - 1] += Double(y - previousInkRow)
            } else {
                lineHeights.append(1)
            }
            previousInkRow = y
        }
        return lineHeights
    }

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

    func testPermanentAccessibilityFixtureCoversBothCompactTurnsInEveryRotation() {
        XCTAssertEqual(
            CoachingPanelAccessibilityFixtureTurn.allCases,
            [.compactNoObservation, .compactWithObservation]
        )

        for turn in CoachingPanelAccessibilityFixtureTurn.allCases {
            let configurations: [CoachingPanelAccessibilityFixtureConfiguration] = [
                .tall(turn),
                .clockwiseQuarterTurn(turn),
                .counterclockwiseQuarterTurn(turn),
            ]
            XCTAssertEqual(configurations.map(\.composition), [.tall, .wide, .wide])
            XCTAssertEqual(configurations.map(\.tableRotationDegrees), [0, 90, -90])
            XCTAssertEqual(configurations.map(\.turn), [turn, turn, turn])
        }
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
