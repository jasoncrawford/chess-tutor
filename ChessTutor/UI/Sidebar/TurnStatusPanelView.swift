import SwiftUI

struct TurnStatusPanelView: View {
    @Bindable var session: GameSession
    let onAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    .fill(session.guidanceText == nil ? Color.clear : AppTheme.panelInset)
            )

            Spacer(minLength: 0)

            GameControlsView(session: session, placement: .done)

            GameControlsView(session: session, placement: .newGame, onAbout: onAbout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
