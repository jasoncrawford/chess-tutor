import SwiftUI

struct CapturedPiecesPanelView: View {
    let capturedPieces: [CapturedPiece]
    let captureNamespace: Namespace.ID

    private let panelSize: CGFloat = 240

    var body: some View {
        VStack(spacing: 10) {
            captureBox(for: .black)
            captureBox(for: .white)
        }
        .frame(width: panelSize, height: panelSize)
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

            GeometryReader { proxy in
                let layout = CaptureTrayLayout.make(for: pieces.count, in: proxy.size)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(layout.pieceSize), spacing: CaptureTrayLayout.pieceSpacing),
                        count: layout.columns
                    ),
                    alignment: .leading,
                    spacing: CaptureTrayLayout.pieceSpacing
                ) {
                    ForEach(pieces) { capturedPiece in
                        PieceIconView(piece: capturedPiece.piece)
                            .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
                            .frame(width: layout.pieceSize, height: layout.pieceSize)
                            .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
                            .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pieces)
    }
}

struct CaptureTrayLayout: Equatable {
    static let pieceSpacing: CGFloat = 4
    private static let maximumPieceSize: CGFloat = 56
    private static let minimumPieceSize: CGFloat = 18

    let columns: Int
    let pieceSize: CGFloat

    static func make(for pieceCount: Int, in size: CGSize) -> CaptureTrayLayout {
        guard pieceCount > 0 else {
            return CaptureTrayLayout(columns: 1, pieceSize: maximumPieceSize)
        }

        let availableWidth = max(1, size.width)
        let availableHeight = max(1, size.height)
        let rows = (1...3).first { rowCount in
            let columnCount = Int(ceil(Double(pieceCount) / Double(rowCount)))
            let widthBound = (availableWidth - CGFloat(columnCount - 1) * pieceSpacing) / CGFloat(columnCount)
            let heightBound = (availableHeight - CGFloat(rowCount - 1) * pieceSpacing) / CGFloat(rowCount)

            return min(widthBound, heightBound) >= minimumPieceSize
        } ?? 3
        let columns = max(1, Int(ceil(Double(pieceCount) / Double(rows))))
        let widthBound = (availableWidth - CGFloat(columns - 1) * pieceSpacing) / CGFloat(columns)
        let heightBound = (availableHeight - CGFloat(rows - 1) * pieceSpacing) / CGFloat(rows)
        let pieceSize = max(minimumPieceSize, min(maximumPieceSize, widthBound, heightBound))

        return CaptureTrayLayout(columns: columns, pieceSize: pieceSize)
    }
}
