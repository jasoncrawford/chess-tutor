#if DEBUG
import SwiftUI

enum CoachingPanelAccessibilityFixtureConfiguration {
    case tall
    case clockwiseQuarterTurn
    case counterclockwiseQuarterTurn

    var composition: CoachingPanelComposition {
        self == .tall ? .tall : .wide
    }

    var tableRotationDegrees: Double {
        switch self {
        case .tall:
            return 0
        case .clockwiseQuarterTurn:
            return 90
        case .counterclockwiseQuarterTurn:
            return -90
        }
    }

    var readableRotationDegrees: Double {
        -tableRotationDegrees
    }
}

struct CoachingPanelAccessibilityFixture: View {
    let configuration: CoachingPanelAccessibilityFixtureConfiguration

    @State private var session = GameSession()

    static var launchConfiguration: CoachingPanelAccessibilityFixtureConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-coaching-panel"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        switch arguments[flagIndex + 1] {
        case "tall":
            return .tall
        case "clockwise-quarter-turn":
            return .clockwiseQuarterTurn
        case "counterclockwise-quarter-turn":
            return .counterclockwiseQuarterTurn
        default:
            return nil
        }
    }

    var body: some View {
        ZStack {
            AppTheme.table.ignoresSafeArea()

            SidebarPanelView(panelSize: layout.tabletopRegionSize) {
                CoachingPanelView(
                    session: session,
                    presentation: presentation,
                    layout: layout,
                    readableRotationDegrees: configuration.readableRotationDegrees,
                    onCommittedMove: { _ in }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coaching-panel-frame")
            .rotationEffect(.degrees(configuration.tableRotationDegrees))
            .frame(
                width: layout.physicalRegionSize.width,
                height: layout.physicalRegionSize.height
            )
        }
    }

    private var layout: CoachingPanelLayout {
        switch configuration.composition {
        case .tall:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 260, height: 446),
                physicalRegionSize: CGSize(width: 260, height: 446),
                physicalAxis: .vertical
            )
        case .wide:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 246.67, height: 503.34),
                physicalRegionSize: CGSize(width: 503.34, height: 246.67),
                physicalAxis: .horizontal
            )
        }
    }

    private var presentation: CoachingPresentation {
        CoachingPresentation(
            headline: "Yes—that pawn is attacking your queen. How could you help your queen?",
            instruction: "Try moving your queen, protecting it, or taking the attacker.",
            hint: nil,
            routine: [.safeCurrent, .takePending, .wakePending],
            actions: [
                CoachingActionPresentation(
                    action: .done,
                    title: "Done",
                    accessibilityLabel: "Done with this move",
                    prominence: .primary
                ),
                CoachingActionPresentation(
                    action: .keepLooking,
                    title: "Keep looking",
                    accessibilityLabel: "Keep looking for another move",
                    prominence: .secondary
                ),
                CoachingActionPresentation(
                    action: .stop,
                    title: "Stop",
                    accessibilityLabel: "Stop coaching",
                    prominence: .quiet
                ),
            ],
            boardTask: .none,
            focus: .empty
        )
    }
}
#endif
