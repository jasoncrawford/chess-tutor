import SwiftUI

struct SidePanelView: View {
    @Bindable var session: GameSession
    let viewingAngle: BoardViewingAngle
    let readableRotationDegrees: Double
    let captureNamespace: Namespace.ID
    let sideLength: CGFloat
    let onAbout: () -> Void
    #if DEBUG
    let fakeRemoteLab: FakeRemoteGameLab?
    #endif
    @State private var isConfirmingNewGame = false

    var body: some View {
        let layout = SidebarColumnLayout.make(
            for: sideLength,
            presentation: viewingAngle.presentsSidebarSegmentsHorizontally ? .horizontalSegments : .verticalColumn
        )
        let secondaryActions = GameControlsPresentation(result: session.state.result).secondaryActions

        VStack(spacing: 0) {
            if layout.showsColumnUtilityStrip,
               viewingAngle.sidebarColumnUtilityPlacement == .beforeSegments {
                utilityStrip(secondaryActions, layout: layout)
                Spacer(minLength: SidebarColumnLayout.utilityStripSpacing)
            }

            segmentStack(layout: layout, secondaryActions: secondaryActions)

            if layout.showsColumnUtilityStrip,
               viewingAngle.sidebarColumnUtilityPlacement == .afterSegments {
                Spacer(minLength: SidebarColumnLayout.utilityStripSpacing)
                utilityStrip(secondaryActions, layout: layout)
            }
        }
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: layout.columnHeight, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewingAngle.sidebarSegmentsInTabletopOrder)
        .alert("Start a new game?", isPresented: $isConfirmingNewGame) {
            Button("Keep Playing", role: .cancel) {}
            Button("New Game", role: .destructive) {
                session.newGame()
            }
        } message: {
            Text("This will abandon the current game.")
        }
    }

    private func segmentStack(
        layout: SidebarColumnLayout,
        secondaryActions: [GameControlsPresentation.SecondaryAction]
    ) -> some View {
        VStack(spacing: SidebarColumnLayout.segmentSpacing) {
            ForEach(viewingAngle.sidebarSegmentsInTabletopOrder, id: \.self) { segment in
                sidebarSegment(
                    segment,
                    layout: layout,
                    secondaryActions: secondaryActions
                )
                    .rotationEffect(.degrees(readableRotationDegrees))
            }
        }
    }

    private func utilityStrip(_ actions: [GameControlsPresentation.SecondaryAction], layout: SidebarColumnLayout) -> some View {
        SidePanelUtilityStrip(
            actions: actions,
            onNewGame: requestNewGame,
            onAbout: onAbout
        )
        .frame(height: layout.utilityStripHeight)
        .rotationEffect(.degrees(readableRotationDegrees))
    }

    private func requestNewGame() {
        if session.hasGameInProgress {
            isConfirmingNewGame = true
        } else {
            session.newGame()
        }
    }

    @ViewBuilder
    private func sidebarSegment(
        _ segment: SidebarSegment,
        layout: SidebarColumnLayout,
        secondaryActions: [GameControlsPresentation.SecondaryAction]
    ) -> some View {
        let panelSize = layout.size(for: segment)

        switch segment {
        case .messageAndDone:
            SidebarPanelView(panelSize: panelSize) {
                #if DEBUG
                TurnStatusPanelView(session: session, fakeRemoteLab: fakeRemoteLab)
                #else
                TurnStatusPanelView(session: session)
                #endif
            }
        case .selectedPiece:
            SidebarPanelView(panelSize: panelSize) {
                SelectedPiecePanelView(selectedPieceInfo: session.selectedPieceInfo)
            }
        case .capturedPieces:
            if layout.showsCapturedPanelUtilityFooter {
                CapturedPiecesPanelView(
                    capturedPieces: session.capturedPieces,
                    captureNamespace: captureNamespace,
                    panelSize: panelSize,
                    footerHeight: layout.capturedPanelUtilityFooterHeight
                ) {
                    SidePanelUtilityStrip(
                        actions: secondaryActions,
                        onNewGame: requestNewGame,
                        onAbout: onAbout
                    )
                }
            } else {
                CapturedPiecesPanelView(
                    capturedPieces: session.capturedPieces,
                    captureNamespace: captureNamespace,
                    panelSize: panelSize
                )
            }
        }
    }
}

