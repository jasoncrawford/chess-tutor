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
    case identity
    case conversation
    case routine
    case actions

    var identifier: String {
        "coaching-panel-\(rawValue)"
    }

    var sortPriority: Double {
        switch self {
        case .identity:
            4
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
    case primaryMessage
    case instruction
    case observation

    var sortPriority: Double {
        switch self {
        case .primaryMessage:
            3
        case .instruction:
            2
        case .observation:
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

    var tabletopContentSize: CGSize {
        contentSize(for: tabletopRegionSize)
    }

    var physicalContentSize: CGSize {
        contentSize(for: physicalRegionSize)
    }

    private func contentSize(for regionSize: CGSize) -> CGSize {
        let totalInset = SidebarPanelMetrics.contentPadding * 2
        return CGSize(
            width: max(1, regionSize.width - totalInset),
            height: max(1, regionSize.height - totalInset)
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var coachingBodySize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var coachingActionSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var actionMinimumHeight: CGFloat = 44

    @Bindable var session: GameSession
    let presentation: CoachingPresentation?
    let layout: CoachingPanelLayout
    let readableRotationDegrees: Double
    let onCommittedMove: (Move) -> Void

    var body: some View {
        panelContent
            .frame(
                width: layout.physicalContentSize.width,
                height: layout.physicalContentSize.height,
                alignment: .topLeading
            )
            .rotationEffect(.degrees(readableRotationDegrees))
            .frame(
                width: layout.tabletopContentSize.width,
                height: layout.tabletopContentSize.height
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
                panelHeader

                scrollableConversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                panelDivider
                readableActions(axis: .vertical)
            }
        case .wide:
            VStack(spacing: 10) {
                panelHeader
                panelDivider

                HStack(spacing: 10) {
                    scrollableConversation
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    panelDivider
                    readableActions(axis: .vertical)
                }
            }
        }
    }

    @ViewBuilder
    private var accessibilityPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            coachIdentity
            accessibleConversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if !routine.isEmpty {
                routineHeader(axis: .horizontal)
            }

            readableActions(axis: .vertical)
        }
        .frame(
            width: layout.tabletopContentSize.width,
            height: layout.tabletopContentSize.height,
            alignment: .topLeading
        )
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            coachIdentity
            if !routine.isEmpty {
                routineHeader(axis: .horizontal)
            }
            Spacer(minLength: 0)
        }
    }

    private var coachIdentity: some View {
        CoachingPanelIdentity(
            isThinking: presentation?.isThinking == true,
            showsTitle: routine.isEmpty
        )
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.identity.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.identity.sortPriority)
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
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.conversation.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.conversation.sortPriority)
    }

    private var accessibleConversation: some View {
        accessibilityConversationCopy
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(CoachingPanelAccessibilitySection.conversation.identifier)
            .accessibilitySortPriority(CoachingPanelAccessibilitySection.conversation.sortPriority)
    }

    private var accessibilityConversationCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation?.isThinking == true {
                // A stable semantic counterpart to the animated visual below.
                Color.clear
                    .frame(width: 64, height: 40)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Thinking")
                    .accessibilityIdentifier("coaching-thinking-indicator")
            } else if let presentation {
                Text(presentation.primaryMessage)
                    .font(bodyFont)
                    .lineLimit(1)
                    .accessibilitySortPriority(
                        CoachingConversationAccessibilityElement.primaryMessage.sortPriority
                    )

                if let instruction = presentation.instruction {
                    Text(instruction)
                        .font(bodyFont)
                        .lineLimit(1)
                        .accessibilitySortPriority(
                            CoachingConversationAccessibilityElement.instruction.sortPriority
                        )
                }

                if let observation = presentation.observation {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(observation)
                            .font(bodyFont)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(observation)
                    .accessibilityIdentifier("coaching-response-note")
                    .accessibilitySortPriority(
                        CoachingConversationAccessibilityElement.observation.sortPriority
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if presentation?.isThinking == true {
                CoachingThinkingIndicator(reduceMotion: reduceMotion)
            } else if let presentation {
                Text(presentation.primaryMessage)
                    .font(bodyFont)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(
                        CoachingConversationAccessibilityElement.primaryMessage.sortPriority
                    )

                if let instruction = presentation.instruction {
                    Text(instruction)
                        .font(bodyFont)
                        .foregroundStyle(AppTheme.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilitySortPriority(
                            CoachingConversationAccessibilityElement.instruction.sortPriority
                        )
                }

                if let observation = presentation.observation {
                    CoachingResponseNote(text: observation, font: bodyFont)
                        .accessibilitySortPriority(
                            CoachingConversationAccessibilityElement.observation.sortPriority
                        )
                }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.routine.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.routine.sortPriority)
    }

    @ViewBuilder
    private var routineTokens: some View {
        ForEach(Array(routine.enumerated()), id: \.offset) { _, state in
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
        .font(actionFont)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CoachingPanelAccessibilitySection.actions.identifier)
        .accessibilitySortPriority(CoachingPanelAccessibilitySection.actions.sortPriority)
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(actions, id: \.action) { action in
            Button {
                choose(action.action)
            } label: {
                Text(action.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        minWidth: 44,
                        maxWidth: .infinity,
                        minHeight: min(actionMinimumHeight, 48)
                    )
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

    private var bodyFont: Font {
        AppTheme.coachingBodyFont(size: min(coachingBodySize, 25))
    }

    private var actionFont: Font {
        AppTheme.coachingActionFont(size: min(coachingActionSize, 23))
    }

    private var routine: [CoachingRoutineState] {
        presentation?.routine ?? []
    }

    private var actions: [CoachingActionPresentation] {
        presentation?.actions ?? [
            CoachingActionPresentation(
                action: .stop,
                title: "Close help",
                accessibilityLabel: "Close coaching help",
                prominence: .quiet
            )
        ]
    }
}

private struct CoachingPanelIdentity: View {
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    let isThinking: Bool
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    AppTheme.captureBoxFelt
                    AppTheme.lightSquare
                }
                HStack(spacing: 2) {
                    AppTheme.lightSquare
                    AppTheme.captureBoxFelt
                }
            }
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            if showsTitle {
                Text("Coach")
                    .font(.system(size: min(titleSize, 32), weight: .semibold, design: .serif))
                    .foregroundStyle(AppTheme.ink)
            }
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
        .accessibilityValue(isThinking ? "Thinking" : "")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Motion belongs to this presentation-only view; request state still comes
/// exclusively from the session's `isThinking` flag.
struct CoachingThinkingIndicator: View {
    let reduceMotion: Bool
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    let lift = reduceMotion ? 0 : max(0, sin(elapsed * .pi * 2 / 1.4 - Double(index) * 0.8))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(AppTheme.captureBoxFelt.opacity(0.65 + lift * 0.35))
                        .frame(width: 14, height: 14)
                        .offset(y: -8 * lift)
                }
            }
            .frame(width: 64, height: 40, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thinking")
        .accessibilityIdentifier("coaching-thinking-indicator")
    }
}

private struct CoachingResponseNote: View {
    let text: String
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(AppTheme.ink.opacity(0.78))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(AppTheme.coachingResponseFill)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(AppTheme.coachingResponseRule)
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coaching-response-note")
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
