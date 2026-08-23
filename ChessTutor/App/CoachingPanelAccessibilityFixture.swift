#if DEBUG
import SwiftUI

enum CoachingPanelAccessibilityFixtureConfiguration {
    case tall
    case tallNoObservation
    case clockwiseQuarterTurn
    case clockwiseQuarterTurnNoObservation
    case counterclockwiseQuarterTurn

    var composition: CoachingPanelComposition {
        switch self {
        case .tall, .tallNoObservation:
            return .tall
        case .clockwiseQuarterTurn, .clockwiseQuarterTurnNoObservation, .counterclockwiseQuarterTurn:
            return .wide
        }
    }

    var tableRotationDegrees: Double {
        switch self {
        case .tall, .tallNoObservation:
            return 0
        case .clockwiseQuarterTurn, .clockwiseQuarterTurnNoObservation:
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
        case "tall-no-observation":
            return .tallNoObservation
        case "clockwise-quarter-turn":
            return .clockwiseQuarterTurn
        case "clockwise-quarter-turn-no-observation":
            return .clockwiseQuarterTurnNoObservation
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
        let omitsObservation = configuration == .tallNoObservation
            || configuration == .clockwiseQuarterTurnNoObservation
        return CoachingPresentation(
            primaryMessage: "What could Black do next?",
            instruction: "Tap a black piece that could check your king or win one of your pieces.",
            observation: omitsObservation ? nil : "That knight does not cause trouble here.",
            hint: nil,
            routine: [.safeCurrent, .takePending, .wakePending],
            actions: [
                CoachingActionPresentation(
                    action: .done,
                    title: "Play this move",
                    accessibilityLabel: "Play this move",
                    prominence: .primary
                ),
                CoachingActionPresentation(
                    action: .keepLooking,
                    title: "Try another move",
                    accessibilityLabel: "Try another move",
                    prominence: .secondary
                ),
                CoachingActionPresentation(
                    action: .stop,
                    title: "Close help",
                    accessibilityLabel: "Close coaching help",
                    prominence: .quiet
                ),
            ],
            boardTask: .none,
            focus: .empty
        )
    }
}
#endif
