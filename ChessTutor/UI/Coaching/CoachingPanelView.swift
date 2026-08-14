import SwiftUI

enum CoachingPanelAxis: Equatable {
    case vertical
    case horizontal
}

enum CoachingPanelAccessibleElement: Equatable {
    case headline
    case instruction
    case routine
    case actions
}

enum CoachingPanelAccessibilityOrder {
    static let elements: [CoachingPanelAccessibleElement] = [
        .headline, .instruction, .routine, .actions,
    ]

    static func sortPriority(for element: CoachingPanelAccessibleElement) -> Double {
        Double(elements.count - (elements.firstIndex(of: element) ?? elements.count))
    }
}

enum CoachingSidebarRegion: Equatable {
    case coaching
    case capturedPieces
}

struct CoachingPanelLayout: Equatable {
    let tabletopRegionSize: CGSize
    let physicalRegionSize: CGSize
    let physicalAxis: CoachingPanelAxis

    static func make(sidebar: SidebarColumnLayout) -> CoachingPanelLayout {
        CoachingPanelLayout(
            tabletopRegionSize: sidebar.coachingRegionSize,
            physicalRegionSize: sidebar.coachingRegionPhysicalSize,
            physicalAxis: sidebar.coachingPhysicalAxis
        )
    }

    static func sidebarRegions(
        inTabletopOrder segments: [SidebarSegment]
    ) -> [CoachingSidebarRegion] {
        if segments.first == .capturedPieces {
            return [.capturedPieces, .coaching]
        }
        return [.coaching, .capturedPieces]
    }
}

extension SidebarColumnLayout {
    var coachingRegionSize: CGSize {
        let message = size(for: .messageAndDone)
        let selected = size(for: .selectedPiece)
        return CGSize(
            width: max(message.width, selected.width),
            height: message.height + Self.segmentSpacing + selected.height
        )
    }

    var coachingPhysicalAxis: CoachingPanelAxis {
        presentation == .verticalColumn ? .vertical : .horizontal
    }

    var coachingRegionPhysicalSize: CGSize {
        guard presentation == .horizontalSegments else {
            return coachingRegionSize
        }
        return CGSize(width: coachingRegionSize.height, height: coachingRegionSize.width)
    }
}

enum CoachingActionRouting {
    static func committedMove(
        for action: CoachingAction,
        returnedMove: Move?
    ) -> Move? {
        action == .done ? returnedMove : nil
    }
}

