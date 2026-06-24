import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 20) {
                ChessBoardView(session: session)
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
    }
}

#Preview {
    ContentView()
}
