import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?
    @State private var isShowingAbout = false
    @State private var remotePlayFlow: RemotePlayFlow
    @State private var pendingRemoteStartAnnouncement: RemoteGameStartAnnouncement?
    @State private var pendingRemoteInviteConfirmation: RemoteInviteConfirmation?
    @State private var pendingRemoteInviteAcceptance: PendingRemoteInviteAcceptance?
    @State private var remoteInviteAcceptanceTask: Task<Void, Never>?
    @State private var activeRemoteGameController: RemoteGameSessionController?
    @State private var remoteMoveFetchTask: Task<Void, Never>?
    @State private var remotePresenceHeartbeatTask: Task<Void, Never>?
    @State private var remoteActiveMovingResetTask: Task<Void, Never>?
    @State private var remoteOpponentPresence: RemotePresenceUpdate?
    @State private var lastRemoteActivePresencePublishedAt: Date?
    @State private var activeInviteLinkRequest: InviteLinkRequest?
    @State private var inviteLinkFetchTask: Task<Void, Never>?
    @State private var baselineOrientation = UIInterfaceOrientation.landscapeLeft
    @State private var viewingAngle: BoardViewingAngle
    @State private var tableRotationDegrees: Double
    @Environment(\.scenePhase) private var scenePhase
    private let remoteIdentityStore: RemoteIdentityStore
    private let activeRemoteGameStore: ActiveRemoteGameStore
    private let remoteInviteTransport: any RemoteInviteTransport
    private let remoteGameTransport: any RemoteGameTransport
    private let remotePlayRuntimeMode: RemotePlayRuntimeMode
    #if DEBUG
    @State private var isCaptureTestModeEnabled = false
    @State private var fakeRemoteLab = FakeRemoteGameLab()
    #endif
    @Namespace private var captureNamespace

    init() {
        let remoteIdentityStore = RemoteIdentityStore()
        self.remoteIdentityStore = remoteIdentityStore
        let activeRemoteGameStore = ActiveRemoteGameStore()
        self.activeRemoteGameStore = activeRemoteGameStore
        let runtimeMode = RemotePlayRuntimeMode.resolve()
        self.remotePlayRuntimeMode = runtimeMode
        self.remoteInviteTransport = Self.remoteInviteTransport(for: runtimeMode)
        self.remoteGameTransport = Self.remoteGameTransport(for: runtimeMode)
        let localProfile = try? remoteIdentityStore.loadLocalProfile()
        _remotePlayFlow = State(
            initialValue: RemotePlayFlow(
                knownPlayers: (try? remoteIdentityStore.loadKnownPlayers()) ?? [],
                localDisplayName: localProfile?.displayName
            )
        )

        let initialViewingAngle = Self.currentViewingAngle()
        _viewingAngle = State(initialValue: initialViewingAngle)
        _tableRotationDegrees = State(initialValue: initialViewingAngle.tableRotationDegrees)

        if let snapshot = try? activeRemoteGameStore.load(),
           let restoredSession = try? Self.restoredSession(from: snapshot),
           let restoredController = try? RemoteGameSessionController(
                snapshot: snapshot,
                transport: self.remoteGameTransport
           ) {
            Self.applyRemoteSeats(from: snapshot.descriptor, to: restoredSession)
            _session = State(initialValue: restoredSession)
            _activeRemoteGameController = State(initialValue: restoredController)
        } else if (try? activeRemoteGameStore.load()) != nil {
            try? activeRemoteGameStore.clear()
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = PlaySurfaceLayout.make(for: proxy.size)

            ZStack {
                AppTheme.table.ignoresSafeArea()
                tabletop(boardSide: layout.boardSide)
                    .frame(width: layout.tabletopSize.width, height: layout.tabletopSize.height)
                    .rotationEffect(.degrees(tableRotationDegrees))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let pendingRemoteStartAnnouncement {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    RemoteGameStartAnnouncementView(
                        announcement: pendingRemoteStartAnnouncement,
                        onStart: dismissRemoteStartAnnouncement
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if let pendingRemoteInviteConfirmation {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    RemoteInviteConfirmationView(
                        confirmation: pendingRemoteInviteConfirmation,
                        onSelectColor: selectRemoteInviteColor,
                        onStart: confirmRemoteInvite,
                        onCancel: cancelRemoteInvite
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: pendingRemoteStartAnnouncement)
            .animation(.easeInOut(duration: 0.18), value: pendingRemoteInviteConfirmation)
        }
        .onAppear {
            syncToCurrentInterfaceOrientation(animated: false)
            DispatchQueue.main.async {
                syncToCurrentInterfaceOrientation(animated: false)
            }
            resumeRemoteSyncIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            guard orientation.isValidBoardViewingOrientation else {
                return
            }
            let nextAngle = BoardViewingAngle(deviceOrientation: orientation, baseline: baselineOrientation.deviceOrientation)
            applyViewingAngle(nextAngle, animated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteInviteAcceptanceMayHaveChanged)) { notification in
            guard let rawInviteID = notification.userInfo?[RemoteInviteAcceptancePushUserInfoKey.inviteID] as? String else {
                return
            }
            fetchAcceptedInviteAfterPush(id: RemoteInviteID(rawValue: rawInviteID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteGameMovesMayHaveChanged)) { notification in
            guard let rawGameID = notification.userInfo?[RemoteGameMovePushUserInfoKey.gameID] as? String else {
                return
            }
            fetchRemoteMovesAfterPush(gameID: RemoteGameID(rawValue: rawGameID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .remoteGameStatusMayHaveChanged)) { notification in
            guard let rawGameID = notification.userInfo?[RemoteGameStatusPushUserInfoKey.gameID] as? String else {
                return
            }
            fetchRemoteGameStatusAfterPush(gameID: RemoteGameID(rawValue: rawGameID))
        }
        .sheet(item: $pendingPromotion) { promotion in
            PromotionPickerView(color: promotion.color) { kind in
                #if DEBUG
                if let testingSquare = promotion.testingSquare {
                    session.promoteForTesting(at: testingSquare, to: kind)
                    pendingPromotion = nil
                    return
                }
                #endif

                session.promote(from: promotion.from, to: promotion.to, to: kind)
                pendingPromotion = nil
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutSheetView()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: remotePlaySheetBinding) {
            #if DEBUG
            RemotePlaySheetView(
                flow: remotePlayFlow,
                session: session,
                fakeRemoteLab: activeFakeRemoteLab,
                onLocalDisplayNameSaved: saveLocalDisplayName,
                onInviteLinkCopied: copyInviteLink,
                onKnownPlayerAccepted: rememberKnownPlayer,
                onRemoteGameStarted: showRemoteStartAnnouncement,
                onRemoteInviteConfirmationNeeded: showRemoteInviteConfirmation,
                onCreateRemoteInvite: createRemoteInvite,
                onFetchRemoteInvite: fetchRemoteInvite,
                onFetchAcceptedRemoteInvite: fetchAcceptedRemoteInvite,
                onRemoteInviteAccepted: startInviterRemoteGame
            )
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
            #else
            RemotePlaySheetView(
                flow: remotePlayFlow,
                session: session,
                onLocalDisplayNameSaved: saveLocalDisplayName,
                onInviteLinkCopied: copyInviteLink,
                onKnownPlayerAccepted: rememberKnownPlayer,
                onRemoteGameStarted: showRemoteStartAnnouncement,
                onRemoteInviteConfirmationNeeded: showRemoteInviteConfirmation,
                onCreateRemoteInvite: createRemoteInvite,
                onFetchRemoteInvite: fetchRemoteInvite,
                onFetchAcceptedRemoteInvite: fetchAcceptedRemoteInvite,
                onRemoteInviteAccepted: startInviterRemoteGame
            )
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
            #endif
        }
        .onOpenURL { url in
            handleInviteURL(url)
        }
    }

    private func tabletop(boardSide: CGFloat) -> some View {
        HStack(alignment: .top, spacing: PlaySurfaceLayout.boardPanelSpacing) {
            chessBoard
                .frame(width: boardSide, height: boardSide)
            sidePanelContainer(sideLength: boardSide)
        }
        .frame(
            width: boardSide + PlaySurfaceLayout.boardPanelSpacing + PlaySurfaceLayout.sidePanelWidth,
            height: boardSide
        )
    }

    private var chessBoard: some View {
        let handleMoveAttempt: (MoveAttemptResult) -> Void = { result in
            if case let .needsPromotion(from, to) = result {
                pendingPromotion = PendingPromotion(from: from, to: to, color: session.state.sideToMove)
            }
        }

        #if DEBUG
        return ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            isCaptureTestModeEnabled: isCaptureTestModeEnabled,
            onPromotionTestRequest: { square, color in
                pendingPromotion = PendingPromotion(testingSquare: square, color: color)
            },
            onMoveAttempt: handleMoveAttempt,
            onLocalBoardInteraction: reportLocalBoardInteraction
        )
        #else
        return ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            onMoveAttempt: handleMoveAttempt,
            onLocalBoardInteraction: reportLocalBoardInteraction
        )
        #endif
    }

    private func sidePanelContainer(sideLength: CGFloat) -> some View {
        #if DEBUG
        return SidePanelView(
            session: session,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            captureNamespace: captureNamespace,
            sideLength: sideLength,
            remotePlayFlow: remotePlayFlow,
            onAbout: {
                isShowingAbout = true
            },
            onPlayRemotely: {
                remotePlayFlow.open()
            },
            onNewGame: startNewGame,
            remoteNewGameOpponentName: activeRemoteGameOpponent?.displayName,
            remotePresence: remoteOpponentPresence,
            onInviteRemoteNewGame: inviteActiveRemoteOpponentAgain,
            onCommittedMove: handleCommittedMove,
            fakeRemoteLab: activeFakeRemoteLab
        )
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: sideLength, alignment: .top)
        #else
        return SidePanelView(
            session: session,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            captureNamespace: captureNamespace,
            sideLength: sideLength,
            remotePlayFlow: remotePlayFlow,
            onAbout: {
                isShowingAbout = true
            },
            onPlayRemotely: {
                remotePlayFlow.open()
            },
            onNewGame: startNewGame,
            remoteNewGameOpponentName: activeRemoteGameOpponent?.displayName,
            remotePresence: remoteOpponentPresence,
            onInviteRemoteNewGame: inviteActiveRemoteOpponentAgain,
            onCommittedMove: handleCommittedMove
        )
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: sideLength, alignment: .top)
        #endif
    }

    private func startNewGame() {
        publishRemoteGameEndedIfNeeded()
        cancelRemoteGameSync(clearSavedGame: true)
        #if DEBUG
        GameLifecycle.startNewGame(
            session: session,
            remotePlayFlow: remotePlayFlow,
            fakeRemoteLab: activeFakeRemoteLab
        )
        #else
        GameLifecycle.startNewGame(session: session, remotePlayFlow: remotePlayFlow)
        #endif
    }

    private var activeRemoteGameOpponent: KnownRemotePlayer? {
        guard let descriptor = activeRemoteGameController?.snapshot.descriptor else {
            return nil
        }
        let opponent: RemotePlayerRef
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            opponent = descriptor.blackPlayer
        } else {
            opponent = descriptor.whitePlayer
        }
        return KnownRemotePlayer(id: opponent.id, displayName: opponent.displayName)
    }

    private func inviteActiveRemoteOpponentAgain() {
        guard let opponent = activeRemoteGameOpponent else {
            return
        }
        remotePlayFlow.open()
        remotePlayFlow.invite(opponent)
    }

    private func rememberKnownPlayer(_ player: KnownRemotePlayer) {
        try? remoteIdentityStore.saveKnownPlayer(player)
        remotePlayFlow.rememberKnownPlayer(player)
    }

    private func saveLocalDisplayName(_ displayName: String) {
        if let profile = try? remoteIdentityStore.saveLocalDisplayName(displayName) {
            remotePlayFlow.updateLocalDisplayName(profile.displayName)
        }
    }

    private func createRemoteInvite(
        target: RemotePlayFlow.InviteTarget,
        whiteChoice: RemotePlayFlow.WhiteChoice
    ) async throws -> RemotePendingInvite {
        let profile = try remoteIdentityStore.loadLocalProfile()
        guard let displayName = profile.displayName else {
            throw RemoteInviteTransportError.notFound
        }

        let now = Date()
        let invite = try await remoteInviteTransport.createInvite(
            CreateRemoteInviteRequest(
                inviter: RemotePlayerRef(id: profile.id, displayName: displayName),
                inviteeDisplayName: remoteInviteeDisplayName(for: target),
                whiteAssignment: remoteWhiteAssignment(from: whiteChoice),
                now: now,
                expiresAt: now.addingTimeInterval(10 * 60)
            )
        )
        try? await remoteInviteTransport.prepareAcceptanceNotification(for: invite)
        return invite
    }

    private func fetchRemoteInvite(
        code: InviteCode,
        token: RemoteInviteToken?
    ) async throws -> RemotePendingInvite {
        try await remoteInviteTransport.fetchInvite(code: code, token: token, now: Date())
    }

    private func fetchAcceptedRemoteInvite(id: RemoteInviteID) async throws -> RemoteAcceptedInvite? {
        try await remoteInviteTransport.acceptedInvite(id: id, now: Date())
    }

    private func fetchAcceptedInviteAfterPush(id: RemoteInviteID) {
        guard case .waitingForInvitee(let pendingInvite) = remotePlayFlow.stage,
              pendingInvite.remoteInviteID == id else {
            return
        }

        Task { @MainActor in
            do {
                guard case .waitingForInvitee(let currentInvite) = remotePlayFlow.stage,
                      currentInvite.remoteInviteID == id,
                      let acceptedInvite = try await fetchAcceptedRemoteInvite(id: id) else {
                    return
                }
                remotePlayFlow.cancel()
                startInviterRemoteGame(acceptedInvite)
            } catch {
                return
            }
        }
    }

    private func remoteInviteeDisplayName(for target: RemotePlayFlow.InviteTarget) -> String? {
        switch target {
        case .known(let player):
            return player.displayName
        case .newPlayer:
            return nil
        }
    }

    private func remoteWhiteAssignment(from choice: RemotePlayFlow.WhiteChoice) -> RemoteInviteWhiteAssignment {
        switch choice {
        case .localPlayer:
            return .inviter
        case .invitee:
            return .invitee
        case .inviteeChooses:
            return .inviteeChooses
        }
    }

    private func copyInviteLink(_ inviteURL: URL) {
        UIPasteboard.general.string = inviteURL.absoluteString
    }

    private func showRemoteStartAnnouncement(_ announcement: RemoteGameStartAnnouncement) {
        pendingRemoteStartAnnouncement = announcement
    }

    private func showRemoteInviteConfirmation(
        _ confirmation: RemoteInviteConfirmation,
        invite: RemotePendingInvite? = nil
    ) {
        pendingRemoteInviteConfirmation = confirmation
        pendingRemoteInviteAcceptance = invite.map(PendingRemoteInviteAcceptance.init(invite:))
    }

    private func dismissRemoteStartAnnouncement() {
        pendingRemoteStartAnnouncement = nil
        syncRemotePresenceForCurrentTurn()
        startRemoteMoveFetchLoopIfNeeded()
    }

    private func selectRemoteInviteColor(_ color: PieceColor) {
        pendingRemoteInviteConfirmation = pendingRemoteInviteConfirmation?.selectColor(color)
    }

    private func cancelRemoteInvite() {
        pendingRemoteInviteConfirmation = nil
        pendingRemoteInviteAcceptance = nil
        remoteInviteAcceptanceTask?.cancel()
        remoteInviteAcceptanceTask = nil
    }

    private func confirmRemoteInvite() {
        guard let localPlayerColor = pendingRemoteInviteConfirmation?.localPlayerColor else {
            return
        }

        if let pendingRemoteInviteAcceptance {
            acceptRemoteInvite(pendingRemoteInviteAcceptance.invite, localPlayerColor: localPlayerColor)
            return
        }

        pendingRemoteInviteConfirmation = nil
        #if DEBUG
        if remotePlayRuntimeMode == .fakeLocal {
            startFakeRemoteJoin(localPlayerColor: localPlayerColor)
        }
        #endif
    }

    private func handleInviteURL(_ url: URL) {
        guard let lookup = RemotePlayFlow.inviteLookup(from: url) else {
            _ = remotePlayFlow.requestJoinInvite(from: url)
            return
        }

        guard let lookupToFetch = remotePlayFlow.requestJoinInviteLookup(lookup) else {
            return
        }

        let request = InviteLinkRequest(
            lookup: lookupToFetch,
            expectedStage: remotePlayFlow.stage,
            expectedJoinCode: remotePlayFlow.joinCode
        )
        activeInviteLinkRequest = request
        inviteLinkFetchTask?.cancel()
        inviteLinkFetchTask = Task { @MainActor in
            defer {
                if activeInviteLinkRequest == request {
                    activeInviteLinkRequest = nil
                    inviteLinkFetchTask = nil
                }
            }

            do {
                let invite = try await remoteInviteTransport.fetchInvite(
                    code: lookupToFetch.code,
                    token: lookupToFetch.token,
                    now: Date()
                )
                guard isCurrentInviteLinkRequest(request) else {
                    return
                }
                remotePlayFlow.cancel()
                showRemoteInviteConfirmation(
                    RemoteInviteConfirmation(
                        opponentName: invite.inviter.displayName,
                        localPlayerColor: invite.whiteAssignment.localPlayerColorForJoiner
                    ),
                    invite: invite
                )
            } catch {
                guard isCurrentInviteLinkRequest(request) else {
                    return
                }
                remotePlayFlow.showJoinInviteLookupError(
                    lookupToFetch,
                    message: "That link did not match an open invite."
                )
            }
        }
    }

    private func isCurrentInviteLinkRequest(_ request: InviteLinkRequest) -> Bool {
        activeInviteLinkRequest == request
            && !Task.isCancelled
            && remotePlayFlow.stage == request.expectedStage
            && remotePlayFlow.joinCode == request.expectedJoinCode
    }

    #if DEBUG
    private func startFakeRemoteJoin(localPlayerColor: PieceColor) {
        fakeRemoteLab.start(session: session, localPlayerColor: localPlayerColor)
        rememberKnownPlayer(KnownRemotePlayer(id: RemotePlayerID(rawValue: "maya"), displayName: "Maya"))
    }

    private var activeFakeRemoteLab: FakeRemoteGameLab? {
        remotePlayRuntimeMode == .fakeLocal ? fakeRemoteLab : nil
    }
    #endif

    private func acceptRemoteInvite(_ invite: RemotePendingInvite, localPlayerColor: PieceColor) {
        remoteInviteAcceptanceTask?.cancel()
        remoteInviteAcceptanceTask = Task { @MainActor in
            do {
                let localPlayer = try localRemotePlayer()
                let acceptedInvite = try await remoteInviteTransport.acceptInvite(
                    JoinRemoteInviteRequest(
                        code: invite.code,
                        token: invite.token,
                        joiner: localPlayer,
                        now: Date()
                    ),
                    chosenColor: localPlayerColor
                )
                pendingRemoteInviteConfirmation = nil
                pendingRemoteInviteAcceptance = nil
                startJoinerRemoteGame(acceptedInvite)
            } catch {
                session.message = "Could not start remote game. Check your connection and try again."
            }
            remoteInviteAcceptanceTask = nil
        }
    }

    private func localRemotePlayer() throws -> RemotePlayerRef {
        let profile = try remoteIdentityStore.loadLocalProfile()
        guard let displayName = profile.displayName else {
            throw RemoteInviteTransportError.notFound
        }
        return RemotePlayerRef(id: profile.id, displayName: displayName)
    }

    private func startJoinerRemoteGame(_ acceptedInvite: RemoteAcceptedInvite) {
        rememberKnownPlayer(
            KnownRemotePlayer(
                id: acceptedInvite.invite.inviter.id,
                displayName: acceptedInvite.invite.inviter.displayName
            )
        )
        showRemoteStartAnnouncement(startRemoteGame(context: .joiner(from: acceptedInvite)))
    }

    private func startInviterRemoteGame(_ acceptedInvite: RemoteAcceptedInvite) {
        rememberKnownPlayer(
            KnownRemotePlayer(
                id: acceptedInvite.joiner.id,
                displayName: acceptedInvite.joiner.displayName
            )
        )
        showRemoteStartAnnouncement(startRemoteGame(context: .inviter(from: acceptedInvite)))
    }

    private func startRemoteGame(context: RemoteGameStartContext) -> RemoteGameStartAnnouncement {
        cancelRemoteGameSync(clearSavedGame: false)
        session.newGame()
        Self.applyRemoteSeats(from: context.descriptor, to: session)
        activeRemoteGameController = RemoteGameSessionController(
            descriptor: context.descriptor,
            transport: remoteGameTransport,
            initialState: .startingPosition()
        )
        persistActiveRemoteGame()
        prepareRemoteMoveNotification(for: context.descriptor)
        prepareRemoteGameStatusNotification(for: context.descriptor.id)
        requestRemoteNotificationAuthorizationIfNeeded()
        remotePlayFlow.cancel()
        return RemoteGameStartAnnouncement(
            opponentName: context.opponent.displayName,
            localPlayerColor: context.localPlayerColor
        )
    }

    private func handleCommittedMove(_ move: Move) {
        stopRemotePresenceHeartbeat()
        remoteOpponentPresence = nil

        #if DEBUG
        if let fakeRemoteLab = activeFakeRemoteLab, fakeRemoteLab.isActive {
            Task { @MainActor in
                try? await fakeRemoteLab.recordCommittedLocalMove(move)
            }
            return
        }
        #endif

        guard let activeRemoteGameController else {
            return
        }

        Task { @MainActor in
            do {
                try activeRemoteGameController.recordCommittedLocalMove(move)
                persistActiveRemoteGame()
                try await activeRemoteGameController.uploadPendingMoves()
                persistActiveRemoteGame()
                syncRemotePresenceForCurrentTurn()
                startRemoteMoveFetchLoopIfNeeded()
            } catch {
                persistActiveRemoteGame()
                session.message = "Could not sync move. Check your connection."
            }
        }
    }

    private func resumeRemoteSyncIfNeeded() {
        guard activeRemoteGameController != nil else {
            return
        }
        if let descriptor = activeRemoteGameController?.snapshot.descriptor {
            prepareRemoteMoveNotification(for: descriptor)
            prepareRemoteGameStatusNotification(for: descriptor.id)
        }

        Task { @MainActor in
            guard let activeRemoteGameController else {
                return
            }
            do {
                try await activeRemoteGameController.uploadPendingMoves()
                persistActiveRemoteGame()
            } catch {
                persistActiveRemoteGame()
                session.message = "Could not sync move. Check your connection."
            }
            await fetchRemoteGameStatusIfNeeded()
            syncRemotePresenceForCurrentTurn()
            startRemoteMoveFetchLoopIfNeeded()
        }
    }

    private func prepareRemoteMoveNotification(for descriptor: RemoteGameDescriptor) {
        guard let notificationPreparing = remoteGameTransport as? any RemoteGameMoveNotificationPreparing else {
            return
        }

        Task {
            try? await notificationPreparing.prepareMoveNotification(for: descriptor)
        }
    }

    private func prepareRemoteGameStatusNotification(for gameID: RemoteGameID) {
        guard let notificationPreparing = remoteGameTransport as? any RemoteGameLifecycleNotificationPreparing else {
            return
        }

        Task {
            try? await notificationPreparing.prepareGameStatusNotification(gameID: gameID)
        }
    }

    private func requestRemoteNotificationAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard RemoteNotificationPermissionPolicy.shouldRequestAuthorization(
                for: settings.authorizationStatus
            ) else {
                return
            }
            _ = try? await center.requestAuthorization(options: [.alert])
        }
    }

    private func fetchRemoteMovesAfterPush(gameID: RemoteGameID) {
        guard activeRemoteGameController?.gameID == gameID else {
            return
        }
        startRemoteMoveFetchLoopIfNeeded()
    }

    private func fetchRemoteGameStatusAfterPush(gameID: RemoteGameID) {
        guard activeRemoteGameController?.gameID == gameID else {
            return
        }
        Task { @MainActor in
            await fetchRemoteGameStatusIfNeeded()
        }
    }

    private func startRemoteMoveFetchLoopIfNeeded() {
        guard activeRemoteGameController != nil,
              !session.localCanActForCurrentTurn else {
            syncRemotePresenceForCurrentTurn()
            return
        }
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let activeRemoteGameController else {
                    remoteMoveFetchTask = nil
                    return
                }
                guard !session.localCanActForCurrentTurn else {
                    syncRemotePresenceForCurrentTurn()
                    remoteMoveFetchTask = nil
                    return
                }

                let didEnd = await fetchRemoteGameStatusIfNeeded()
                if didEnd {
                    remoteMoveFetchTask = nil
                    return
                }

                await fetchRemotePresenceIfNeeded()

                do {
                    let appliedMoves = try await activeRemoteGameController.fetchAndApplyRemoteMoves(to: session)
                    if !appliedMoves.isEmpty {
                        persistActiveRemoteGame()
                        remoteOpponentPresence = nil
                        syncRemotePresenceForCurrentTurn()
                        remoteMoveFetchTask = nil
                        return
                    }
                } catch {
                    if !Task.isCancelled {
                        session.message = "Could not sync remote move. Check your connection."
                    }
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @discardableResult
    private func fetchRemoteGameStatusIfNeeded() async -> Bool {
        guard let activeRemoteGameController,
              let lifecycleTransport = remoteGameTransport as? any RemoteGameLifecycleTransport else {
            return false
        }

        let descriptor = activeRemoteGameController.snapshot.descriptor
        do {
            guard let status = try await lifecycleTransport.fetchGameStatus(gameID: descriptor.id),
                  status.status == .ended,
                  status.updatedByPlayerID != descriptor.localPlayerID else {
                return false
            }
            endRemoteGameAfterOpponentEnded(descriptor: descriptor)
            return true
        } catch {
            return false
        }
    }

    private func publishRemoteGameEndedIfNeeded() {
        guard let activeRemoteGameController,
              let lifecycleTransport = remoteGameTransport as? any RemoteGameLifecycleTransport else {
            return
        }

        let descriptor = activeRemoteGameController.snapshot.descriptor
        Task {
            try? await lifecycleTransport.updateGameStatus(
                RemoteGameStatusUpdate(
                    gameID: descriptor.id,
                    status: .ended,
                    updatedByPlayerID: descriptor.localPlayerID,
                    updatedAt: Date()
                )
            )
        }
    }

    private func endRemoteGameAfterOpponentEnded(descriptor: RemoteGameDescriptor) {
        let opponentName = Self.opponentName(from: descriptor)
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = nil
        stopRemotePresenceHeartbeat()
        remoteOpponentPresence = nil
        activeRemoteGameController = nil
        try? activeRemoteGameStore.clear()
        session.endRemoteGame(message: "\(opponentName) ended this game.")
    }

    private func persistActiveRemoteGame() {
        guard let activeRemoteGameController else {
            return
        }
        try? activeRemoteGameStore.save(activeRemoteGameController.snapshot)
    }

    private func cancelRemoteGameSync(clearSavedGame: Bool) {
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = nil
        stopRemotePresenceHeartbeat()
        remoteOpponentPresence = nil
        activeRemoteGameController = nil
        if clearSavedGame {
            try? activeRemoteGameStore.clear()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active, .inactive:
            syncRemotePresenceForCurrentTurn()
        case .background:
            publishLocalRemotePresence(.away, expiresAfter: RemotePresencePolicy.awayExpiresAfter)
            stopRemotePresenceHeartbeat()
        @unknown default:
            break
        }
    }

    private func reportLocalBoardInteraction() {
        guard activeRemoteGameController != nil,
              session.localCanActForCurrentTurn else {
            return
        }

        let now = Date()
        if RemotePresencePolicy.shouldPublishActiveMoving(
            lastPublishedAt: lastRemoteActivePresencePublishedAt,
            now: now
        ) {
            publishLocalRemotePresence(
                .activeMoving,
                updatedAt: now,
                expiresAfter: RemotePresencePolicy.activeMovingExpiresAfter
            )
            lastRemoteActivePresencePublishedAt = now
            remotePresenceHeartbeatTask?.cancel()
            remotePresenceHeartbeatTask = nil
        }

        remoteActiveMovingResetTask?.cancel()
        remoteActiveMovingResetTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(RemotePresencePolicy.activeMovingResetDelay * 1_000_000_000)
            )
            guard !Task.isCancelled else {
                return
            }
            lastRemoteActivePresencePublishedAt = nil
            publishLocalRemotePresence(
                .foregroundIdle,
                expiresAfter: RemotePresencePolicy.foregroundIdleExpiresAfter
            )
            startRemotePresenceHeartbeatIfNeeded()
        }
    }

    private func syncRemotePresenceForCurrentTurn() {
        guard activeRemoteGameController != nil else {
            stopRemotePresenceHeartbeat()
            return
        }

        if session.localCanActForCurrentTurn {
            startRemotePresenceHeartbeatIfNeeded()
        } else {
            stopRemotePresenceHeartbeat()
        }
    }

    private func startRemotePresenceHeartbeatIfNeeded() {
        guard activeRemoteGameController != nil,
              session.localCanActForCurrentTurn,
              scenePhase != .background else {
            stopRemotePresenceHeartbeat()
            return
        }

        guard remotePresenceHeartbeatTask == nil else {
            return
        }

        publishLocalRemotePresence(.foregroundIdle, expiresAfter: RemotePresencePolicy.foregroundIdleExpiresAfter)
        remotePresenceHeartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(RemotePresencePolicy.foregroundIdleHeartbeatInterval * 1_000_000_000)
                )
                guard !Task.isCancelled,
                      activeRemoteGameController != nil,
                      session.localCanActForCurrentTurn,
                      scenePhase != .background else {
                    remotePresenceHeartbeatTask = nil
                    return
                }
                publishLocalRemotePresence(
                    .foregroundIdle,
                    expiresAfter: RemotePresencePolicy.foregroundIdleExpiresAfter
                )
            }
        }
    }

    private func stopRemotePresenceHeartbeat() {
        remotePresenceHeartbeatTask?.cancel()
        remotePresenceHeartbeatTask = nil
        remoteActiveMovingResetTask?.cancel()
        remoteActiveMovingResetTask = nil
        lastRemoteActivePresencePublishedAt = nil
    }

    private func publishLocalRemotePresence(
        _ state: RemotePresenceState,
        updatedAt: Date = Date(),
        expiresAfter timeInterval: TimeInterval
    ) {
        guard let descriptor = activeRemoteGameController?.snapshot.descriptor,
              let presenceTransport = remoteGameTransport as? any RemotePresenceTransport else {
            return
        }

        let presence = RemotePresenceUpdate(
            gameID: descriptor.id,
            playerID: descriptor.localPlayerID,
            state: state,
            updatedAt: updatedAt,
            expiresAt: updatedAt.addingTimeInterval(timeInterval)
        )

        Task {
            try? await presenceTransport.updatePresence(presence)
        }
    }

    private func fetchRemotePresenceIfNeeded() async {
        guard let descriptor = activeRemoteGameController?.snapshot.descriptor,
              let remoteTurnPlayer = remoteTurnPlayer(from: descriptor),
              let presenceTransport = remoteGameTransport as? any RemotePresenceTransport else {
            remoteOpponentPresence = nil
            return
        }

        do {
            remoteOpponentPresence = try await presenceTransport.fetchPresence(
                gameID: descriptor.id,
                playerID: remoteTurnPlayer.id
            )
        } catch {
            remoteOpponentPresence = nil
        }
    }

    private func remoteTurnPlayer(from descriptor: RemoteGameDescriptor) -> RemotePlayerRef? {
        let player: RemotePlayerRef
        switch session.state.sideToMove {
        case .white:
            player = descriptor.whitePlayer
        case .black:
            player = descriptor.blackPlayer
        }
        guard player.id != descriptor.localPlayerID else {
            return nil
        }
        return player
    }

    private static func applyRemoteSeats(from descriptor: RemoteGameDescriptor, to session: GameSession) {
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            session.whitePlayer = .humanLocal
            session.blackPlayer = .remote(playerID: descriptor.blackPlayer.id.rawValue)
        } else {
            session.whitePlayer = .remote(playerID: descriptor.whitePlayer.id.rawValue)
            session.blackPlayer = .humanLocal
        }
    }

    private static func restoredSession(from snapshot: ActiveRemoteGameSnapshot) throws -> GameSession {
        let projectedState = try RemoteGameSessionController.projectedState(from: snapshot)
        let moves = try snapshot.acceptedEvents
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .map { try RemoteMoveCodec.decode($0.move) }
        let session = GameSession(replayingCommittedMoves: moves)
        guard session.state == projectedState else {
            throw RemoteGameSessionController.Error.invalidSnapshot
        }
        return session
    }

    private static func opponentName(from descriptor: RemoteGameDescriptor) -> String {
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            return descriptor.blackPlayer.displayName
        }
        return descriptor.whitePlayer.displayName
    }

    private static func remoteInviteTransport(for mode: RemotePlayRuntimeMode) -> any RemoteInviteTransport {
        switch mode {
        case .fakeLocal:
            return InMemoryRemoteInviteTransport()
        case .cloudKit:
            return CloudKitRemoteInviteTransport()
        }
    }

    private static func remoteGameTransport(for mode: RemotePlayRuntimeMode) -> any RemoteGameTransport {
        switch mode {
        case .fakeLocal:
            return InMemoryRemoteGameTransport()
        case .cloudKit:
            return CloudKitRemoteGameTransport()
        }
    }

    private func syncToCurrentInterfaceOrientation(animated: Bool) {
        applyViewingAngle(Self.currentViewingAngle(), animated: animated)
    }

    private func applyViewingAngle(_ nextAngle: BoardViewingAngle, animated: Bool) {
        let nextTableRotationDegrees = nextAngle.tableRotationDegrees(closestTo: tableRotationDegrees)
        let update = {
            viewingAngle = nextAngle
            tableRotationDegrees = nextTableRotationDegrees
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                update()
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                update()
            }
        }
    }

    private static func currentViewingAngle() -> BoardViewingAngle {
        resolvedInitialViewingAngle(
            deviceOrientation: UIDevice.current.orientation,
            interfaceOrientation: UIApplication.shared.activeInterfaceOrientation
        )
    }

    static func resolvedInitialViewingAngle(
        deviceOrientation: UIDeviceOrientation,
        interfaceOrientation: UIInterfaceOrientation?
    ) -> BoardViewingAngle {
        if deviceOrientation.isValidBoardViewingOrientation {
            return BoardViewingAngle(deviceOrientation: deviceOrientation, baseline: .landscapeLeft)
        }

        if let interfaceOrientation, interfaceOrientation.isValidBoardViewingOrientation {
            return BoardViewingAngle(interfaceOrientation: interfaceOrientation, baseline: .landscapeLeft)
        }

        return .normal
    }

    private var readableRotationDegrees: Double {
        -tableRotationDegrees
    }

    private var remotePlaySheetBinding: Binding<Bool> {
        Binding {
            remotePlayFlow.stage != .closed
        } set: { isPresented in
            if !isPresented {
                cancelInviteLinkFetch()
                remotePlayFlow.cancel()
            }
        }
    }

    private func cancelInviteLinkFetch() {
        activeInviteLinkRequest = nil
        inviteLinkFetchTask?.cancel()
        inviteLinkFetchTask = nil
    }
}