struct CoachingPanelView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Bindable var session: GameSession
    let presentation: CoachingPresentation
    let layout: CoachingPanelLayout
    let readableRotationDegrees: Double
    let onCommittedMove: (Move) -> Void

    var body: some View {
        VStack(spacing: 12) {
            readableConversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .overlay(AppTheme.panelStroke)
                .accessibilityHidden(true)

            readableActions
                .frame(maxWidth: .infinity, alignment: .bottom)
        }
        .frame(
            maxWidth: layout.tabletopRegionSize.width,
            maxHeight: layout.tabletopRegionSize.height,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var readableConversation: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical) {
                    conversation
                }
                .scrollIndicators(.visible)
            } else {
                conversation
            }
        }
        .rotationEffect(.degrees(readableRotationDegrees))
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.headline)
                .font(AppTheme.panelTitleFont)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(
                    CoachingPanelAccessibilityOrder.sortPriority(for: .headline)
                )

            if let instruction = presentation.instruction {
                Text(instruction)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(
                        CoachingPanelAccessibilityOrder.sortPriority(for: .instruction)
                    )
            }

            if !presentation.routine.isEmpty {
                routineView
                    .padding(.top, 2)
                    .accessibilitySortPriority(
                        CoachingPanelAccessibilityOrder.sortPriority(for: .routine)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var routineView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                routineTokens
            }

            VStack(alignment: .leading, spacing: 5) {
                routineTokens
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var routineTokens: some View {
        ForEach(Array(presentation.routine.enumerated()), id: \.offset) { _, state in
            CoachingRoutineToken(state: state)
        }
    }

    private var readableActions: some View {
        VStack(spacing: 7) {
            ForEach(presentation.actions, id: \.action) { action in
                Button {
                    choose(action.action)
                } label: {
                    Text(action.title)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(CoachingActionButtonStyle(prominence: action.prominence))
                .accessibilityLabel(action.accessibilityLabel)
            }
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .rotationEffect(.degrees(readableRotationDegrees))
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(
            CoachingPanelAccessibilityOrder.sortPriority(for: .actions)
        )
    }

    private func choose(_ action: CoachingAction) {
        if action == .done {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                let returnedMove = session.chooseCoachingAction(action)
                if let move = CoachingActionRouting.committedMove(
                    for: action,
                    returnedMove: returnedMove
                ) {
                    onCommittedMove(move)
                }
            }
            return
        }

        _ = session.chooseCoachingAction(action)
    }
}

private struct CoachingRoutineToken: View {
    let state: CoachingRoutineState

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: weight, design: .rounded))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundStyle)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(statusLabel)")
    }

    private var title: String {
        switch state {
        case .safeCurrent, .safeCleared:
            return "Safe"
        case .takePending, .takeCurrent, .takeCleared:
            return "Take"
        case .wakePending, .wakeCurrent, .wakeCleared:
            return "Wake"
        }
    }

    private var systemImage: String {
        switch state {
        case .safeCleared, .takeCleared, .wakeCleared:
            return "checkmark.circle.fill"
        case .safeCurrent, .takeCurrent, .wakeCurrent:
            return "circle.fill"
        case .takePending, .wakePending:
            return "circle"
        }
    }

    private var statusLabel: String {
        switch state {
        case .safeCleared, .takeCleared, .wakeCleared:
            return "cleared"
        case .safeCurrent, .takeCurrent, .wakeCurrent:
            return "current step"
        case .takePending, .wakePending:
            return "coming next"
        }
    }

    private var weight: Font.Weight {
        switch state {
        case .safeCurrent, .takeCurrent, .wakeCurrent:
            return .bold
        case .safeCleared, .takeCleared, .wakeCleared, .takePending, .wakePending:
            return .semibold
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .safeCurrent, .takeCurrent, .wakeCurrent:
            return AppTheme.ink
        case .safeCleared, .takeCleared, .wakeCleared:
            return AppTheme.darkSquare
        case .takePending, .wakePending:
            return AppTheme.mutedInk
        }
    }

    private var backgroundStyle: Color {
        switch state {
        case .safeCurrent, .takeCurrent, .wakeCurrent:
            return AppTheme.selectedSquare.opacity(0.34)
        case .safeCleared, .takeCleared, .wakeCleared:
            return AppTheme.darkSquare.opacity(0.12)
        case .takePending, .wakePending:
            return AppTheme.panelInset
        }
    }
}

private struct CoachingActionButtonStyle: ButtonStyle {
    let prominence: CoachingActionProminence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundStyle)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(backgroundStyle(configuration: configuration))
                    .overlay(alignment: .top) {
                        if prominence == .primary {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppTheme.panelTopLight.opacity(0.30))
                                .frame(height: 16)
                        }
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .shadow(
                color: prominence == .primary ? AppTheme.panelShadow : .clear,
                radius: 6,
                y: 3
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }

    private var foregroundStyle: Color {
        prominence == .primary ? AppTheme.whitePiece : AppTheme.mutedInk
    }

    private func backgroundStyle(configuration: Configuration) -> Color {
        switch prominence {
        case .primary:
            return AppTheme.boardFrame.opacity(configuration.isPressed ? 0.86 : 1)
        case .secondary:
            return AppTheme.coverageControlFill.opacity(configuration.isPressed ? 1 : 0.72)
        case .quiet:
            return AppTheme.panelInset.opacity(configuration.isPressed ? 1 : 0.42)
        }
    }
}
