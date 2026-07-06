import SwiftUI

struct RemotePlaySheetView: View {
    @Bindable var flow: RemotePlayFlow
    @Bindable var session: GameSession
    let onLocalDisplayNameSaved: (String) -> Void
    let onKnownPlayerAccepted: (KnownRemotePlayer) -> Void
    #if DEBUG
    let fakeRemoteLab: FakeRemoteGameLab?
    #endif

    init(
        flow: RemotePlayFlow,
        session: GameSession,
        onLocalDisplayNameSaved: @escaping (String) -> Void = { _ in },
        onKnownPlayerAccepted: @escaping (KnownRemotePlayer) -> Void = { _ in }
    ) {
        self.flow = flow
        self.session = session
        self.onLocalDisplayNameSaved = onLocalDisplayNameSaved
        self.onKnownPlayerAccepted = onKnownPlayerAccepted
        #if DEBUG
        self.fakeRemoteLab = nil
        #endif
    }

    #if DEBUG
    init(
        flow: RemotePlayFlow,
        session: GameSession,
        fakeRemoteLab: FakeRemoteGameLab? = nil,
        onLocalDisplayNameSaved: @escaping (String) -> Void = { _ in },
        onKnownPlayerAccepted: @escaping (KnownRemotePlayer) -> Void = { _ in }
    ) {
        self.flow = flow
        self.session = session
        self.fakeRemoteLab = fakeRemoteLab
        self.onLocalDisplayNameSaved = onLocalDisplayNameSaved
        self.onKnownPlayerAccepted = onKnownPlayerAccepted
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if showsIdentityRow {
                identityRow
            }

            switch flow.stage {
            case .closed:
                EmptyView()
            case .choosing:
                choosingView
            case .choosingWhite(let target):
                choosingWhiteView(for: target)
            case .waitingForInvitee(let pendingInvite):
                waitingView(for: pendingInvite)
            case .enteringLocalName:
                localNameView
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.panel)
    }