struct PlaySurfaceLayout: Equatable {
    static let maximumBoardSide: CGFloat = 760
    static let sidePanelWidth: CGFloat = 260
    static let boardPanelSpacing: CGFloat = 28
    static let horizontalPadding: CGFloat = 30
    static let verticalPadding: CGFloat = 24

    let tabletopSize: CGSize
    let boardSide: CGFloat

    var sidePanelHeight: CGFloat {
        boardSide
    }

    var contentSize: CGSize {
        CGSize(
            width: boardSide + Self.boardPanelSpacing + Self.sidePanelWidth,
            height: boardSide
        )
    }

    static func make(for viewportSize: CGSize) -> PlaySurfaceLayout {
        let tabletopSize = CGSize(
            width: max(viewportSize.width, viewportSize.height),
            height: min(viewportSize.width, viewportSize.height)
        )
        let availableHeight = max(1, tabletopSize.height - verticalPadding * 2)
        let availableWidth = max(
            1,
            tabletopSize.width - horizontalPadding * 2 - sidePanelWidth - boardPanelSpacing
        )
        let boardSide = min(maximumBoardSide, availableWidth, availableHeight)

        return PlaySurfaceLayout(tabletopSize: tabletopSize, boardSide: boardSide)
    }
}

private extension UIApplication {
    var activeInterfaceOrientation: UIInterfaceOrientation? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
            }?
            .interfaceOrientation
    }
}

