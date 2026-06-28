import SwiftUI

struct SelectedPiecePanelView: View {
    let selectedPieceInfo: SelectedPieceInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selectedPieceInfo {
                selectedPieceIcon(selectedPieceInfo.piece)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 128)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPieceInfo.title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(selectedPieceInfo.movementSummary)
                        .font(.callout)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)

                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AppTheme.mutedInk.opacity(0.42))
                    .frame(maxWidth: .infinity)

                Text("Choose a piece")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
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
