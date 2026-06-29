import SwiftUI

struct SidePanelView: View {
    @Bindable var session: GameSession
    let viewingAngle: BoardViewingAngle
    let readableRotationDegrees: Double
    let captureNamespace: Namespace.ID
    let sideLength: CGFloat
    let onAbout: () -> Void

    var body: some View {
        let layout = SidebarColumnLayout.make(for: sideLength)

        VStack(spacing: SidebarColumnLayout.segmentSpacing) {
            ForEach(viewingAngle.sidebarSegmentsInTabletopOrder, id: \.self) { segment in
                sidebarSegment(segment, panelLength: layout.segmentLength)
                    .rotationEffect(.degrees(readableRotationDegrees))
            }
        }
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: layout.columnHeight, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewingAngle.sidebarSegmentsInTabletopOrder)
    }

    @ViewBuilder
    private func sidebarSegment(_ segment: SidebarSegment, panelLength: CGFloat) -> some View {
        switch segment {
        case .messageAndDone:
            SidebarPanelView(panelLength: panelLength) {
                TurnStatusPanelView(
                    session: session,
                    onAbout: onAbout
                )
            }
        case .selectedPiece:
            SidebarPanelView(panelLength: panelLength) {
                SelectedPiecePanelView(selectedPieceInfo: session.selectedPieceInfo)
            }
        case .capturedPieces:
            CapturedPiecesPanelView(
                capturedPieces: session.capturedPieces,
                captureNamespace: captureNamespace,
                panelLength: panelLength
            )
        }
    }
}

struct SidebarColumnLayout: Equatable {
    static let segmentSpacing: CGFloat = 12
    static let segmentCount: CGFloat = 3

    let columnHeight: CGFloat
    let segmentLength: CGFloat

    static func make(for sideLength: CGFloat) -> SidebarColumnLayout {
        let totalSpacing = segmentSpacing * (segmentCount - 1)
        let segmentLength = max(1, (sideLength - totalSpacing) / segmentCount)

        return SidebarColumnLayout(columnHeight: sideLength, segmentLength: segmentLength)
    }
}
