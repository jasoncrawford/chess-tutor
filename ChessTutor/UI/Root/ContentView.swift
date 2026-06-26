import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.table.ignoresSafeArea()
                HStack(alignment: .top, spacing: 28) {
                    ChessBoardView(session: session) { result in
                        if case let .needsPromotion(from, to) = result {
                            pendingPromotion = PendingPromotion(from: from, to: to)
                        }
                    }
                    .frame(maxWidth: 760)
                    sidePanel
                        .frame(width: 320)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
            }
            .navigationTitle("Chess Tutor")
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("At the board")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .textCase(.uppercase)
                Text(session.statusText)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(session.message ?? "Tap or drag a piece to make a move.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(minHeight: 36, alignment: .topLeading)
            }

            GameControlsView(session: session)

            Divider()
                .overlay(AppTheme.boardFrame.opacity(0.18))

            VStack(alignment: .leading, spacing: 10) {
                Text("Moves")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                MoveHistoryView(moves: session.state.moveHistory)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panel)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
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
