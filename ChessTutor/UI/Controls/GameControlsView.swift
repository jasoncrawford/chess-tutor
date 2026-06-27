import SwiftUI

enum GameControlsPlacement {
    case done
    case newGame
}

struct GameControlsView: View {
    @Bindable var session: GameSession
    let placement: GameControlsPlacement
    @State private var isConfirmingNewGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if placement == .done {
                turnControls
            } else {
                newGameButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        doneButton
        .labelStyle(.titleAndIcon)
        .tint(AppTheme.boardFrame)
    }

    private var doneButton: some View {
        Button {
            guard session.canFinishTurn else {
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
        .disabled(!session.canFinishTurn)
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
}
