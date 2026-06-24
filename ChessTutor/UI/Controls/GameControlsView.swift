import SwiftUI

struct GameControlsView: View {
    @Bindable var session: GameSession

    var body: some View {
        HStack {
            Button("New Game") {
                session.newGame()
            }
            Button("Flip") {
                session.flipBoard()
            }
        }
        .buttonStyle(.bordered)
    }
}
