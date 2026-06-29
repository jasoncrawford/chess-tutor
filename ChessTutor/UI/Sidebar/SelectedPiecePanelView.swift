import SwiftUI

struct SelectedPiecePanelLayout: Equatable {
    static let current = SelectedPiecePanelLayout(
        iconSlotHeight: 112,
        selectedPieceSpacing: 8,
        titleLineHeight: 28,
        titleSummarySpacing: 4,
        twoLineSummaryHeight: 42
    )

    let iconSlotHeight: CGFloat
    let selectedPieceSpacing: CGFloat
    let titleLineHeight: CGFloat
    let titleSummarySpacing: CGFloat
    let twoLineSummaryHeight: CGFloat

    var textSlotHeight: CGFloat {
        titleLineHeight + titleSummarySpacing + twoLineSummaryHeight
    }

    var requiredContentHeight: CGFloat {
        iconSlotHeight + selectedPieceSpacing + textSlotHeight
    }

    func remainingSlack(inPanelLength panelLength: CGFloat) -> CGFloat {
        panelLength - SidebarPanelMetrics.contentPadding * 2 - requiredContentHeight
    }
}

struct SelectedPiecePanelView: View {
    let selectedPieceInfo: SelectedPieceInfo?
    private let layout = SelectedPiecePanelLayout.current

    var body: some View {
        VStack(alignment: .leading, spacing: layout.selectedPieceSpacing) {
            if let selectedPieceInfo {
                selectedPieceIcon(selectedPieceInfo.piece)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: layout.iconSlotHeight)

                VStack(alignment: .leading, spacing: layout.titleSummarySpacing) {
                    Text(selectedPieceInfo.title)
                        .font(AppTheme.pieceTitleFont)
                        .foregroundStyle(AppTheme.ink)
                        .frame(height: layout.titleLineHeight, alignment: .leading)

                    Text(selectedPieceInfo.movementSummary)
                        .font(AppTheme.pieceBodyFont)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: layout.textSlotHeight, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)

                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.42))
                    .frame(maxWidth: .infinity)

                Text("Choose a piece")
                    .font(AppTheme.emptyPanelFont)
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectedPieceIcon(_ piece: Piece) -> some View {
        PieceIconView(piece: piece)
            .frame(width: 100, height: 100)
            .padding(9)
            .background {
                Circle()
                    .fill(AppTheme.selectedPiecePlinth)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.panelStroke, lineWidth: 1)
                    }
            }
    }
}
