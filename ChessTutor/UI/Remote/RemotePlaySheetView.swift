import SwiftUI
import UIKit

struct RemotePlaySheetView: View {
    @Bindable var flow: RemotePlayFlow
    @Bindable var session: GameSession
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var inviteLinkShareItem: InviteLinkShareItem?
    @State private var remoteInviteTask: Task<Void, Never>?
    @State private var remoteInviteErrorMessage: String?
    @State private var isWorkingWithRemoteInvite = false
    @State private var activeRemoteInviteRequest: RemoteInviteRequest?
    let onLocalDisplayNameSaved: (String) -> Void
    let onInviteLinkCopied: (URL) -> Void
    let onKnownPlayerAccepted: (KnownRemotePlayer) -> Void
    let onRemoteGameStarted: (RemoteGameStartAnnouncement) -> Void
    let onRemoteInviteConfirmationNeeded: (RemoteInviteConfirmation, RemotePendingInvite?) -> Void
    let onPendingRemoteInviteCancelled: (RemotePlayFlow.PendingInvite) -> Void
    let onCreatedRemoteInviteAbandoned: (RemotePendingInvite) -> Void
    let onCreateRemoteInvite: @Sendable (RemotePlayFlow.InviteTarget, RemotePlayFlow.WhiteChoice) async throws -> RemotePendingInvite
    let onFetchRemoteInvite: @Sendable (InviteCode, RemoteInviteToken?) async throws -> RemotePendingInvite
    let onFetchAcceptedRemoteInvite: @Sendable (RemoteInviteID) async throws -> RemoteAcceptedInvite?
    let onRemoteInviteAccepted: (RemoteAcceptedInvite) -> Void
    let onRemoteInviteCreated: (RemotePendingInvite) -> Bool
    #if DEBUG
    let fakeRemoteLab: FakeRemoteGameLab?
    #endif

