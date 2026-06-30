import SwiftUI

struct SelectedPiecePanelLayout: Equatable {
    static let current = SelectedPiecePanelLayout(
        iconSlotHeight: 96,
        selectedPieceSpacing: 6,
        squareBadgeHeight: 22,
        titleLineHeight: 24,
        titleSummarySpacing: 3,
        twoLineSummaryHeight: 35
    )

    let iconSlotHeight: CGFloat
    let selectedPieceSpacing: CGFloat
    let squareBadgeHeight: CGFloat
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

    func verticalInset(inPanelLength panelLength: CGFloat) -> CGFloat {
        max(0, remainingSlack(inPanelLength: panelLength) / 2)
    }
}

struct SelectedPiecePanelView: View {
    let selectedPieceInfo: SelectedPieceInfo?
    private let layout = SelectedPiecePanelLayout.current

    var body: some View {
        GeometryReader { proxy in
            if let selectedPieceInfo {
                let verticalInset = layout.verticalInset(
                    inPanelLength: proxy.size.height + SidebarPanelMetrics.contentPadding * 2
                )

                VStack(alignment: .leading, spacing: layout.selectedPieceSpacing) {
                    Spacer(minLength: verticalInset)
                        .frame(height: verticalInset)

                    selectedPieceIcon(selectedPieceInfo.piece)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: layout.iconSlotHeight)

                    VStack(alignment: .leading, spacing: layout.titleSummarySpacing) {
                        titleRow(for: selectedPieceInfo)

                        Text(selectedPieceInfo.movementSummary)
                            .font(AppTheme.pieceBodyFont)
                            .foregroundStyle(AppTheme.mutedInk)
                            .lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: layout.textSlotHeight, alignment: .topLeading)

                    Spacer(minLength: verticalInset)
                        .frame(height: verticalInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: layout.selectedPieceSpacing) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectedPieceIcon(_ piece: Piece) -> some View {
        PieceIconView(piece: piece)
            .frame(width: 78, height: 78)
            .padding(7)
            .background {
                Circle()
                    .fill(AppTheme.selectedPiecePlinth)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.panelStroke, lineWidth: 1)
                    }
            }
    }

    private func titleRow(for selectedPieceInfo: SelectedPieceInfo) -> some View {
        HStack(spacing: 8) {
            Text(selectedPieceInfo.squareID)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.lightSquare)
                .padding(.horizontal, 10)
                .frame(height: layout.squareBadgeHeight)
                .background {
                    Capsule()
                        .fill(AppTheme.boardFrame)
                }

            Text(selectedPieceInfo.title)
                .font(AppTheme.pieceTitleFont)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: layout.titleLineHeight, alignment: .leading)
    }
}
