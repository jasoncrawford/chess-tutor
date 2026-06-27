import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?
    @Namespace private var captureNamespace

    var body: some View {
        ZStack {
            AppTheme.table.ignoresSafeArea()
            HStack(alignment: .top, spacing: 28) {
                ChessBoardView(session: session, captureNamespace: captureNamespace) { result in
                    if case let .needsPromotion(from, to) = result {
                        pendingPromotion = PendingPromotion(from: from, to: to)
                    }
                }
                .frame(maxWidth: 760)
                sidePanel
                    .frame(width: 260)
                    .frame(minHeight: 240, alignment: .top)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .sheet(item: $pendingPromotion) { promotion in
            VStack(spacing: 16) {
                Text("Choose promotion")
                    .font(.title2.bold())
                ForEach([Piece.Kind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button(kind.rawValue.capitalized) {
                        session.promote(from: promotion.from, to: promotion.to, to: kind)
                        pendingPromotion = nil
                    }
                }
            }
            .padding()
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.statusText)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if let guidanceText = session.guidanceText {
                    Text(guidanceText)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, session.guidanceText == nil ? 0 : 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(session.guidanceText == nil ? Color.clear : Color.white.opacity(0.58))
            )

            captureTrays

            GameControlsView(session: session)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panel)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        )
    }

    private var captureTrays: some View {
        VStack(spacing: 6) {
            captureTray(for: .black)
            captureTray(for: .white)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    private func captureTray(for color: PieceColor) -> some View {
        let pieces = session.capturedPieces.filter { $0.piece.color == color }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6),
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(pieces) { capturedPiece in
                PieceIconView(piece: capturedPiece.piece)
                    .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
                    .frame(width: 28, height: 28)
                    .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
                    .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pieces)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.ink.opacity(pieces.isEmpty ? 0.04 : 0.07))
        )
    }
}

private struct PendingPromotion: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
}

#Preview {
    ContentView()
}
