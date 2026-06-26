import SwiftUI

struct ChessBoardView: View {
    @Bindable var session: GameSession
    var onMoveAttempt: (MoveAttemptResult) -> Void = { _ in }
    @State private var dragState: DragState?

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )

            ZStack {
                board(side: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.boardFrame, lineWidth: 10)
                    }
                    .shadow(color: .black.opacity(0.20), radius: 18, y: 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let dragState {
                    PieceIconView(piece: dragState.piece)
                        .frame(width: side / 8 * 0.82, height: side / 8 * 0.82)
                        .position(dragState.location)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side, origin: origin))
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
        let isDraggingFromSquare = dragState?.from == square
        let isLegalDestination = session.legalDestinations.contains(square)
        let isCaptureDestination = isLegalDestination && piece?.color == session.state.sideToMove.opposite

        return ZStack {
            Rectangle()
                .fill(isLight ? AppTheme.lightSquare : AppTheme.darkSquare)
            if session.selectedSquare == square {
                Rectangle().fill(AppTheme.selectedSquare)
            }
            if isLegalDestination {
                if isCaptureDestination {
                    Circle()
                        .stroke(AppTheme.captureMove, lineWidth: 5)
                        .padding(10)
                } else {
                    Circle()
                        .fill(AppTheme.legalMove)
                        .frame(width: 22, height: 22)
                }
            }
            coordinateLabels(for: square)
            if let piece, !isDraggingFromSquare {
                PieceIconView(piece: piece)
                    .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(square)
        }
    }

    private func coordinateLabels(for square: Square) -> some View {
        let files = Array(session.boardOrientation == .white ? Square.File.allCases : Square.File.allCases.reversed())
        let ranks = session.boardOrientation == .white ? Array((1...8).reversed()) : Array(1...8)
        let showsRank = square.file == files.first
        let showsFile = square.rank == ranks.last

        return ZStack {
            if showsRank {
                Text("\(square.rank)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.boardFrame.opacity(0.60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(5)
            }
            if showsFile {
                Text(verbatim: "\(square.file)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.boardFrame.opacity(0.60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
            }
        }
    }

    private func dragGesture(side: CGFloat, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let from = square(at: value.startLocation, side: side, origin: origin),
                      let piece = session.state.board[from],
                      piece.color == session.state.sideToMove else {
                    return
                }

                if dragState == nil {
                    session.select(from)
                }
                dragState = DragState(from: from, piece: piece, location: value.location)
            }
            .onEnded { value in
                guard let dragState else {
                    if let tappedSquare = square(at: value.location, side: side, origin: origin) {
                        handleTap(tappedSquare)
                    }
                    return
                }

                defer {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        self.dragState = nil
                    }
                }

                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 8 else {
                    return
                }

                guard let destination = square(at: value.location, side: side, origin: origin) else {
                    session.select(dragState.from)
                    return
                }

                let result = session.moveSelectedPiece(to: destination)
                onMoveAttempt(result)
            }
    }

    private func square(at point: CGPoint, side: CGFloat, origin: CGPoint) -> Square? {
        let localX = point.x - origin.x
        let localY = point.y - origin.y
        guard localX >= 0, localY >= 0, localX < side, localY < side else {
            return nil
        }

        let column = min(7, max(0, Int(localX / (side / 8))))
        let row = min(7, max(0, Int(localY / (side / 8))))
        let visibleFiles = Array(session.boardOrientation == .white ? Square.File.allCases : Square.File.allCases.reversed())
        let visibleRanks = session.boardOrientation == .white ? Array((1...8).reversed()) : Array(1...8)

        return Square(file: visibleFiles[column], rank: visibleRanks[row])
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

private struct DragState {
    let from: Square
    let piece: Piece
    var location: CGPoint
}