private struct SidePanelUtilityStrip: View {
    let actions: [GameControlsPresentation.SecondaryAction]
    let onNewGame: () -> Void
    let onAbout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .newGame:
                    Button(action: onNewGame) {
                        Label("New Game...", systemImage: "arrow.counterclockwise")
                    }
                case .about:
                    Button(action: onAbout) {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
        }
        .buttonStyle(SidePanelUtilityButtonStyle())
        .labelStyle(.titleAndIcon)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(AppTheme.mutedInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private struct SidePanelUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(AppTheme.panelWarmth.opacity(configuration.isPressed ? 0.88 : 0.68))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AppTheme.panelStroke.opacity(0.92), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

enum SidebarColumnPresentation: Equatable {
    case verticalColumn
    case horizontalSegments
}

struct SidebarColumnLayout: Equatable {
    static let segmentSpacing: CGFloat = 10
    static let segmentCount: CGFloat = 3
    static let utilityStripHeight: CGFloat = 40
    static let utilityStripSpacing: CGFloat = 12
    static let capturedPanelUtilityFooterHeight: CGFloat = 36

    let columnHeight: CGFloat
    let presentation: SidebarColumnPresentation
    let segmentSizes: [SidebarSegment: CGSize]
    let utilityStripHeight: CGFloat
    let capturedPanelUtilityFooterHeight: CGFloat

    var showsColumnUtilityStrip: Bool {
        presentation == .verticalColumn
    }

    var showsCapturedPanelUtilityFooter: Bool {
        presentation == .horizontalSegments
    }

    var segmentLength: CGFloat {
        size(for: .selectedPiece).height
    }

    func size(for segment: SidebarSegment) -> CGSize {
        segmentSizes[segment] ?? CGSize(width: PlaySurfaceLayout.sidePanelWidth, height: 1)
    }

    static func make(
        for sideLength: CGFloat,
        presentation: SidebarColumnPresentation = .verticalColumn
    ) -> SidebarColumnLayout {
        let totalSpacing = segmentSpacing * (segmentCount - 1)

        switch presentation {
        case .verticalColumn:
            let segmentHeightBudget = sideLength - totalSpacing - utilityStripSpacing - utilityStripHeight
            let messageHeight = max(172, min(196, segmentHeightBudget * 0.28))
            let selectedHeight = max(238, min(240, segmentHeightBudget * 0.345))
            let capturedHeight = max(1, segmentHeightBudget - messageHeight - selectedHeight)
            let width = PlaySurfaceLayout.sidePanelWidth

            return SidebarColumnLayout(
                columnHeight: sideLength,
                presentation: presentation,
                segmentSizes: [
                    .messageAndDone: CGSize(width: width, height: messageHeight),
                    .selectedPiece: CGSize(width: width, height: selectedHeight),
                    .capturedPieces: CGSize(width: width, height: capturedHeight),
                ],
                utilityStripHeight: utilityStripHeight,
                capturedPanelUtilityFooterHeight: 0
            )
        case .horizontalSegments:
            let segmentLength = max(1, (sideLength - totalSpacing) / segmentCount)
            let panelSize = CGSize(width: segmentLength, height: segmentLength)

            return SidebarColumnLayout(
                columnHeight: sideLength,
                presentation: presentation,
                segmentSizes: [
                    .messageAndDone: panelSize,
                    .selectedPiece: panelSize,
                    .capturedPieces: panelSize,
                ],
                utilityStripHeight: 0,
                capturedPanelUtilityFooterHeight: capturedPanelUtilityFooterHeight
            )
        }
    }
}