private extension UIInterfaceOrientation {
    var deviceOrientation: UIDeviceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .unknown
        }
    }
}

private struct PendingPromotion: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
    let color: PieceColor
    #if DEBUG
    let testingSquare: Square?
    #endif

    init(from: Square, to: Square, color: PieceColor) {
        self.from = from
        self.to = to
        self.color = color
        #if DEBUG
        self.testingSquare = nil
        #endif
    }

    #if DEBUG
    init(testingSquare: Square, color: PieceColor) {
        self.from = testingSquare
        self.to = testingSquare
        self.color = color
        self.testingSquare = testingSquare
    }
    #endif
}

private struct InviteLinkRequest: Equatable {
    let id = UUID()
    let lookup: RemotePlayFlow.InviteLookup
    let expectedStage: RemotePlayFlow.Stage
    let expectedJoinCode: String
}

private struct PendingRemoteInviteAcceptance: Equatable {
    let invite: RemotePendingInvite
}

private struct PromotionPickerView: View {
    let color: PieceColor
    let promote: (Piece.Kind) -> Void

    private let choices: [Piece.Kind] = [.queen, .rook, .bishop, .knight]
    private let columns = [
        GridItem(.flexible(minimum: 132), spacing: 12),
        GridItem(.flexible(minimum: 132), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose promotion")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Pick the piece your pawn becomes.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(choices, id: \.self) { kind in
                    Button {
                        promote(kind)
                    } label: {
                        PromotionChoiceLabel(kind: kind, color: color)
                    }
                    .buttonStyle(PromotionChoiceButtonStyle())
                    .accessibilityLabel("Promote to \(kind.rawValue)")
                    .accessibilityIdentifier("promotion-\(kind.rawValue)-button")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .presentationBackground(AppTheme.table)
    }
}

private struct PromotionChoiceLabel: View {
    let kind: Piece.Kind
    let color: PieceColor

    var body: some View {
        HStack(spacing: 14) {
            PieceIconView(piece: Piece(kind: kind, color: color))
                .frame(width: 56, height: 56)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.lightSquare.opacity(0.72))
                )

            Text(kind.rawValue.capitalized)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PromotionChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SwiftUI.Color.white.opacity(configuration.isPressed ? 0.72 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.boardFrame.opacity(configuration.isPressed ? 0.42 : 0.24), lineWidth: 1)
            )
            .shadow(color: SwiftUI.Color.black.opacity(configuration.isPressed ? 0.06 : 0.12), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