    init(
        flow: RemotePlayFlow,
        session: GameSession,
        onLocalDisplayNameSaved: @escaping (String) -> Void = { _ in },
        onInviteLinkCopied: @escaping (URL) -> Void = { _ in },
        onKnownPlayerAccepted: @escaping (KnownRemotePlayer) -> Void = { _ in },
        onRemoteGameStarted: @escaping (RemoteGameStartAnnouncement) -> Void = { _ in },
        onRemoteInviteConfirmationNeeded: @escaping (RemoteInviteConfirmation, RemotePendingInvite?) -> Void = { _, _ in },
        onPendingRemoteInviteCancelled: @escaping (RemotePlayFlow.PendingInvite) -> Void = { _ in },
        onCreatedRemoteInviteAbandoned: @escaping (RemotePendingInvite) -> Void = { _ in },
        onCreateRemoteInvite: @escaping @Sendable (RemotePlayFlow.InviteTarget, RemotePlayFlow.WhiteChoice) async throws -> RemotePendingInvite = { _, _ in
            throw RemoteInviteTransportError.notFound
        },
        onFetchRemoteInvite: @escaping @Sendable (InviteCode, RemoteInviteToken?) async throws -> RemotePendingInvite = { _, _ in
            throw RemoteInviteTransportError.notFound
        },
        onFetchAcceptedRemoteInvite: @escaping @Sendable (RemoteInviteID) async throws -> RemoteAcceptedInvite? = { _ in nil },
        onRemoteInviteAccepted: @escaping (RemoteAcceptedInvite) -> Void = { _ in },
        onRemoteInviteCreated: @escaping (RemotePendingInvite) -> Bool = { _ in false }
    ) {
        self.flow = flow
        self.session = session
        self.onLocalDisplayNameSaved = onLocalDisplayNameSaved
        self.onInviteLinkCopied = onInviteLinkCopied
        self.onKnownPlayerAccepted = onKnownPlayerAccepted
        self.onRemoteGameStarted = onRemoteGameStarted
        self.onRemoteInviteConfirmationNeeded = onRemoteInviteConfirmationNeeded
        self.onPendingRemoteInviteCancelled = onPendingRemoteInviteCancelled
        self.onCreatedRemoteInviteAbandoned = onCreatedRemoteInviteAbandoned
        self.onCreateRemoteInvite = onCreateRemoteInvite
        self.onFetchRemoteInvite = onFetchRemoteInvite
        self.onFetchAcceptedRemoteInvite = onFetchAcceptedRemoteInvite
        self.onRemoteInviteAccepted = onRemoteInviteAccepted
        self.onRemoteInviteCreated = onRemoteInviteCreated
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
        onInviteLinkCopied: @escaping (URL) -> Void = { _ in },
        onKnownPlayerAccepted: @escaping (KnownRemotePlayer) -> Void = { _ in },
        onRemoteGameStarted: @escaping (RemoteGameStartAnnouncement) -> Void = { _ in },
        onRemoteInviteConfirmationNeeded: @escaping (RemoteInviteConfirmation, RemotePendingInvite?) -> Void = { _, _ in },
        onPendingRemoteInviteCancelled: @escaping (RemotePlayFlow.PendingInvite) -> Void = { _ in },
        onCreatedRemoteInviteAbandoned: @escaping (RemotePendingInvite) -> Void = { _ in },
        onCreateRemoteInvite: @escaping @Sendable (RemotePlayFlow.InviteTarget, RemotePlayFlow.WhiteChoice) async throws -> RemotePendingInvite = { _, _ in
            throw RemoteInviteTransportError.notFound
        },
        onFetchRemoteInvite: @escaping @Sendable (InviteCode, RemoteInviteToken?) async throws -> RemotePendingInvite = { _, _ in
            throw RemoteInviteTransportError.notFound
        },
        onFetchAcceptedRemoteInvite: @escaping @Sendable (RemoteInviteID) async throws -> RemoteAcceptedInvite? = { _ in nil },
        onRemoteInviteAccepted: @escaping (RemoteAcceptedInvite) -> Void = { _ in },
        onRemoteInviteCreated: @escaping (RemotePendingInvite) -> Bool = { _ in false }
    ) {
        self.flow = flow
        self.session = session
        self.fakeRemoteLab = fakeRemoteLab
        self.onLocalDisplayNameSaved = onLocalDisplayNameSaved
        self.onInviteLinkCopied = onInviteLinkCopied
        self.onKnownPlayerAccepted = onKnownPlayerAccepted
        self.onRemoteGameStarted = onRemoteGameStarted
        self.onRemoteInviteConfirmationNeeded = onRemoteInviteConfirmationNeeded
        self.onPendingRemoteInviteCancelled = onPendingRemoteInviteCancelled
        self.onCreatedRemoteInviteAbandoned = onCreatedRemoteInviteAbandoned
        self.onCreateRemoteInvite = onCreateRemoteInvite
        self.onFetchRemoteInvite = onFetchRemoteInvite
        self.onFetchAcceptedRemoteInvite = onFetchAcceptedRemoteInvite
        self.onRemoteInviteAccepted = onRemoteInviteAccepted
        self.onRemoteInviteCreated = onRemoteInviteCreated
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
            case .terminalInvite(let presentation):
                terminalInviteView(presentation)
            case .enteringLocalName:
                localNameView
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.panel)
        .onDisappear {
            remoteInviteTask?.cancel()
            remoteInviteTask = nil
            isWorkingWithRemoteInvite = false
            activeRemoteInviteRequest = nil
        }
        .sheet(item: $inviteLinkShareItem) { item in
            InviteLinkShareSheet(url: item.url)
        }
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
                    .disabled(isWorkingWithRemoteInvite)
                    .opacity(isWorkingWithRemoteInvite ? 0.55 : 1)
                }

                Spacer()

                Button("Cancel") {
                    cancelRemotePlaySheet()
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
        case .closed, .choosing, .waitingForInvitee, .terminalInvite, .enteringLocalName:
            return false
        }
    }

    private var choosingView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let remoteInviteErrorMessage {
                Text(remoteInviteErrorMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.72, green: 0.23, blue: 0.17))
            }

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
                        .disabled(isWorkingWithRemoteInvite)
                        .opacity(isWorkingWithRemoteInvite ? 0.55 : 1)
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
            .disabled(isWorkingWithRemoteInvite)
            .opacity(isWorkingWithRemoteInvite ? 0.55 : 1)

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

                if let joinErrorMessage = flow.joinErrorMessage ?? remoteInviteErrorMessage {
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
            remoteInviteErrorMessage = nil
        }
    }

    private var canJoinWithCode: Bool {
        flow.canSubmitJoinCode && !isWorkingWithRemoteInvite
    }

    private func joinWithCode() {
        joinWithCode(using: nil)
    }

    private func cancelRemotePlaySheet() {
        if case .waitingForInvitee(let pendingInvite) = flow.stage {
            onPendingRemoteInviteCancelled(pendingInvite)
        }
        flow.cancel()
    }

    private func joinWithCode(using pendingLookup: RemotePlayFlow.InviteLookup?) {
        guard flow.localDisplayName != nil else {
            _ = flow.requestJoinCode()
            return
        }

        let code = pendingLookup?.code ?? InviteCode(rawValue: flow.joinCode)
        let token = pendingLookup?.token
        let request = RemoteInviteRequest(kind: .fetch(code: code, token: token))
        isWorkingWithRemoteInvite = true
        activeRemoteInviteRequest = request
        remoteInviteErrorMessage = nil
        remoteInviteTask?.cancel()
        remoteInviteTask = Task { @MainActor in
            defer {
                if activeRemoteInviteRequest == request {
                    isWorkingWithRemoteInvite = false
                    activeRemoteInviteRequest = nil
                    remoteInviteTask = nil
                }
            }

            do {
                let invite = try await onFetchRemoteInvite(code, token)
                guard isCurrentRemoteInviteRequest(request) else {
                    return
                }
                flow.cancel()
                onRemoteInviteConfirmationNeeded(
                    RemoteInviteConfirmation(
                        opponentName: invite.inviter.displayName,
                        localPlayerColor: invite.whiteAssignment.localPlayerColorForJoiner
                    ),
                    invite
                )
            } catch {
                guard isCurrentRemoteInviteRequest(request) else {
                    return
                }
                if let terminalMessage = Self.terminalInviteMessage(from: error) {
                    flow.showTerminalInviteMessage(terminalMessage)
                    return
                }
                remoteInviteErrorMessage = error.remoteInviteJoinFailureMessage(
                    fallbackKind: token == nil ? .code : .link
                )
            }
        }
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
                sendInvite(target: target)
            } label: {
                Label("Send Invite", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(RemotePlaySheetPrimaryButtonStyle())
            .disabled(isWorkingWithRemoteInvite)
            .opacity(isWorkingWithRemoteInvite ? 0.55 : 1)

            if let remoteInviteErrorMessage {
                Text(remoteInviteErrorMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.72, green: 0.23, blue: 0.17))
            }
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
        if case .enteringLocalName(.joinWithCode) = flow.stage {
            guard let lookup = flow.saveLocalNameForPendingJoin(),
                  let localDisplayName = flow.localDisplayName else {
                return
            }

            onLocalDisplayNameSaved(localDisplayName)
            joinWithCode(using: lookup)
            return
        }

        guard let result = flow.saveLocalNameAndContinue(),
              let localDisplayName = flow.localDisplayName else {
            return
        }

        onLocalDisplayNameSaved(localDisplayName)

        #if DEBUG
        switch result {
        case .needsConfirmation(let confirmation):
            onRemoteInviteConfirmationNeeded(confirmation, nil)
        case .sentInvite(let pendingInvite):
            createRemoteInvite(target: pendingInvite.target, whiteChoice: pendingInvite.whiteChoice)
        case .saved:
            break
        }
        #else
        if case .sentInvite(let pendingInvite) = result {
            createRemoteInvite(target: pendingInvite.target, whiteChoice: pendingInvite.whiteChoice)
        }
        #endif
    }

    private func sendInvite(target: RemotePlayFlow.InviteTarget) {
        remoteInviteErrorMessage = nil
        let whiteChoice = flow.selectedWhiteChoice

        guard flow.localDisplayName != nil else {
            _ = flow.requestSendInvite()
            return
        }

        createRemoteInvite(target: target, whiteChoice: whiteChoice)
    }

    private func createRemoteInvite(
        target: RemotePlayFlow.InviteTarget,
        whiteChoice: RemotePlayFlow.WhiteChoice
    ) {
        let request = RemoteInviteRequest(kind: .create(target: target, whiteChoice: whiteChoice))
        showInviteChoice(target: target, whiteChoice: whiteChoice)
        isWorkingWithRemoteInvite = true
        activeRemoteInviteRequest = request
        remoteInviteErrorMessage = nil
        remoteInviteTask?.cancel()
        remoteInviteTask = Task { @MainActor in
            defer {
                if activeRemoteInviteRequest == request {
                    isWorkingWithRemoteInvite = false
                    activeRemoteInviteRequest = nil
                    remoteInviteTask = nil
                }
            }

            do {
                let invite = try await onCreateRemoteInvite(target, whiteChoice)
                guard isCurrentRemoteInviteRequest(request) else {
                    onCreatedRemoteInviteAbandoned(invite)
                    return
                }
                if onRemoteInviteCreated(invite) {
                    flow.cancel()
                } else {
                    flow.showCreatedRemoteInvite(invite, target: target)
                }
            } catch {
                guard isCurrentRemoteInviteRequest(request) else {
                    return
                }
                showInviteChoice(target: target, whiteChoice: whiteChoice)
                remoteInviteErrorMessage = "Could not create invite. Check your connection and try again."
            }
        }
    }

    private func isCurrentRemoteInviteRequest(_ request: RemoteInviteRequest) -> Bool {
        guard activeRemoteInviteRequest == request,
              !Task.isCancelled else {
            return false
        }

        switch request.kind {
        case .create(let target, let whiteChoice):
            return flow.stage == .choosingWhite(target)
                && flow.selectedWhiteChoice == whiteChoice
        case .fetch(let code, _):
            return flow.joinCode == code.rawValue
        }
    }

    private func showInviteChoice(
        target: RemotePlayFlow.InviteTarget,
        whiteChoice: RemotePlayFlow.WhiteChoice
    ) {
        switch target {
        case .known(let player):
            flow.invite(player)
        case .newPlayer:
            flow.inviteSomeoneNew()
        }
        flow.chooseWhite(whiteChoice)
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
        .disabled(isWorkingWithRemoteInvite)
        .opacity(isWorkingWithRemoteInvite ? 0.55 : 1)
    }

    private func waitingView(for pendingInvite: RemotePlayFlow.PendingInvite) -> some View {
        let waitingPresentation = flow.inviteWaitingPresentation(for: pendingInvite)
        let shouldShowFallback = flow.shouldShowInviteShareFallback(for: pendingInvite)
        let presentation = flow.inviteSharePresentation(for: pendingInvite)

        return VStack(alignment: .leading, spacing: 18) {
            if pendingInvite.isAddressed {
                VStack(alignment: .leading, spacing: 10) {
                    Text(waitingPresentation.title)
                        .font(AppTheme.panelBodyFont)
                        .foregroundStyle(AppTheme.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    if !shouldShowFallback {
                        Button(waitingPresentation.fallbackButtonTitle) {
                            flow.showInviteShareFallback(for: pendingInvite)
                        }
                        .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: true))
                    }
                }
            }

            if shouldShowFallback {
                inviteShareFallbackView(presentation)
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
        .task(id: pendingInvite.remoteInviteID) {
            #if DEBUG
            guard fakeRemoteLab == nil else {
                return
            }
            #endif
            await pollForAcceptedInvite(pendingInvite)
        }
    }

    private func terminalInviteView(_ presentation: RemotePlayFlow.TerminalInvitePresentation) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(presentation.message)
                .font(AppTheme.panelBodyFont)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button(presentation.buttonTitle) {
                flow.cancel()
            }
            .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: true))
        }
    }

    private func inviteShareFallbackView(_ presentation: RemotePlayFlow.InviteSharePresentation) -> some View {
        VStack(alignment: .leading, spacing: 18) {
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

                HStack(spacing: 10) {
                    Button {
                        copyInviteLink(presentation.inviteURL)
                    } label: {
                        Text(presentation.copyLinkButtonTitle)
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: presentation.isCopyLinkButtonEnabled))
                    .disabled(!presentation.isCopyLinkButtonEnabled)
                    .animation(.easeInOut(duration: 0.18), value: presentation.copyLinkButtonTitle)
                    .animation(.easeInOut(duration: 0.18), value: presentation.isCopyLinkButtonEnabled)

                    Button(presentation.shareLinkButtonTitle) {
                        inviteLinkShareItem = InviteLinkShareItem(url: presentation.inviteURL)
                    }
                    .buttonStyle(RemotePlaySheetCompactButtonStyle(isEnabled: true))
                }

                Text(presentation.linkInstructions)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyInviteLink(_ inviteURL: URL) {
        onInviteLinkCopied(inviteURL)
        flow.markInviteLinkCopied(inviteURL)

        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            flow.clearCopiedInviteLink()
            copyFeedbackTask = nil
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
        if let announcement = fakeRemoteLab?.start(session: session, localPlayerColor: localPlayerColor) {
            onRemoteGameStarted(announcement)
        }
        onKnownPlayerAccepted(Self.fakeMayaPlayer)
        flow.cancel()
    }

    private func localPlayerColor(for pendingInvite: RemotePlayFlow.PendingInvite) -> PieceColor {
        switch pendingInvite.whiteChoice {
        case .localPlayer:
            return .white
        case .invitee:
            return .black
        case .inviteeChooses:
            return .white
        }
    }

    private static var fakeMayaPlayer: KnownRemotePlayer {
        KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya")
    }
    #endif

    private func pollForAcceptedInvite(_ pendingInvite: RemotePlayFlow.PendingInvite) async {
        guard let inviteID = pendingInvite.remoteInviteID else {
            return
        }

        while !Task.isCancelled {
            do {
                guard case .waitingForInvitee(let currentInvite) = flow.stage,
                      currentInvite.remoteInviteID == inviteID else {
                    return
                }
                guard let acceptedInvite = try await onFetchAcceptedRemoteInvite(inviteID) else {
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                flow.cancel()
                onRemoteInviteAccepted(acceptedInvite)
                return
            } catch is CancellationError {
                return
            } catch {
                if let terminalMessage = Self.terminalInviteMessage(from: error) {
                    flow.showTerminalInviteMessage(terminalMessage)
                    return
                }
                continue
            }
        }
    }

    private static func terminalInviteMessage(from error: Error) -> String? {
        guard let remoteInviteError = error as? RemoteInviteTransportError else {
            return nil
        }

        switch remoteInviteError {
        case .cancelled(let inviterDisplayName):
            return "Sorry, \(inviterDisplayName) canceled this game."
        case .declined(let inviteeDisplayName):
            return "Sorry, \(inviteeDisplayName ?? "the other player") declined this game."
        case .notFound, .tokenMismatch, .expired, .notPending, .colorChoiceRequired, .colorChoiceNotAllowed, .codeCollision:
            return nil
        }
    }
}

private struct RemoteInviteRequest: Equatable {
    let id = UUID()
    let kind: Kind

    enum Kind: Equatable {
        case create(target: RemotePlayFlow.InviteTarget, whiteChoice: RemotePlayFlow.WhiteChoice)
        case fetch(code: InviteCode, token: RemoteInviteToken?)
    }
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

private struct InviteLinkShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct InviteLinkShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
