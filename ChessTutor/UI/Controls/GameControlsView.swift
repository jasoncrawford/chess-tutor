import SwiftUI

struct GameControlsView: View {
    @Bindable var session: GameSession
    @State private var isConfirmingNewGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            turnControls

            Spacer(minLength: 20)

            newGameButton
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .controlSize(.regular)
        .transaction { transaction in
            transaction.animation = nil
        }
        .alert("Start a new game?", isPresented: $isConfirmingNewGame) {
            Button("Keep Playing", role: .cancel) {}
            Button("New Game", role: .destructive) {
                session.newGame()
            }
        } message: {
            Text("This will abandon the current game.")
        }
    }

    private var turnControls: some View {
        VStack(spacing: 10) {
            Button {
                guard session.canFinishTurn else {
                    withoutAnimation {
                        session.message = "Make a move first."
                    }
                    return
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    session.finishTurn()
                }
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                session.flipBoard()
            } label: {
                Label("Flip Board", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.titleAndIcon)
        .tint(AppTheme.boardFrame)
    }

    private var newGameButton: some View {
        Button {
            if session.hasGameInProgress {
                isConfirmingNewGame = true
            } else {
                session.newGame()
            }
        } label: {
            Label("New Game...", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.ink.opacity(0.72))
    }

    private func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, action)
    }
}
