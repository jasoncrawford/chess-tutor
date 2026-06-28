import SwiftUI

struct SidePanelView: View {
    @Bindable var session: GameSession
    let viewingAngle: BoardViewingAngle
    let readableRotationDegrees: Double
    let captureNamespace: Namespace.ID
    #if DEBUG
    @Binding var isCaptureTestModeEnabled: Bool
    #endif
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
                #if DEBUG
                TurnStatusPanelView(
                    session: session,
                    isCaptureTestModeEnabled: $isCaptureTestModeEnabled,
                    onAbout: onAbout
                )
                #else
                TurnStatusPanelView(
                    session: session,
                    onAbout: onAbout
                )
                #endif
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
