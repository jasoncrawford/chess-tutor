import SwiftUI

struct ChessBoardView: View {
    @Bindable var session: GameSession
    var onMoveAttempt: (MoveAttemptResult) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            board(side: side)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func board(side: CGFloat) -> some View {
        let files = session.boardOrientation == .white ? Square.File.allCases : Square.File.allCases.reversed()
        let ranks = session.boardOrientation == .white ? Array((1...8).reversed()) : Array(1...8)

        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(ranks, id: \.self) { rank in
                GridRow {
                    ForEach(Array(files), id: \.self) { file in
                        let square = Square(file: file, rank: rank)
                        squareView(square)
                            .frame(width: side / 8, height: side / 8)
                    }
                }
            }
        }
    }

    private func squareView(_ square: Square) -> some View {
        let isLight = (square.file.rawValue + square.rank).isMultiple(of: 2)
        let piece = session.state.board[square]

        return ZStack {
            Rectangle()
                .fill(isLight ? AppTheme.lightSquare : AppTheme.darkSquare)
            if session.selectedSquare == square {
                Rectangle().fill(AppTheme.selectedSquare)
            }
            if session.legalDestinations.contains(square) {
                Circle()
                    .fill(AppTheme.legalMove)
                    .frame(width: 22, height: 22)
            }
            if let piece {
                Text(PieceGlyph.text(for: piece))
                    .font(.system(size: 44))
                    .minimumScaleFactor(0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(square)
        }
    }

    private func handleTap(_ square: Square) {
        if session.selectedSquare == nil {
            session.select(square)
        } else {
            let result = session.moveSelectedPiece(to: square)
            onMoveAttempt(result)

            if case .illegal = result,
               session.state.board[square]?.color == session.state.sideToMove {
                session.select(square)
            }
        }
    }
}
