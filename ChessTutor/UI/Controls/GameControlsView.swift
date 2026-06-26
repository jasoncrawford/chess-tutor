import SwiftUI

struct GameControlsView: View {
    @Bindable var session: GameSession

    var body: some View {
        HStack(spacing: 10) {
            Button {
                session.newGame()
            } label: {
                Label("New game", systemImage: "arrow.counterclockwise")
            }
            Button {
                session.flipBoard()
            } label: {
                Label("Flip board", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .labelStyle(.iconOnly)
        .tint(AppTheme.boardFrame)
    }
}
