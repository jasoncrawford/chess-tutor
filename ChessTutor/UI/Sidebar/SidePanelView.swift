import SwiftUI

struct SidePanelView: View {
    @Bindable var session: GameSession
    let viewingAngle: BoardViewingAngle
    let readableRotationDegrees: Double
    let captureNamespace: Namespace.ID
    let onAbout: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(viewingAngle.sidebarSegmentsInTabletopOrder, id: \.self) { segment in
                sidebarSegment(segment)
                    .rotationEffect(.degrees(readableRotationDegrees))
            }
        }
        .frame(width: 260, height: 760, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewingAngle.sidebarSegmentsInTabletopOrder)
    }

    @ViewBuilder
    private func sidebarSegment(_ segment: SidebarSegment) -> some View {
        switch segment {
        case .messageAndDone:
            SidebarPanelView {
                TurnStatusPanelView(session: session, onAbout: onAbout)
            }
        case .selectedPiece:
            SidebarPanelView {
                SelectedPiecePanelView(selectedPieceInfo: session.selectedPieceInfo)
            }
        case .capturedPieces:
            CapturedPiecesPanelView(
                capturedPieces: session.capturedPieces,
                captureNamespace: captureNamespace
            )
        }
    }
}
