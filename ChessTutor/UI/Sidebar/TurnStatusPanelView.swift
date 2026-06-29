import SwiftUI

struct TurnStatusPanelView: View {
    @Bindable var session: GameSession
    #if DEBUG
    @Binding var isCaptureTestModeEnabled: Bool
    #endif
    let onAbout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.statusText)
                .font(AppTheme.panelTitleFont)
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            if let guidanceText = session.guidanceText {
                Text(guidanceText)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            #if DEBUG
            Toggle("Capture Test", isOn: $isCaptureTestModeEnabled)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .toggleStyle(.switch)
                .accessibilityIdentifier("capture-test-toggle")
            #endif

            GameControlsView(session: session, placement: .done)

            GameControlsView(session: session, placement: .newGame, onAbout: onAbout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
