import SwiftUI

struct TurnStatusPanelView: View {
    @Bindable var session: GameSession
    let remotePlayFlow: RemotePlayFlow?
    let onPlayRemotely: () -> Void
    let onNewGame: () -> Void
    #if DEBUG
    let fakeRemoteLab: FakeRemoteGameLab?

    init(
        session: GameSession,
        remotePlayFlow: RemotePlayFlow? = nil,
        onPlayRemotely: @escaping () -> Void = {},
        onNewGame: @escaping () -> Void = {},
        fakeRemoteLab: FakeRemoteGameLab? = nil
    ) {
        self.session = session
        self.remotePlayFlow = remotePlayFlow
        self.onPlayRemotely = onPlayRemotely
        self.onNewGame = onNewGame
        self.fakeRemoteLab = fakeRemoteLab
    }
    #endif

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

            GameControlsView(
                session: session,
                isRemotePlayAvailable: remotePlayFlow?.canShowEntryPoint(for: session) ?? false,
                onPlayRemotely: onPlayRemotely,
                onNewGame: onNewGame,
                onCommittedMove: { move in
                #if DEBUG
                    guard let fakeRemoteLab else {
                        return
                    }
                    Task { @MainActor in
                        try? await fakeRemoteLab.recordCommittedLocalMove(move)
                    }
                #endif
                }
            )

            #if DEBUG
            if let fakeRemoteLab, fakeRemoteLab.isActive {
                FakeRemoteLabControlsView(session: session, lab: fakeRemoteLab)
                    .padding(.top, 2)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
private struct FakeRemoteLabControlsView: View {
    @Bindable var session: GameSession
    let lab: FakeRemoteGameLab

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { @MainActor in
                    try? await lab.remotePlaysNextMove(session: session)
                }
            } label: {
                Label("Maya", systemImage: "person.crop.circle.badge.checkmark")
            }
            .disabled(!lab.canRemotePlay)
        }
        .buttonStyle(FakeRemoteLabButtonStyle())
        .labelStyle(.iconOnly)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FakeRemoteLabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 30)
            .foregroundStyle(AppTheme.mutedInk)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.panelWarmth.opacity(configuration.isPressed ? 0.95 : 0.62))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.panelStroke.opacity(0.9), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }
}
#endif
