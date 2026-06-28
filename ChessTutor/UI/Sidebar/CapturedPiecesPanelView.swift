import SwiftUI

struct CapturedPiecesPanelView: View {
    let capturedPieces: [CapturedPiece]
    let captureNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 10) {
            captureBox(for: .black)
            captureBox(for: .white)
        }
        .frame(width: 240, height: 240)
    }

    private func captureBox(for color: PieceColor) -> some View {
        let pieces = capturedPieces.filter { $0.piece.color == color }

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.captureBoxWood.opacity(0.94),
                            AppTheme.captureBoxWood,
                            AppTheme.captureBoxWood.opacity(0.82),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: AppTheme.captureBoxShadow, radius: 14, y: 8)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.captureBoxFelt)
                .padding(9)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1)
                        .padding(9)
                }
                .shadow(color: .black.opacity(0.20), radius: 5, y: -1)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6),
                alignment: .center,
                spacing: 4
            ) {
                ForEach(pieces) { capturedPiece in
                    PieceIconView(piece: capturedPiece.piece)
                        .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
                        .frame(width: 30, height: 30)
                        .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
                        .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pieces)
    }
}
