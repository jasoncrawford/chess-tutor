import SwiftUI

struct ChessBoardView: View {
    @Bindable var session: GameSession
    let captureNamespace: Namespace.ID
    var onMoveAttempt: (MoveAttemptResult) -> Void = { _ in }
    @State private var dragState: DragState?
    @State private var visualPieces: [VisualPiece] = []
    @State private var settlingPieceID: UUID?

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

                piecesOverlay(side: side, origin: origin)

                if let dragState {
                    PieceIconView(piece: dragState.piece)
                        .frame(width: side / 8 * 0.82, height: side / 8 * 0.82)
                        .position(dragState.location)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 8)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side, origin: origin))
            .onAppear {
                syncVisualPieces(animated: false)
            }
            .onChange(of: session.state.board) {
                syncVisualPieces(animated: true)
            }
            .onChange(of: session.boardOrientation) {
                syncVisualPieces(animated: false)
            }
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(square)
        }
    }

    private func piecesOverlay(side: CGFloat, origin: CGPoint) -> some View {
        ZStack {
            ForEach(visualPieces) { visualPiece in
                if dragState?.visualPieceID != visualPiece.id, settlingPieceID != visualPiece.id {
                    PieceIconView(piece: visualPiece.piece)
                        .matchedGeometryEffect(
                            id: session.pieceAnimationID(for: visualPiece.piece, at: visualPiece.square),
                            in: captureNamespace
                        )
                        .frame(width: side / 8 * 0.82, height: side / 8 * 0.82)
                        .position(center(of: visualPiece.square, side: side, origin: origin))
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: visualPiece.square)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
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
                let visualPieceID = dragState?.visualPieceID ?? visualPieces.first {
                    $0.square == from && $0.piece == piece
                }?.id
                dragState = DragState(from: from, piece: piece, visualPieceID: visualPieceID, location: value.location)
            }
            .onEnded { value in
                guard let dragState else {
                    if let tappedSquare = square(at: value.location, side: side, origin: origin) {
                        handleTap(tappedSquare)
                    }
                    return
                }

                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > 8 else {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        self.dragState = nil
                    }
                    return
                }

                guard let destination = square(at: value.location, side: side, origin: origin) else {
                    session.select(dragState.from)
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        self.dragState = nil
                    }
                    return
                }

                let result = session.moveSelectedPiece(to: destination)
                onMoveAttempt(result)
                switch result {
                case .moved, .needsPromotion:
                    settleDraggedPiece(dragState, to: destination, side: side, origin: origin)
                case .illegal:
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        self.dragState = nil
                    }
                }
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

    private func center(of square: Square, side: CGFloat, origin: CGPoint) -> CGPoint {
        let visibleFiles = Array(session.boardOrientation == .white ? Square.File.allCases : Square.File.allCases.reversed())
        let visibleRanks = session.boardOrientation == .white ? Array((1...8).reversed()) : Array(1...8)
        guard let column = visibleFiles.firstIndex(of: square.file),
              let row = visibleRanks.firstIndex(of: square.rank) else {
            return origin
        }

        let cell = side / 8
        return CGPoint(
            x: origin.x + (CGFloat(column) + 0.5) * cell,
            y: origin.y + (CGFloat(row) + 0.5) * cell
        )
    }

    private func syncVisualPieces(animated: Bool) {
        let update = {
            visualPieces = nextVisualPieces()
        }

        if animated {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                update()
            }
        } else {
            update()
        }
    }

    private func settleDraggedPiece(_ dragState: DragState, to destination: Square, side: CGFloat, origin: CGPoint) {
        settlingPieceID = dragState.visualPieceID
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            self.dragState?.location = center(of: destination, side: side, origin: origin)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            self.dragState = nil
            self.settlingPieceID = nil
        }
    }

    private func nextVisualPieces() -> [VisualPiece] {
        let boardPieces = session.state.board.pieces
        guard !visualPieces.isEmpty else {
            return boardPieces
                .map { VisualPiece(square: $0.key, piece: $0.value) }
                .sorted()
        }

        var stablePieces: [VisualPiece] = []
        var movablePieces: [VisualPiece] = []
        var newSquares: [(square: Square, piece: Piece)] = []

        for visualPiece in visualPieces {
            if boardPieces[visualPiece.square] == visualPiece.piece {
                stablePieces.append(visualPiece)
            } else {
                movablePieces.append(visualPiece)
            }
        }

        for (square, piece) in boardPieces where !stablePieces.contains(where: { $0.square == square }) {
            newSquares.append((square, piece))
        }

        for newSquare in newSquares.sorted(by: { $0.square.sortKey < $1.square.sortKey }) {
            if let index = movablePieces.bestMatchIndex(for: newSquare) {
                var movedPiece = movablePieces.remove(at: index)
                movedPiece.square = newSquare.square
                movedPiece.piece = newSquare.piece
                stablePieces.append(movedPiece)
            } else {
                stablePieces.append(VisualPiece(square: newSquare.square, piece: newSquare.piece))
            }
        }

        return stablePieces.sorted()
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
    let visualPieceID: UUID?
    var location: CGPoint
}

private struct VisualPiece: Identifiable, Equatable, Comparable {
    let id = UUID()
    var square: Square
    var piece: Piece

    static func < (lhs: VisualPiece, rhs: VisualPiece) -> Bool {
        lhs.square.sortKey < rhs.square.sortKey
    }
}

private extension Array where Element == VisualPiece {
    func bestMatchIndex(for target: (square: Square, piece: Piece)) -> Int? {
        if let exact = indices
            .filter({ self[$0].piece == target.piece })
            .min(by: { self[$0].square.distance(to: target.square) < self[$1].square.distance(to: target.square) }) {
            return exact
        }

        return indices
            .filter { self[$0].piece.color == target.piece.color }
            .min(by: { self[$0].square.distance(to: target.square) < self[$1].square.distance(to: target.square) })
    }
}

private extension Square {
    var sortKey: Int {
        rank * 10 + file.rawValue
    }

    func distance(to other: Square) -> Int {
        abs(file.rawValue - other.file.rawValue) + abs(rank - other.rank)
    }
}
