import SwiftUI

enum CoachingPanelAxis: Equatable {
    case vertical
    case horizontal
}

enum CoachingPanelComposition: Equatable {
    case tall
    case wide

    var routineTabletopAxis: CoachingPanelAxis {
        self == .tall ? .horizontal : .vertical
    }

    var actionTabletopAxis: CoachingPanelAxis {
        self == .tall ? .vertical : .horizontal
    }
}

private enum CoachingPanelAccessibilitySection: String {
    case conversation
    case routine
    case actions

    var identifier: String {
        "coaching-panel-\(rawValue)"
    }

    var sortPriority: Double {
        switch self {
        case .conversation:
            3
        case .routine:
            2
        case .actions:
            1
        }
    }
}

private enum CoachingConversationAccessibilityElement {
    case headline
    case instruction

    var sortPriority: Double {
        switch self {
        case .headline:
            2
        case .instruction:
            1
        }
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

extension CoachingPanelLayout {
    var composition: CoachingPanelComposition {
        physicalAxis == .vertical ? .tall : .wide
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
        panelContent
        .frame(
            maxWidth: layout.tabletopRegionSize.width,
            maxHeight: layout.tabletopRegionSize.height,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityRepresentation {
            accessibilityPanelContent
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch layout.composition {
        case .tall:
            VStack(spacing: 10) {
                if !presentation.routine.isEmpty {
                    routineHeader(axis: .horizontal)
                }

                scrollableConversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                panelDivider
                readableActions(axis: .vertical)
            }
        case .wide:
            HStack(spacing: 10) {
                if !presentation.routine.isEmpty {
                    routineHeader(axis: .vertical)
                    panelDivider
                }

                VStack(spacing: 10) {
                    scrollableConversation
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    panelDivider
                    readableActions(axis: .horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            accessibleConversation

            if !presentation.routine.isEmpty {
                routineHeader(axis: .horizontal)
            }

            readableActions(axis: .vertical)
        }
    }

    private var panelDivider: some View {
        Divider()
            .overlay(AppTheme.panelStroke)
            .accessibilityHidden(true)
    }

    private var scrollableConversation: some View {
        ScrollView(.vertical) {
            conversation
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(dynamicTypeSize.isAccessibilitySize ? .visible : .automatic)
        .rotationEffect(.degrees(readableRotationDegrees))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.conversation.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.conversation.sortPriority)
    }

    private var accessibleConversation: some View {
        conversation
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CoachingPanelAccessibilitySection.conversation.identifier)
            .accessibilitySortPriority(CoachingPanelAccessibilitySection.conversation.sortPriority)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.headline)
                .font(AppTheme.coachingTitleFont)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(
                    CoachingConversationAccessibilityElement.headline.sortPriority
                )

            if let instruction = presentation.instruction {
                Text(instruction)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(
                        CoachingConversationAccessibilityElement.instruction.sortPriority
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func routineHeader(axis: CoachingPanelAxis) -> some View {
        Group {
            switch axis {
            case .horizontal:
                HStack(spacing: 4) {
                    routineTokens
                }
            case .vertical:
                VStack(spacing: 4) {
                    routineTokens
                }
            }
        }
        .rotationEffect(.degrees(readableRotationDegrees))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.routine.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.routine.sortPriority)
    }

    @ViewBuilder
    private var routineTokens: some View {
        ForEach(Array(presentation.routine.enumerated()), id: \.offset) { _, state in
            CoachingRoutineToken(state: state)
        }
    }

    @ViewBuilder
    private func readableActions(axis: CoachingPanelAxis) -> some View {
        Group {
            switch axis {
            case .vertical:
                VStack(spacing: 7) {
                    actionButtons
                }
            case .horizontal:
                HStack(spacing: 7) {
                    actionButtons
                }
            }
        }
        .font(.system(size: 17, weight: .semibold, design: .rounded))
        .rotationEffect(.degrees(readableRotationDegrees))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.actions.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.actions.sortPriority)
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(presentation.actions, id: \.action) { action in
            Button {
                choose(action.action)
            } label: {
                Text(action.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(CoachingActionButtonStyle(prominence: action.prominence))
            .accessibilityLabel(action.accessibilityLabel)
        }
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
            .font(.system(size: 13, weight: weight, design: .rounded))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 6)
            .frame(minHeight: 28)
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
