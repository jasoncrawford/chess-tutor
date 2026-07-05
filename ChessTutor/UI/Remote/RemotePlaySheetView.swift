import SwiftUI

struct RemotePlaySheetView: View {
    @Bindable var flow: RemotePlayFlow
    @Bindable var session: GameSession
    #if DEBUG
    let fakeRemoteLab: FakeRemoteGameLab?
    #endif

    #if DEBUG
    init(
        flow: RemotePlayFlow,
        session: GameSession,
        fakeRemoteLab: FakeRemoteGameLab? = nil
    ) {
        self.flow = flow
        self.session = session
        self.fakeRemoteLab = fakeRemoteLab
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            switch flow.stage {
            case .closed:
                EmptyView()
            case .choosing:
                choosingView
            case .choosingWhite(let target):
                choosingWhiteView(for: target)
            case .waitingForInvitee(let pendingInvite):
                waitingView(for: pendingInvite)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.panel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Play Remotely")
                .font(AppTheme.aboutTitleFont)
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Button("Cancel") {
                flow.cancel()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.mutedInk)
        }
    }

    private var choosingView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !flow.knownPlayers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Invite")
                        .font(AppTheme.aboutSectionTitleFont)
                        .foregroundStyle(AppTheme.ink)

                    ForEach(flow.knownPlayers) { player in
                        Button {
                            flow.invite(player)
                        } label: {
                            Label(player.displayName, systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(RemotePlaySheetButtonStyle())
                    }
                }
            }

            Button {
                flow.inviteSomeoneNew()
            } label: {
                Label("Invite Someone New", systemImage: "link")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(RemotePlaySheetButtonStyle())

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Join")
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                HStack(spacing: 10) {
                    TextField("Code", text: .constant(""))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AppTheme.panelInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Join") {}
                        .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: false))
                        .disabled(true)
                }
            }
        }
    }

    private func choosingWhiteView(for target: RemotePlayFlow.InviteTarget) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(targetTitle(for: target))
                .font(AppTheme.aboutSectionTitleFont)
                .foregroundStyle(AppTheme.ink)

            Picker("White", selection: $flow.selectedWhiteChoice) {
                Text("Me").tag(RemotePlayFlow.WhiteChoice.localPlayer)
                Text(inviteeName(for: target)).tag(RemotePlayFlow.WhiteChoice.invitee)
                Text("Let them choose").tag(RemotePlayFlow.WhiteChoice.inviteeChooses)
            }
            .pickerStyle(.segmented)

            Button {
                _ = flow.sendInvite()
            } label: {
                Label("Send Invite", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(RemotePlaySheetPrimaryButtonStyle())
        }
    }

    private func waitingView(for pendingInvite: RemotePlayFlow.PendingInvite) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Sent")
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text(pendingInvite.formattedCode)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Button("Copy Link") {}
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: false))
                    .disabled(true)

                #if DEBUG
                if fakeRemoteLab != nil {
                    Button("Maya Accepts") {
                        acceptPendingInvite(pendingInvite)
                    }
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: true))
                }
                #endif
            }
        }
    }

    private func targetTitle(for target: RemotePlayFlow.InviteTarget) -> String {
        switch target {
        case .known(let player):
            return "Invite \(player.displayName)"
        case .newPlayer:
            return "Invite Someone New"
        }
    }

    private func inviteeName(for target: RemotePlayFlow.InviteTarget) -> String {
        switch target {
        case .known(let player):
            return player.displayName
        case .newPlayer:
            return "Them"
        }
    }

    #if DEBUG
    private func acceptPendingInvite(_ pendingInvite: RemotePlayFlow.PendingInvite) {
        let localPlayerColor: PieceColor = pendingInvite.whiteChoice == .invitee ? .black : .white
        fakeRemoteLab?.start(session: session, localPlayerColor: localPlayerColor)
        flow.cancel()
    }
    #endif
}

private struct RemotePlaySheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.panelWarmth.opacity(configuration.isPressed ? 0.95 : 0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
    }
}

private struct RemotePlaySheetPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.whitePiece)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.boardFrame)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct RemotePlaySheetCompactButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? AppTheme.whitePiece : AppTheme.mutedInk.opacity(0.58))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled ? AppTheme.boardFrame : AppTheme.panelInset)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
    }
}
