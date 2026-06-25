import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                ChessBoardView(session: session) { result in
                    if case let .needsPromotion(from, to) = result {
                        pendingPromotion = PendingPromotion(from: from, to: to)
                    }
                }
                    .frame(maxWidth: 720)
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(session.state.sideToMove.rawValue.capitalized) to move")
                        .font(.title2.bold())
                    if let message = session.message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    GameControlsView(session: session)
                    MoveHistoryView(moves: session.state.moveHistory)
                }
                .frame(width: 280)
            }
            .padding(24)
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
}

private struct PendingPromotion: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
}

#Preview {
    ContentView()
}
