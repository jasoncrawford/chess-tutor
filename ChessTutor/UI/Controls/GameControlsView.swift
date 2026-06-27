import SwiftUI

struct GameControlsView: View {
    @Bindable var session: GameSession

    var body: some View {
        HStack(spacing: 10) {
            Button {
                session.finishTurn()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .disabled(!session.canFinishTurn)

            Button {
                session.newGame()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .accessibilityLabel("New game")
            }
            Button {
                session.flipBoard()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .accessibilityLabel("Flip board")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(AppTheme.boardFrame)
    }
}
