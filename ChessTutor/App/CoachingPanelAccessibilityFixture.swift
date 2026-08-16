#if DEBUG
import SwiftUI

struct CoachingPanelAccessibilityFixture: View {
    let composition: CoachingPanelComposition

    @State private var session = GameSession()

    static var launchComposition: CoachingPanelComposition? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-ui-test-coaching-panel"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        switch arguments[flagIndex + 1] {
        case "tall":
            return .tall
        case "wide":
            return .wide
        default:
            return nil
        }
    }

    var body: some View {
        CoachingPanelView(
            session: session,
            presentation: presentation,
            layout: layout,
            readableRotationDegrees: 0,
            onCommittedMove: { _ in }
        )
        .frame(width: layout.tabletopRegionSize.width, height: layout.tabletopRegionSize.height)
        .background(AppTheme.table)
    }

    private var layout: CoachingPanelLayout {
        switch composition {
        case .tall:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 360, height: 720),
                physicalRegionSize: CGSize(width: 360, height: 720),
                physicalAxis: .vertical
            )
        case .wide:
            CoachingPanelLayout(
                tabletopRegionSize: CGSize(width: 720, height: 360),
                physicalRegionSize: CGSize(width: 720, height: 360),
                physicalAxis: .horizontal
            )
        }
    }

    private var presentation: CoachingPresentation {
        CoachingPresentation(
            headline: "What do you notice?",
            instruction: "Find a safe square.",
            hint: nil,
            routine: [.safeCurrent, .takePending, .wakePending],
            actions: [CoachingActionPresentation(
                action: .hint,
                title: "I need help",
                accessibilityLabel: "I need help",
                prominence: .secondary
            )],
            boardTask: .none,
            focus: .empty
        )
    }
}
#endif