    private var header: some View {
        ZStack {
            Text(flow.sheetTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            HStack {
                if showsBackButton {
                    Button {
                        flow.goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
                    .labelStyle(.titleAndIcon)
                }

                Spacer()

                Button("Cancel") {
                    flow.cancel()
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .frame(height: 32)
    }

    private var showsIdentityRow: Bool {
        flow.showsLocalIdentitySummary
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.mutedInk)
                .frame(width: 24, height: 24)

            Text("Playing as \(flow.localDisplayName ?? "")")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                flow.editLocalDisplayName()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.mutedInk)
            .accessibilityLabel("Edit your name")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(AppTheme.panelInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var showsBackButton: Bool {
        switch flow.stage {
        case .choosingWhite:
            return true
        case .closed, .choosing, .waitingForInvitee, .enteringLocalName:
            return false
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
                    TextField("Code", text: joinCodeBinding)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AppTheme.panelInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Join") {
                        joinWithCode()
                    }
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: canJoinWithCode))
                    .disabled(!canJoinWithCode)
                }

                if let joinErrorMessage = flow.joinErrorMessage {
                    Text(joinErrorMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.68))
                }
            }
        }
    }

    private var joinCodeBinding: Binding<String> {
        Binding {
            flow.joinCode
        } set: { nextCode in
            flow.updateJoinCode(nextCode)
        }
    }

    private var canJoinWithCode: Bool {
        #if DEBUG
        flow.canSubmitJoinCode
        #else
        false
        #endif
    }

    private func joinWithCode() {
        #if DEBUG
        guard flow.requestJoinCode() else {
            return
        }

        fakeRemoteLab?.start(session: session, localPlayerColor: .black)
        onKnownPlayerAccepted(Self.fakeMayaPlayer)
        #endif
    }

    private func choosingWhiteView(for target: RemotePlayFlow.InviteTarget) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(flow.whiteChoicePromptTitle)
                .font(AppTheme.panelBodyFont)
                .foregroundStyle(AppTheme.ink.opacity(0.72))

            VStack(spacing: 8) {
                whiteChoiceButton(.localPlayer, target: target)
                whiteChoiceButton(.invitee, target: target)
                whiteChoiceButton(.inviteeChooses, target: target)
            }

            Button {
                _ = flow.requestSendInvite()
            } label: {
                Label("Send Invite", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(RemotePlaySheetPrimaryButtonStyle())
        }
    }

    private var localNameView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localNameTitle)
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text("The other player will see this when you play remotely.")
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.72))
            }

            TextField("First name or handle", text: localNameBinding)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(AppTheme.panelInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                saveLocalNameAndContinue()
            } label: {
                Label(localNameButtonTitle, systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(RemotePlaySheetPrimaryButtonStyle())
            .disabled(!flow.canSubmitLocalName)
            .opacity(flow.canSubmitLocalName ? 1 : 0.55)
        }
    }

    private var localNameTitle: String {
        if case .enteringLocalName(.edit) = flow.stage {
            return "Your name"
        }

        return "What's your name?"
    }

    private var localNameButtonTitle: String {
        if case .enteringLocalName(.edit) = flow.stage {
            return "Save"
        }

        return "Continue"
    }

    private var localNameBinding: Binding<String> {
        Binding {
            flow.localNameDraft
        } set: { nextName in
            flow.updateLocalNameDraft(nextName)
        }
    }

    private func saveLocalNameAndContinue() {
        guard let result = flow.saveLocalNameAndContinue(),
              let localDisplayName = flow.localDisplayName else {
            return
        }

        onLocalDisplayNameSaved(localDisplayName)

        #if DEBUG
        if result == .joined {
            fakeRemoteLab?.start(session: session, localPlayerColor: .black)
            onKnownPlayerAccepted(Self.fakeMayaPlayer)
        }
        #endif
    }

    private func whiteChoiceButton(
        _ choice: RemotePlayFlow.WhiteChoice,
        target: RemotePlayFlow.InviteTarget
    ) -> some View {
        Button {
            flow.chooseWhite(choice)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: flow.selectedWhiteChoice == choice ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(flow.selectedWhiteChoice == choice ? AppTheme.boardFrame : AppTheme.mutedInk)
                    .frame(width: 24)

                Text(whiteChoiceTitle(choice, target: target))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(WhiteChoiceButtonStyle(isSelected: flow.selectedWhiteChoice == choice))
    }

    private func waitingView(for pendingInvite: RemotePlayFlow.PendingInvite) -> some View {
        let presentation = flow.inviteSharePresentation(for: pendingInvite)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.codeSectionTitle)
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text(presentation.code)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .monospacedDigit()

                Text(presentation.codeInstructions)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.linkSectionTitle)
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Button(presentation.copyLinkButtonTitle) {}
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: false))
                    .disabled(true)

                Text(presentation.linkInstructions)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            HStack(spacing: 10) {
                if fakeRemoteLab != nil {
                    Button("Maya Accepts") {
                        acceptPendingInvite(pendingInvite)
                    }
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: true))
                }
            }
            #endif
        }
    }

    private func inviteeName(for target: RemotePlayFlow.InviteTarget) -> String {
        switch target {
        case .known(let player):
            return player.displayName
        case .newPlayer:
            return "Other Player"
        }
    }

    private func whiteChoiceTitle(
        _ choice: RemotePlayFlow.WhiteChoice,
        target: RemotePlayFlow.InviteTarget
    ) -> String {
        switch choice {
        case .localPlayer:
            return "Me"
        case .invitee:
            return inviteeName(for: target)
        case .inviteeChooses:
            return "Let them choose"
        }
    }

    #if DEBUG
    private func acceptPendingInvite(_ pendingInvite: RemotePlayFlow.PendingInvite) {
        let localPlayerColor = localPlayerColor(for: pendingInvite)
        fakeRemoteLab?.start(session: session, localPlayerColor: localPlayerColor)
        onKnownPlayerAccepted(Self.fakeMayaPlayer)
        flow.cancel()
    }

    private func localPlayerColor(for pendingInvite: RemotePlayFlow.PendingInvite) -> PieceColor {
        pendingInvite.whiteChoice == .invitee ? .black : .white
    }

    private static var fakeMayaPlayer: KnownRemotePlayer {
        KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
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

private struct WhiteChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppTheme.panelWarmth.opacity(0.95) : AppTheme.panelInset.opacity(0.78))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppTheme.boardFrame.opacity(0.72) : AppTheme.panelStroke, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
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
