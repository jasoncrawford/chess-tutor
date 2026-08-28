import SwiftUI
import UIKit
import UserNotifications

private enum RemoteSyncMessage {
    static let uploadFailed = "Could not sync move. Check your connection."
    static let fetchFailed = "Could not sync remote move. Check your connection."
}

struct ContentView: View {
    @State private var session = GameSession()
    @State private var gameLibrary: GameLibrary
    @State private var pendingPromotion: PendingPromotion?
    @State private var isShowingAbout = false
    @State private var isShowingGameTypeChooser = false
    @State private var remotePlayFlow: RemotePlayFlow
    @State private var remoteLifecycle: RemoteGameLifecycleController
    @State private var remoteInviteAcceptanceTask: Task<Void, Never>?
    @State private var incomingRemoteInvitePollTask: Task<Void, Never>?
    @State private var remoteMoveFetchTask: Task<Void, Never>?
    @State private var remoteMoveUploadRetryTask: Task<Void, Never>?
    @State private var remotePresenceHeartbeatTask: Task<Void, Never>?
    @State private var remoteActiveMovingResetTask: Task<Void, Never>?
    @State private var lastRemoteActivePresencePublishedAt: Date?
    @State private var activeInviteLinkRequest: InviteLinkRequest?
    @State private var inviteLinkFetchTask: Task<Void, Never>?
    @State private var dismissedIncomingRemoteInviteIDs: Set<RemoteInviteID> = []
    @State private var pendingOutboundAcceptanceFetchIDs: Set<RemoteInviteID> = []
    @State private var foregroundIncomingInvite: ManagedPendingRemoteBoard?
    @State private var outboundInvitationNotice: ManagedPendingRemoteBoard?
    @State private var didLogAppLaunch = false
    @State private var baselineOrientation = UIInterfaceOrientation.landscapeLeft
    @State private var viewingAngle: BoardViewingAngle
    @State private var tableRotationDegrees: Double
    @Environment(\.scenePhase) private var scenePhase
    private let remoteIdentityStore: RemoteIdentityStore
    private let activeRemoteGameStore: ActiveRemoteGameStore
    private let gameLibraryStore: GameLibraryStore
    private let remoteInviteTransport: any RemoteInviteTransport
    private let remoteGameTransport: any RemoteGameTransport
    private let remotePlayRuntimeMode: RemotePlayRuntimeMode
    private let diagnosticsLog: DiagnosticsLog
    #if DEBUG
    @State private var isCaptureTestModeEnabled = false
    @State private var fakeRemoteLab = FakeRemoteGameLab()
    #endif
    @Namespace private var captureNamespace

    init() {
        let gameLibraryStore = GameLibraryStore()
        self.gameLibraryStore = gameLibraryStore
        let gameLibrary = GameLibrary(
            snapshot: (try? gameLibraryStore.load())
                ?? GameLibrarySnapshot(games: [], route: .games)
        )
        _gameLibrary = State(initialValue: gameLibrary)
        let remoteIdentityStore = RemoteIdentityStore()
        self.remoteIdentityStore = remoteIdentityStore
        let activeRemoteGameStore = ActiveRemoteGameStore()
        self.activeRemoteGameStore = activeRemoteGameStore
        let runtimeMode = RemotePlayRuntimeMode.resolve()
        self.remotePlayRuntimeMode = runtimeMode
        self.diagnosticsLog = .shared
        self.remoteInviteTransport = Self.remoteInviteTransport(for: runtimeMode, diagnosticsLog: diagnosticsLog)
        self.remoteGameTransport = Self.remoteGameTransport(for: runtimeMode, diagnosticsLog: diagnosticsLog)
        let localProfile = try? remoteIdentityStore.loadLocalProfile()
        let remotePlayFlow = RemotePlayFlow(
            knownPlayers: (try? remoteIdentityStore.loadKnownPlayers()) ?? [],
            localDisplayName: localProfile?.displayName
        )
        _remotePlayFlow = State(initialValue: remotePlayFlow)

        let initialViewingAngle = Self.currentViewingAngle()
        _viewingAngle = State(initialValue: initialViewingAngle)
        _tableRotationDegrees = State(initialValue: initialViewingAngle.tableRotationDegrees)

        let initialSession: GameSession
        let initialActiveRemoteGameController: RemoteGameSessionController?
        if case let .board(id) = gameLibrary.route,
           let savedGame = gameLibrary.game(id: id) {
            initialSession = GameSession(replayingCommittedMoves: savedGame.moves)
            initialActiveRemoteGameController = nil
        } else if case let .board(id) = gameLibrary.route,
                  let savedGame = gameLibrary.remoteGame(id: id),
                  let restoredSession = try? Self.restoredSession(from: savedGame.snapshot),
                  let restoredController = try? RemoteGameSessionController(
                    snapshot: savedGame.snapshot,
                    transport: self.remoteGameTransport
                  ) {
            RemoteGameLifecycleController.applyRemoteSeats(from: savedGame.snapshot.descriptor, to: restoredSession)
            initialSession = restoredSession
            initialActiveRemoteGameController = restoredController
        } else if case let .board(id) = gameLibrary.route,
                  gameLibrary.pendingRemoteBoard(id: id) != nil {
            initialSession = GameSession()
            initialSession.lockBoard(message: "Waiting for this invitation to be accepted.", statusText: "Invitation pending")
            initialActiveRemoteGameController = nil
        } else {
            if (try? activeRemoteGameStore.load()) != nil {
                try? activeRemoteGameStore.clear()
            }
            initialSession = GameSession()
            initialActiveRemoteGameController = nil
        }
        _session = State(initialValue: initialSession)
        _remoteLifecycle = State(
            initialValue: RemoteGameLifecycleController(
                session: initialSession,
                remotePlayFlow: remotePlayFlow,
                remoteGameTransport: self.remoteGameTransport,
                activeRemoteGameController: initialActiveRemoteGameController
            )
        )
    }

    var body: some View {
        Group {
            if case .games = gameLibrary.route {
                GamesRackView(
                    entries: gameLibrary.entries,
                    onStartGame: startNewGame,
                    onOpenEntry: openGameEntry
                )
            } else {
        GeometryReader { proxy in
            let layout = PlaySurfaceLayout.make(for: proxy.size)

            ZStack {
                AppTheme.table.ignoresSafeArea()
                tabletop(boardSide: layout.boardSide)
                    .frame(width: layout.tabletopSize.width, height: layout.tabletopSize.height)
                    .rotationEffect(.degrees(tableRotationDegrees))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let pendingRemoteStartAnnouncement = remoteLifecycle.pendingRemoteStartAnnouncement {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    RemoteGameStartAnnouncementView(
                        announcement: pendingRemoteStartAnnouncement,
                        onStart: dismissRemoteStartAnnouncement
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if let pendingRemoteInviteConfirmation = remoteLifecycle.pendingRemoteInviteConfirmation {
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
            .animation(.easeInOut(duration: 0.18), value: remoteLifecycle.pendingRemoteStartAnnouncement)
            .animation(.easeInOut(duration: 0.18), value: remoteLifecycle.pendingRemoteInviteConfirmation)
        }
            }
        }
        .overlay {
            if let invite = foregroundIncomingInvite {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                IncomingInviteNoticeView(
                    inviterName: invite.invite.inviter.displayName,
                    onView: {
                        foregroundIncomingInvite = nil
                        openPendingRemoteBoard(invite)
                    },
                    onLater: {
                        foregroundIncomingInvite = nil
                    }
                )
            } else if let invitation = outboundInvitationNotice {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                InvitationSentNoticeView(
                    onKeepLooking: { outboundInvitationNotice = nil },
                    onCancel: {
                        outboundInvitationNotice = nil
                        cancelRemoteInviteRecord(id: invitation.invite.id)
                    }
                )
            }
        }
        .onAppear {
            syncToCurrentInterfaceOrientation(animated: false)
            DispatchQueue.main.async {
                syncToCurrentInterfaceOrientation(animated: false)
            }
            logAppLaunchIfNeeded()
            resumeRemoteSyncIfNeeded()
            prepareIncomingRemoteInviteNotificationIfPossible()
            startIncomingRemoteInvitePollLoopIfNeeded()
            replayBufferedRemotePushNotifications()
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
        .onReceive(NotificationCenter.default.publisher(for: .remotePendingInvitesMayHaveChanged)) { notification in
            guard let rawPlayerID = notification.userInfo?[RemotePendingInvitePushUserInfoKey.playerID] as? String,
                  (try? remoteIdentityStore.loadLocalProfile().id.rawValue) == rawPlayerID else {
                return
            }
            Task { @MainActor in
                await fetchIncomingRemoteInviteIfNeeded()
            }
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
            AboutSheetView(diagnosticsLog: diagnosticsLog)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingGameTypeChooser) {
            StartGameTypeChooserView(
                onStartLocal: {
                    isShowingGameTypeChooser = false
                    startLocalGame()
                },
                onStartRemote: {
                    isShowingGameTypeChooser = false
                    remotePlayFlow.open()
                }
            )
            .presentationDetents([.height(350)])
            .presentationDragIndicator(.visible)
            .presentationBackground(AppTheme.table)
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
                onPendingRemoteInviteCancelled: cancelPendingOutboundInvite,
                onCreatedRemoteInviteAbandoned: cancelCreatedRemoteInvite,
                onCreateRemoteInvite: createRemoteInvite,
                onFetchRemoteInvite: fetchRemoteInvite,
                onFetchAcceptedRemoteInvite: fetchAcceptedRemoteInvite,
                onRemoteInviteAccepted: startInviterRemoteGame,
                onRemoteInviteCreated: { _ in true }
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
                onPendingRemoteInviteCancelled: cancelPendingOutboundInvite,
                onCreatedRemoteInviteAbandoned: cancelCreatedRemoteInvite,
                onCreateRemoteInvite: createRemoteInvite,
                onFetchRemoteInvite: fetchRemoteInvite,
                onFetchAcceptedRemoteInvite: fetchAcceptedRemoteInvite,
                onRemoteInviteAccepted: startInviterRemoteGame,
                onRemoteInviteCreated: { _ in true }
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
            onGames: showGames,
            isInvitationPending: isViewingPendingRemoteBoard,
            remoteNewGameOpponentName: remoteLifecycle.activeRemoteGameOpponent?.displayName,
            remotePresence: remoteLifecycle.remoteOpponentPresence,
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
            onGames: showGames,
            isInvitationPending: isViewingPendingRemoteBoard,
            remoteNewGameOpponentName: remoteLifecycle.activeRemoteGameOpponent?.displayName,
            remotePresence: remoteLifecycle.remoteOpponentPresence,
            onInviteRemoteNewGame: inviteActiveRemoteOpponentAgain,
            onCommittedMove: handleCommittedMove
        )
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: sideLength, alignment: .top)
        #endif
    }

    private func startNewGame() {
        isShowingGameTypeChooser = true
    }

    private var isViewingPendingRemoteBoard: Bool {
        guard case let .board(id) = gameLibrary.route else {
            return false
        }
        return gameLibrary.pendingRemoteBoard(id: id) != nil
    }

    private func startLocalGame() {
        cancelRemoteGameSync(clearSavedGame: true)
        let game = gameLibrary.createLocalGame()
        session = GameSession()
        gameLibrary.showBoard(game.id)
        remoteLifecycle = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: remotePlayFlow,
            remoteGameTransport: remoteGameTransport
        )
        persistGameLibrary()
    }

    private func openLocalGame(_ game: ManagedLocalGame) {
        cancelRemoteGameSync(clearSavedGame: true)
        session = GameSession(replayingCommittedMoves: game.moves)
        gameLibrary.showBoard(game.id)
        remoteLifecycle = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: remotePlayFlow,
            remoteGameTransport: remoteGameTransport
        )
        persistGameLibrary()
    }

    private func openGameEntry(_ entry: GameLibraryEntry) {
        switch entry {
        case .local(let game):
            openLocalGame(game)
        case .pendingRemote(let board):
            openPendingRemoteBoard(board)
        case .remote(let game):
            openRemoteGame(game)
        }
    }

    private func openPendingRemoteBoard(_ board: ManagedPendingRemoteBoard) {
        cancelRemoteGameSync(clearSavedGame: false)
        session = GameSession()
        session.lockBoard(message: "Waiting for this invitation to be accepted.", statusText: "Invitation pending")
        gameLibrary.showBoard(board.id)
        remoteLifecycle = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: remotePlayFlow,
            remoteGameTransport: remoteGameTransport
        )
        if board.role == .invitee {
            showRemoteInviteConfirmation(
                RemoteInviteConfirmation(
                    opponentName: board.invite.inviter.displayName,
                    localPlayerColor: board.invite.whiteAssignment.localPlayerColorForJoiner
                ),
                invite: board.invite
            )
        }
        persistGameLibrary()
    }

    private func openRemoteGame(_ game: ManagedRemoteGame) {
        guard let restoredSession = try? Self.restoredSession(from: game.snapshot),
              let controller = try? RemoteGameSessionController(snapshot: game.snapshot, transport: remoteGameTransport) else {
            return
        }
        cancelRemoteGameSync(clearSavedGame: false)
        RemoteGameLifecycleController.applyRemoteSeats(from: game.snapshot.descriptor, to: restoredSession)
        session = restoredSession
        gameLibrary.showBoard(game.id)
        remoteLifecycle = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: remotePlayFlow,
            remoteGameTransport: remoteGameTransport,
            activeRemoteGameController: controller
        )
        persistGameLibrary()
        resumeRemoteSyncIfNeeded()
    }

    private func persistGameLibrary() {
        try? gameLibraryStore.save(gameLibrary.snapshot)
    }

    private func showGames() {
        gameLibrary.showGames()
        persistGameLibrary()
    }

    private func inviteActiveRemoteOpponentAgain() {
        remoteLifecycle.inviteActiveRemoteOpponentAgain()
    }

    private func rememberKnownPlayer(_ player: KnownRemotePlayer) {
        try? remoteIdentityStore.saveKnownPlayer(player)
        remotePlayFlow.rememberKnownPlayer(player)
    }

    private func saveLocalDisplayName(_ displayName: String) {
        if let profile = try? remoteIdentityStore.saveLocalDisplayName(displayName) {
            remotePlayFlow.updateLocalDisplayName(profile.displayName)
            prepareIncomingRemoteInviteNotification(for: profile.id)
            requestRemoteNotificationAuthorizationIfNeeded()
        }
    }

    private func logAppLaunchIfNeeded() {
        guard !didLogAppLaunch else {
            return
        }
        didLogAppLaunch = true
        Task { @MainActor in
            let installationID = await diagnosticsLog.installationID()
            let device = DiagnosticsDeviceSnapshot.current(installationID: installationID)
            let localProfile = try? remoteIdentityStore.loadLocalProfile()
            await diagnosticsLog.logAppLaunch(
                runtimeMode: remotePlayRuntimeMode,
                device: device,
                localPlayerID: localProfile?.id
            )
        }
    }

    private func logDiagnostics(
        category: String,
        _ name: String,
        fields: [String: String] = [:]
    ) {
        Task {
            await diagnosticsLog.append(category: category, name, fields: fields)
        }
    }

    private func diagnosticsTargetName(_ target: RemotePlayFlow.InviteTarget) -> String {
        switch target {
        case .known(let player):
            return "known:\(player.id.rawValue)"
        case .newPlayer:
            return "newPlayer"
        }
    }

    private func diagnosticsMoveFields(_ move: Move) -> [String: String] {
        [
            "from": diagnosticsSquareName(move.from),
            "to": diagnosticsSquareName(move.to),
            "special": diagnosticsSpecialName(move.special)
        ]
    }

    private func diagnosticsSquareName(_ square: Square) -> String {
        "\(square.file)\(square.rank)"
    }

    private func diagnosticsSpecialName(_ special: Move.Special?) -> String {
        guard let special else {
            return "none"
        }
        return "\(special)"
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
        logDiagnostics(
            category: "remoteInvite",
            "createStarted",
            fields: [
                "target": diagnosticsTargetName(target),
                "whiteChoice": "\(whiteChoice)",
                "localPlayerID": profile.id.rawValue,
                "inviteePlayerID": remoteInviteePlayerID(for: target)?.rawValue ?? "none"
            ]
        )
        let notificationBody = remoteInviteNotificationBody(inviterDisplayName: displayName, target: target)
        let invite = try await remoteInviteTransport.createInvite(
            CreateRemoteInviteRequest(
                inviter: RemotePlayerRef(id: profile.id, displayName: displayName),
                inviteePlayerID: remoteInviteePlayerID(for: target),
                inviteeDisplayName: remoteInviteeDisplayName(for: target),
                whiteAssignment: remoteWhiteAssignment(from: whiteChoice),
                notificationBody: notificationBody,
                now: now,
                expiresAt: now.addingTimeInterval(10 * 60)
            )
        )
        try? await remoteInviteTransport.prepareAcceptanceNotification(for: invite)
        let board = gameLibrary.createPendingRemoteBoard(invite, role: .inviter)
        outboundInvitationNotice = board
        gameLibrary.showBoard(board.id)
        session = GameSession()
        session.lockBoard(message: "Waiting for someone to join this game.", statusText: "Invitation sent")
        remoteLifecycle = RemoteGameLifecycleController(
            session: session,
            remotePlayFlow: remotePlayFlow,
            remoteGameTransport: remoteGameTransport
        )
        persistGameLibrary()
        logDiagnostics(
            category: "remoteInvite",
            "createReadyToShare",
            fields: [
                "inviteID": invite.id.rawValue,
                "code": invite.code.rawValue,
                "tokenSuffix": DiagnosticsLog.tokenSuffix(invite.token),
                "whiteAssignment": invite.whiteAssignment.rawValue,
                "inviteePlayerID": invite.inviteePlayerID?.rawValue ?? "none",
                "notificationBody": notificationBody
            ]
        )
        return invite
    }

    private func fetchRemoteInvite(
        code: InviteCode,
        token: RemoteInviteToken?
    ) async throws -> RemotePendingInvite {
        logDiagnostics(
            category: "remoteInvite",
            "fetchStarted",
            fields: [
                "code": code.rawValue,
                "tokenSuffix": DiagnosticsLog.tokenSuffix(token),
                "source": token == nil ? "code" : "link"
            ]
        )
        do {
            let invite = try await remoteInviteTransport.fetchInvite(code: code, token: token, now: Date())
            logDiagnostics(
                category: "remoteInvite",
                "fetchSucceeded",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "code": invite.code.rawValue,
                    "status": invite.status.rawValue,
                    "whiteAssignment": invite.whiteAssignment.rawValue,
                    "inviterID": invite.inviter.id.rawValue
                ]
            )
            return invite
        } catch {
            logDiagnostics(
                category: "remoteInvite",
                "fetchFailed",
                fields: [
                    "code": code.rawValue,
                    "tokenSuffix": DiagnosticsLog.tokenSuffix(token),
                    "source": token == nil ? "code" : "link",
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
    }

    private func fetchAcceptedRemoteInvite(id: RemoteInviteID) async throws -> RemoteAcceptedInvite? {
        do {
            let acceptedInvite = try await remoteInviteTransport.acceptedInvite(id: id, now: Date())
            logDiagnostics(
                category: "remoteInvite",
                acceptedInvite == nil ? "acceptancePollNoChange" : "acceptancePollSucceeded",
                fields: ["inviteID": id.rawValue]
            )
            return acceptedInvite
        } catch {
            logDiagnostics(
                category: "remoteInvite",
                "acceptancePollFailed",
                fields: [
                    "inviteID": id.rawValue,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
            throw error
        }
    }

    private func fetchAcceptedInviteAfterPush(id: RemoteInviteID) {
        logDiagnostics(category: "remoteInvite", "acceptancePushReceived", fields: ["inviteID": id.rawValue])
        guard let pendingBoard = gameLibrary.pendingRemoteBoard(inviteID: id),
              pendingBoard.role == .inviter else {
            logDiagnostics(category: "remoteInvite", "acceptancePushIgnored", fields: ["inviteID": id.rawValue])
            return
        }
        guard pendingOutboundAcceptanceFetchIDs.insert(id).inserted else {
            return
        }

        Task { @MainActor in
            defer { pendingOutboundAcceptanceFetchIDs.remove(id) }
            do {
                guard let acceptedInvite = try await fetchAcceptedRemoteInvite(id: id) else {
                    return
                }
                remotePlayFlow.cancel()
                if gameLibrary.route == .board(pendingBoard.id) {
                    startInviterRemoteGame(acceptedInvite)
                } else {
                    storeAcceptedRemoteGame(acceptedInvite, role: .inviter)
                }
            } catch {
                if let terminalMessage = outboundTerminalInviteMessage(from: error) {
                    remotePlayFlow.showTerminalInviteMessage(terminalMessage)
                }
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

    private func remoteInviteePlayerID(for target: RemotePlayFlow.InviteTarget) -> RemotePlayerID? {
        switch target {
        case .known(let player):
            return player.id
        case .newPlayer:
            return nil
        }
    }

    private func remoteInviteNotificationBody(
        inviterDisplayName: String,
        target: RemotePlayFlow.InviteTarget
    ) -> String {
        if case .known(let player) = target,
           remoteLifecycle.activeRemoteGameOpponent?.id == player.id {
            return "\(inviterDisplayName) wants to start a new game."
        }
        return "\(inviterDisplayName) wants to play."
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
        remoteLifecycle.pendingRemoteStartAnnouncement = announcement
    }

    private func showRemoteInviteConfirmation(
        _ confirmation: RemoteInviteConfirmation,
        invite: RemotePendingInvite? = nil
    ) {
        logDiagnostics(
            category: "remoteInvite",
            "confirmationShown",
            fields: [
                "opponentName": confirmation.opponentName,
                "inviteID": invite?.id.rawValue ?? "none",
                "localPlayerColor": confirmation.localPlayerColor?.rawValue ?? "choiceRequired",
                "purpose": confirmation.purpose.rawValue
            ]
        )
        remoteLifecycle.showRemoteInviteConfirmation(confirmation, invite: invite)
    }

    private func dismissRemoteStartAnnouncement() {
        remoteLifecycle.dismissRemoteStartAnnouncement()
        syncRemotePresenceForCurrentTurn()
        startRemoteMoveFetchLoopIfNeeded()
    }

    private func selectRemoteInviteColor(_ color: PieceColor) {
        remoteLifecycle.selectRemoteInviteColor(color)
    }

    private func cancelRemoteInvite() {
        let inviteToDecline = remoteLifecycle.pendingRemoteInviteAcceptance
        if let inviteToDecline {
            dismissedIncomingRemoteInviteIDs.insert(inviteToDecline.id)
            gameLibrary.removePendingRemoteBoard(inviteID: inviteToDecline.id)
            persistGameLibrary()
        }
        remoteLifecycle.cancelRemoteInviteConfirmation()
        remoteInviteAcceptanceTask?.cancel()
        remoteInviteAcceptanceTask = nil
        guard let inviteToDecline else {
            startIncomingRemoteInvitePollLoopIfNeeded()
            return
        }

        Task { @MainActor in
            do {
                try await remoteInviteTransport.declineInvite(id: inviteToDecline.id)
                logDiagnostics(
                    category: "remoteInvite",
                    "declineSucceeded",
                    fields: ["inviteID": inviteToDecline.id.rawValue]
                )
            } catch {
                logDiagnostics(
                    category: "remoteInvite",
                    "declineFailed",
                    fields: [
                        "inviteID": inviteToDecline.id.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
            }
            startIncomingRemoteInvitePollLoopIfNeeded()
        }
    }

    private func confirmRemoteInvite() {
        guard let localPlayerColor = remoteLifecycle.pendingRemoteInviteConfirmation?.localPlayerColor else {
            return
        }

        if let pendingRemoteInviteAcceptance = remoteLifecycle.pendingRemoteInviteAcceptance {
            acceptRemoteInvite(pendingRemoteInviteAcceptance, localPlayerColor: localPlayerColor)
            return
        }

        remoteLifecycle.cancelRemoteInviteConfirmation()
        #if DEBUG
        if remotePlayRuntimeMode == .fakeLocal {
            startFakeRemoteJoin(localPlayerColor: localPlayerColor)
        }
        #endif
    }

    private func handleInviteURL(_ url: URL) {
        guard let lookup = RemotePlayFlow.inviteLookup(from: url) else {
            logDiagnostics(category: "remoteInvite", "linkRejected", fields: ["urlHost": url.host ?? "none"])
            _ = remotePlayFlow.requestJoinInvite(from: url)
            return
        }
        logDiagnostics(
            category: "remoteInvite",
            "linkOpened",
            fields: [
                "code": lookup.code.rawValue,
                "tokenSuffix": DiagnosticsLog.tokenSuffix(lookup.token)
            ]
        )

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
                let board = gameLibrary.createPendingRemoteBoard(invite)
                persistGameLibrary()
                openPendingRemoteBoard(board)
            } catch {
                guard isCurrentInviteLinkRequest(request) else {
                    return
                }
                logDiagnostics(
                    category: "remoteInvite",
                    "linkFetchFailed",
                    fields: [
                        "code": lookupToFetch.code.rawValue,
                        "tokenSuffix": DiagnosticsLog.tokenSuffix(lookupToFetch.token),
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
                remotePlayFlow.showJoinInviteLookupError(
                    lookupToFetch,
                    message: error.remoteInviteJoinFailureMessage(fallbackKind: .link)
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
        logDiagnostics(
            category: "remoteInvite",
            "acceptStarted",
            fields: [
                "inviteID": invite.id.rawValue,
                "code": invite.code.rawValue,
                "tokenSuffix": DiagnosticsLog.tokenSuffix(invite.token),
                "localPlayerColor": localPlayerColor.rawValue
            ]
        )
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
                remoteLifecycle.cancelRemoteInviteConfirmation()
                startIncomingRemoteInvitePollLoopIfNeeded()
                logDiagnostics(
                    category: "remoteInvite",
                    "acceptSucceeded",
                    fields: [
                        "inviteID": acceptedInvite.invite.id.rawValue,
                        "joinerID": acceptedInvite.joiner.id.rawValue,
                        "joinerColor": acceptedInvite.joinerColor.rawValue
                    ]
                )
                startJoinerRemoteGame(acceptedInvite)
            } catch {
                logDiagnostics(
                    category: "remoteInvite",
                    "acceptFailed",
                    fields: [
                        "inviteID": invite.id.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
                if let terminalMessage = incomingTerminalInviteTitle(from: error) {
                    dismissedIncomingRemoteInviteIDs.insert(invite.id)
                    remoteLifecycle.showTerminalRemoteInviteConfirmation(title: terminalMessage)
                } else {
                    session.message = "Could not start remote game. Check your connection and try again."
                }
                startIncomingRemoteInvitePollLoopIfNeeded()
            }
            remoteInviteAcceptanceTask = nil
        }
    }

    private func cancelPendingOutboundInvite(_ pendingInvite: RemotePlayFlow.PendingInvite) {
        guard let inviteID = pendingInvite.remoteInviteID else {
            return
        }

        cancelRemoteInviteRecord(id: inviteID)
    }

    private func cancelCreatedRemoteInvite(_ invite: RemotePendingInvite) {
        cancelRemoteInviteRecord(id: invite.id)
    }

    private func cancelRemoteInviteRecord(id inviteID: RemoteInviteID) {
        gameLibrary.removePendingRemoteBoard(inviteID: inviteID)
        persistGameLibrary()
        Task { @MainActor in
            do {
                try await remoteInviteTransport.cancelInvite(id: inviteID)
                logDiagnostics(
                    category: "remoteInvite",
                    "cancelInviteSucceeded",
                    fields: ["inviteID": inviteID.rawValue]
                )
            } catch {
                logDiagnostics(
                    category: "remoteInvite",
                    "cancelInviteFailed",
                    fields: [
                        "inviteID": inviteID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
            }
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
        startRemoteGame(context: .joiner(from: acceptedInvite), role: .joiner, inviteID: acceptedInvite.invite.id)
    }

    private func startInviterRemoteGame(_ acceptedInvite: RemoteAcceptedInvite) {
        rememberKnownPlayer(
            KnownRemotePlayer(
                id: acceptedInvite.joiner.id,
                displayName: acceptedInvite.joiner.displayName
            )
        )
        startRemoteGame(context: .inviter(from: acceptedInvite), role: .inviter, inviteID: acceptedInvite.invite.id)
    }

    private func storeAcceptedRemoteGame(_ acceptedInvite: RemoteAcceptedInvite, role: RemoteGameStartRole) {
        let context: RemoteGameStartContext
        switch role {
        case .inviter:
            context = .inviter(from: acceptedInvite)
        case .joiner:
            context = .joiner(from: acceptedInvite)
        }
        let controller = RemoteGameSessionController(
            descriptor: context.descriptor,
            transport: remoteGameTransport,
            initialState: .startingPosition()
        )
        _ = gameLibrary.activateRemoteBoard(for: acceptedInvite.invite.id, snapshot: controller.snapshot)
        persistGameLibrary()
        prepareRemoteMoveNotification(for: context.descriptor)
        prepareRemoteGameStatusNotification(for: context.descriptor.id)
        requestRemoteNotificationAuthorizationIfNeeded()
    }

    private func startRemoteGame(
        context: RemoteGameStartContext,
        role: RemoteGameStartRole,
        inviteID: RemoteInviteID? = nil
    ) {
        logDiagnostics(
            category: "remoteGame",
            "start",
            fields: [
                "gameID": context.descriptor.id.rawValue,
                "role": "\(role)",
                "localPlayerID": context.descriptor.localPlayerID.rawValue,
                "whitePlayerID": context.descriptor.whitePlayer.id.rawValue,
                "blackPlayerID": context.descriptor.blackPlayer.id.rawValue
            ]
        )
        let result = remoteLifecycle.startRemoteGame(context: context, role: role)
        if let activeRemoteGameController = remoteLifecycle.activeRemoteGameController,
           let inviteID {
            let board = gameLibrary.activateRemoteBoard(
                for: inviteID,
                snapshot: activeRemoteGameController.snapshot
            )
            gameLibrary.showBoard(board.id)
            persistGameLibrary()
        }
        persistActiveRemoteGame()
        prepareRemoteMoveNotification(for: result.descriptor)
        prepareRemoteGameStatusNotification(for: result.descriptor.id)
        requestRemoteNotificationAuthorizationIfNeeded()

        if result.shouldStartSyncImmediately {
            syncRemotePresenceForCurrentTurn()
            startRemoteMoveFetchLoopIfNeeded()
        }
    }

    private func handleCommittedMove(_ move: Move) {
        if case let .board(id) = gameLibrary.route {
            gameLibrary.recordCommittedMove(move, in: id)
            persistGameLibrary()
        }
        stopRemotePresenceHeartbeat()
        remoteLifecycle.remoteOpponentPresence = nil

        #if DEBUG
        if let fakeRemoteLab = activeFakeRemoteLab, fakeRemoteLab.isActive {
            Task { @MainActor in
                try? await fakeRemoteLab.recordCommittedLocalMove(move)
            }
            return
        }
        #endif

        guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController else {
            return
        }

        Task { @MainActor in
            do {
                try activeRemoteGameController.recordCommittedLocalMove(move)
                logDiagnostics(
                    category: "remoteMove",
                    "localMoveQueued",
                    fields: diagnosticsMoveFields(move)
                )
                persistActiveRemoteGame()
                try await activeRemoteGameController.uploadPendingMoves()
                persistActiveRemoteGame()
                session.clearMessage(matching: RemoteSyncMessage.uploadFailed)
                logDiagnostics(
                    category: "remoteMove",
                    "uploadSucceeded",
                    fields: diagnosticsMoveFields(move)
                )
                syncRemotePresenceForCurrentTurn()
                startRemoteMoveFetchLoopIfNeeded()
            } catch {
                persistActiveRemoteGame()
                logDiagnostics(
                    category: "remoteMove",
                    "uploadFailed",
                    fields: diagnosticsMoveFields(move).merging([
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }) { current, _ in current }
                )
                session.message = RemoteSyncMessage.uploadFailed
                startRemoteMoveUploadRetryLoopIfNeeded()
            }
        }
    }

    private func resumeRemoteSyncIfNeeded() {
        guard remoteLifecycle.activeRemoteGameController != nil else {
            return
        }
        if let descriptor = remoteLifecycle.activeRemoteGameController?.snapshot.descriptor {
            prepareRemoteMoveNotification(for: descriptor)
            prepareRemoteGameStatusNotification(for: descriptor.id)
        }

        Task { @MainActor in
            guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController else {
                return
            }
            do {
                try await activeRemoteGameController.uploadPendingMoves()
                persistActiveRemoteGame()
                session.clearMessage(matching: RemoteSyncMessage.uploadFailed)
            } catch {
                persistActiveRemoteGame()
                startRemoteMoveUploadRetryLoopIfNeeded()
            }
            await fetchRemoteGameStatusIfNeeded()
            syncRemotePresenceForCurrentTurn()
            startRemoteMoveFetchLoopIfNeeded()
        }
    }

    private func prepareRemoteMoveNotification(for descriptor: RemoteGameDescriptor) {
        guard let notificationPreparing = remoteGameTransport as? any RemoteGameMoveNotificationPreparing else {
            logDiagnostics(
                category: "notifications",
                "moveSubscriptionUnsupported",
                fields: ["gameID": descriptor.id.rawValue]
            )
            return
        }

        Task {
            do {
                try await notificationPreparing.prepareMoveNotification(for: descriptor)
                logDiagnostics(
                    category: "notifications",
                    "moveSubscriptionPrepared",
                    fields: [
                        "gameID": descriptor.id.rawValue,
                        "localPlayerID": descriptor.localPlayerID.rawValue
                    ]
                )
            } catch {
                logDiagnostics(
                    category: "notifications",
                    "moveSubscriptionFailed",
                    fields: [
                        "gameID": descriptor.id.rawValue,
                        "localPlayerID": descriptor.localPlayerID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
            }
        }
    }

    private func prepareRemoteGameStatusNotification(for gameID: RemoteGameID) {
        guard let notificationPreparing = remoteGameTransport as? any RemoteGameLifecycleNotificationPreparing else {
            logDiagnostics(
                category: "notifications",
                "statusSubscriptionUnsupported",
                fields: ["gameID": gameID.rawValue]
            )
            return
        }

        Task {
            do {
                try await notificationPreparing.prepareGameStatusNotification(gameID: gameID)
                logDiagnostics(
                    category: "notifications",
                    "statusSubscriptionPrepared",
                    fields: ["gameID": gameID.rawValue]
                )
            } catch {
                logDiagnostics(
                    category: "notifications",
                    "statusSubscriptionFailed",
                    fields: [
                        "gameID": gameID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
            }
        }
    }

    private func requestRemoteNotificationAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            logDiagnostics(
                category: "notifications",
                "authorizationStatusChecked",
                fields: [
                    "status": RemoteNotificationPermissionPolicy.diagnosticsName(
                        for: settings.authorizationStatus
                    )
                ]
            )
            guard RemoteNotificationPermissionPolicy.shouldRequestAuthorization(
                for: settings.authorizationStatus
            ) else {
                return
            }
            do {
                let granted = try await center.requestAuthorization(options: [.alert])
                logDiagnostics(
                    category: "notifications",
                    "authorizationRequested",
                    fields: ["granted": granted ? "true" : "false"]
                )
                if RemoteNotificationPermissionPolicy.shouldRegisterAfterAuthorizationRequest(granted: granted) {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    logDiagnostics(
                        category: "notifications",
                        "registrationRequestedAfterAuthorization",
                        fields: ["granted": "true"]
                    )
                }
            } catch {
                logDiagnostics(
                    category: "notifications",
                    "authorizationRequestFailed",
                    fields: ["error": String(describing: error)]
                )
            }
        }
    }

    private func prepareIncomingRemoteInviteNotificationIfPossible() {
        guard let profile = try? remoteIdentityStore.loadLocalProfile(),
              profile.displayName != nil else {
            return
        }
        requestRemoteNotificationAuthorizationIfNeeded()
        prepareIncomingRemoteInviteNotification(for: profile.id)
    }

    private func prepareIncomingRemoteInviteNotification(for playerID: RemotePlayerID) {
        Task {
            do {
                try await remoteInviteTransport.prepareIncomingInviteNotification(for: playerID)
            } catch {
                logDiagnostics(
                    category: "remoteInvite",
                    "incomingInviteSubscriptionFailed",
                    fields: [
                        "playerID": playerID.rawValue,
                        "error": String(describing: error)
                    ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                )
            }
        }
    }

    private func fetchRemoteMovesAfterPush(gameID: RemoteGameID) {
        guard remoteLifecycle.activeRemoteGameController?.gameID == gameID else {
            logDiagnostics(
                category: "push",
                "remoteGameMoveIgnored",
                fields: [
                    "gameID": gameID.rawValue,
                    "activeGameID": remoteLifecycle.activeRemoteGameController?.gameID.rawValue ?? "none"
                ]
            )
            return
        }
        logDiagnostics(category: "push", "remoteGameMoveHandled", fields: ["gameID": gameID.rawValue])
        startRemoteMoveFetchLoopIfNeeded()
    }

    private func fetchRemoteGameStatusAfterPush(gameID: RemoteGameID) {
        guard remoteLifecycle.activeRemoteGameController?.gameID == gameID else {
            logDiagnostics(
                category: "push",
                "remoteGameStatusIgnored",
                fields: [
                    "gameID": gameID.rawValue,
                    "activeGameID": remoteLifecycle.activeRemoteGameController?.gameID.rawValue ?? "none"
                ]
            )
            return
        }
        logDiagnostics(category: "push", "remoteGameStatusHandled", fields: ["gameID": gameID.rawValue])
        Task { @MainActor in
            await fetchRemoteGameStatusIfNeeded()
        }
    }

    private func replayBufferedRemotePushNotifications() {
        let events = RemotePushNotificationInbox.shared.drain()
        guard !events.isEmpty else {
            return
        }
        logDiagnostics(
            category: "push",
            "replayingBufferedEvents",
            fields: ["count": "\(events.count)"]
        )
        for event in events {
            switch event {
            case .remoteInviteAcceptance(let inviteID):
                fetchAcceptedInviteAfterPush(id: inviteID)
            case .remotePendingInvite(let playerID):
                guard (try? remoteIdentityStore.loadLocalProfile().id) == playerID else {
                    continue
                }
                Task { @MainActor in
                    await fetchIncomingRemoteInviteIfNeeded(openingInvitationBoard: true)
                }
            case .remoteGameMove(let gameID):
                fetchRemoteMovesAfterPush(gameID: gameID)
            case .remoteGameStatus(let gameID):
                fetchRemoteGameStatusAfterPush(gameID: gameID)
            }
        }
    }

    private func startRemoteMoveFetchLoopIfNeeded() {
        guard remoteLifecycle.activeRemoteGameController != nil,
              !session.localCanActForCurrentTurn else {
            syncRemotePresenceForCurrentTurn()
            return
        }
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController else {
                    remoteMoveFetchTask = nil
                    return
                }
                guard !session.localCanActForCurrentTurn else {
                    syncRemotePresenceForCurrentTurn()
                    remoteMoveFetchTask = nil
                    return
                }

                do {
                    let appliedMoves = try await activeRemoteGameController.fetchAndApplyRemoteMoves(to: session)
                    session.clearMessage(matching: RemoteSyncMessage.fetchFailed)
                    if !appliedMoves.isEmpty {
                        persistActiveRemoteGame()
                        remoteLifecycle.remoteOpponentPresence = nil
                        logDiagnostics(
                            category: "remoteMove",
                            "fetchApplied",
                            fields: ["count": "\(appliedMoves.count)"]
                        )
                        syncRemotePresenceForCurrentTurn()
                        remoteMoveFetchTask = nil
                        return
                    }
                } catch {
                    if !Task.isCancelled {
                        logDiagnostics(
                            category: "remoteMove",
                            "fetchFailed",
                            fields: [
                                "gameID": activeRemoteGameController.gameID.rawValue,
                                "error": String(describing: error)
                            ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                        )
                        session.message = RemoteSyncMessage.fetchFailed
                    }
                }

                let didEnd = await fetchRemoteGameStatusIfNeeded()
                if didEnd {
                    remoteMoveFetchTask = nil
                    return
                }

                await fetchRemotePresenceIfNeeded()

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startRemoteMoveUploadRetryLoopIfNeeded() {
        guard remoteMoveUploadRetryTask == nil,
              remoteLifecycle.activeRemoteGameController?.hasPendingUploads == true else {
            return
        }

        remoteMoveUploadRetryTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    remoteMoveUploadRetryTask = nil
                    return
                }

                guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController else {
                    remoteMoveUploadRetryTask = nil
                    return
                }

                guard activeRemoteGameController.hasPendingUploads else {
                    remoteMoveUploadRetryTask = nil
                    return
                }

                do {
                    try await activeRemoteGameController.uploadPendingMoves()
                    persistActiveRemoteGame()
                    session.clearMessage(matching: RemoteSyncMessage.uploadFailed)
                    syncRemotePresenceForCurrentTurn()
                    startRemoteMoveFetchLoopIfNeeded()

                    guard activeRemoteGameController.hasPendingUploads else {
                        remoteMoveUploadRetryTask = nil
                        return
                    }
                } catch {
                    persistActiveRemoteGame()
                    logDiagnostics(
                        category: "remoteMove",
                        "uploadRetryFailed",
                        fields: [
                            "gameID": activeRemoteGameController.gameID.rawValue,
                            "error": String(describing: error)
                        ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
                    )
                }
            }
        }
    }

    @discardableResult
    private func fetchRemoteGameStatusIfNeeded() async -> Bool {
        guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController,
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
        guard RemoteGameEndPublishingPolicy.shouldPublishOnLocalReset(result: session.state.result),
              let activeRemoteGameController = remoteLifecycle.activeRemoteGameController,
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
                    updatedByDisplayName: localRemotePlayer(from: descriptor).displayName,
                    updatedAt: Date()
                )
            )
        }
    }

    private func endRemoteGameAfterOpponentEnded(descriptor: RemoteGameDescriptor) {
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = nil
        stopRemotePresenceHeartbeat()
        remoteLifecycle.endRemoteGameAfterOpponentEnded(descriptor: descriptor)
        try? activeRemoteGameStore.clear()
    }

    private func persistActiveRemoteGame() {
        guard let activeRemoteGameController = remoteLifecycle.activeRemoteGameController else {
            return
        }
        try? activeRemoteGameStore.save(activeRemoteGameController.snapshot)
        if case let .board(id) = gameLibrary.route,
           gameLibrary.remoteGame(id: id) != nil {
            gameLibrary.updateRemoteGame(activeRemoteGameController.snapshot, in: id)
            persistGameLibrary()
        }
    }

    private func cancelRemoteGameSync(clearSavedGame: Bool) {
        remoteMoveFetchTask?.cancel()
        remoteMoveFetchTask = nil
        remoteMoveUploadRetryTask?.cancel()
        remoteMoveUploadRetryTask = nil
        stopRemotePresenceHeartbeat()
        remoteLifecycle.clearRemoteGameState()
        if clearSavedGame {
            try? activeRemoteGameStore.clear()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active, .inactive:
            syncRemotePresenceForCurrentTurn()
            startIncomingRemoteInvitePollLoopIfNeeded()
        case .background:
            publishLocalRemotePresence(.away, expiresAfter: RemotePresencePolicy.awayExpiresAfter)
            stopRemotePresenceHeartbeat()
            stopIncomingRemoteInvitePollLoop()
        @unknown default:
            break
        }
    }

    private func startIncomingRemoteInvitePollLoopIfNeeded() {
        guard scenePhase != .background,
              incomingRemoteInvitePollTask == nil else {
            return
        }

        incomingRemoteInvitePollTask = Task { @MainActor in
            while !Task.isCancelled {
                if remoteLifecycle.pendingRemoteInviteConfirmation == nil {
                    await fetchIncomingRemoteInviteIfNeeded()
                } else {
                    await validatePendingRemoteInviteConfirmationIfNeeded()
                }
                await fetchAcceptedPendingRemoteBoardsIfNeeded()

                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    incomingRemoteInvitePollTask = nil
                    return
                }
            }
        }
    }

    private func stopIncomingRemoteInvitePollLoop() {
        incomingRemoteInvitePollTask?.cancel()
        incomingRemoteInvitePollTask = nil
    }

    private func fetchIncomingRemoteInviteIfNeeded(openingInvitationBoard: Bool = false) async {
        guard let profile = try? remoteIdentityStore.loadLocalProfile(),
              profile.displayName != nil else {
            return
        }

        do {
            guard let invite = try await remoteInviteTransport.fetchPendingInvite(for: profile.id, now: Date()) else {
                return
            }
            let board = gameLibrary.createPendingRemoteBoard(invite)
            persistGameLibrary()
            guard remoteLifecycle.pendingRemoteInviteAcceptance?.id != invite.id,
                  remoteLifecycle.pendingRemoteInviteConfirmation == nil,
                  !dismissedIncomingRemoteInviteIDs.contains(invite.id) else {
                return
            }
            logDiagnostics(
                category: "remoteInvite",
                "incomingAddressedInviteFound",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "code": invite.code.rawValue,
                    "inviterID": invite.inviter.id.rawValue,
                    "whiteAssignment": invite.whiteAssignment.rawValue
                ]
            )
            if openingInvitationBoard {
                openPendingRemoteBoard(board)
            } else {
                foregroundIncomingInvite = board
            }
        } catch {
            logDiagnostics(
                category: "remoteInvite",
                "incomingAddressedInviteFetchFailed",
                fields: [
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
        }
    }

    private func fetchAcceptedPendingRemoteBoardsIfNeeded() async {
        let outgoingInviteIDs = gameLibrary.pendingRemoteBoards
            .filter { $0.role == .inviter }
            .map { $0.invite.id }
        for inviteID in outgoingInviteIDs {
            fetchAcceptedInviteAfterPush(id: inviteID)
        }
    }

    private func remoteInviteConfirmationPurpose(for invite: RemotePendingInvite) -> RemoteInviteConfirmationPurpose {
        if remoteLifecycle.activeRemoteGameOpponent?.id == invite.inviter.id {
            return .newGame
        }
        return .play
    }

    private func validatePendingRemoteInviteConfirmationIfNeeded() async {
        guard let invite = remoteLifecycle.pendingRemoteInviteAcceptance else {
            return
        }

        do {
            _ = try await remoteInviteTransport.fetchInvite(code: invite.code, token: invite.token, now: Date())
        } catch {
            guard let terminalMessage = incomingTerminalInviteTitle(from: error) else {
                return
            }
            dismissedIncomingRemoteInviteIDs.insert(invite.id)
            remoteLifecycle.showTerminalRemoteInviteConfirmation(title: terminalMessage)
            logDiagnostics(
                category: "remoteInvite",
                "pendingConfirmationInvalidated",
                fields: [
                    "inviteID": invite.id.rawValue,
                    "error": String(describing: error)
                ].merging(DiagnosticsLog.cloudKitFields(from: error)) { current, _ in current }
            )
        }
    }

    private func incomingTerminalInviteTitle(from error: Error) -> String? {
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

    private func outboundTerminalInviteMessage(from error: Error) -> String? {
        guard let remoteInviteError = error as? RemoteInviteTransportError else {
            return nil
        }

        switch remoteInviteError {
        case .declined(let inviteeDisplayName):
            return "Sorry, \(inviteeDisplayName ?? "the other player") declined this game."
        case .cancelled(let inviterDisplayName):
            return "Sorry, \(inviterDisplayName) canceled this game."
        case .notFound, .tokenMismatch, .expired, .notPending, .colorChoiceRequired, .colorChoiceNotAllowed, .codeCollision:
            return nil
        }
    }

    private func reportLocalBoardInteraction() {
        guard remoteLifecycle.activeRemoteGameController != nil,
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
        guard remoteLifecycle.activeRemoteGameController != nil else {
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
        guard remoteLifecycle.activeRemoteGameController != nil,
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
                      remoteLifecycle.activeRemoteGameController != nil,
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
        guard let descriptor = remoteLifecycle.activeRemoteGameController?.snapshot.descriptor,
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
        guard let descriptor = remoteLifecycle.activeRemoteGameController?.snapshot.descriptor,
              let remoteTurnPlayer = remoteTurnPlayer(from: descriptor),
              let presenceTransport = remoteGameTransport as? any RemotePresenceTransport else {
            remoteLifecycle.remoteOpponentPresence = nil
            return
        }

        do {
            remoteLifecycle.remoteOpponentPresence = try await presenceTransport.fetchPresence(
                gameID: descriptor.id,
                playerID: remoteTurnPlayer.id
            )
        } catch {
            remoteLifecycle.remoteOpponentPresence = nil
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

    private func localRemotePlayer(from descriptor: RemoteGameDescriptor) -> RemotePlayerRef {
        if descriptor.localPlayerID == descriptor.whitePlayer.id {
            return descriptor.whitePlayer
        }
        return descriptor.blackPlayer
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

    private static func remoteInviteTransport(
        for mode: RemotePlayRuntimeMode,
        diagnosticsLog: DiagnosticsLog
    ) -> any RemoteInviteTransport {
        switch mode {
        case .fakeLocal:
            return InMemoryRemoteInviteTransport()
        case .cloudKit:
            return CloudKitRemoteInviteTransport(diagnosticsLog: diagnosticsLog)
        }
    }

    private static func remoteGameTransport(
        for mode: RemotePlayRuntimeMode,
        diagnosticsLog: DiagnosticsLog
    ) -> any RemoteGameTransport {
        switch mode {
        case .fakeLocal:
            return InMemoryRemoteGameTransport()
        case .cloudKit:
            return CloudKitRemoteGameTransport(diagnosticsLog: diagnosticsLog)
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
                if case .waitingForInvitee(let pendingInvite) = remotePlayFlow.stage {
                    cancelPendingOutboundInvite(pendingInvite)
                }
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

private struct GamesRackView: View {
    let entries: [GameLibraryEntry]
    let onStartGame: () -> Void
    let onOpenEntry: (GameLibraryEntry) -> Void

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let columns = Array(
                repeating: GridItem(.flexible(minimum: isWide ? 170 : 132, maximum: 260), spacing: 20),
                count: isWide ? 3 : 2
            )

            ZStack {
                AppTheme.table.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Games")
                            .font(AppTheme.panelTitleFont)
                            .foregroundStyle(AppTheme.ink)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            Button(action: onStartGame) {
                                StartGameRackCard()
                            }
                            .buttonStyle(GameRackButtonStyle())
                            .accessibilityIdentifier("games-start-card")

                            ForEach(entries) { entry in
                                Button {
                                    onOpenEntry(entry)
                                } label: {
                                    GameRackCard(presentation: entry.cardPresentation)
                                }
                                .buttonStyle(GameRackButtonStyle())
                                .accessibilityIdentifier("game-card-\(entry.id.rawValue.uuidString)")
                            }
                        }

                        if entries.isEmpty {
                            Text("Your boards will appear here.")
                                .font(AppTheme.emptyPanelFont)
                                .foregroundStyle(AppTheme.mutedInk)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(isWide ? 30 : 24)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(AppTheme.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(AppTheme.boardFrame, lineWidth: 14)
                        }
                        .shadow(color: AppTheme.captureBoxShadow, radius: 22, y: 12)
                }
                .padding(isWide ? 42 : 24)
            }
        }
    }
}

private struct StartGameRackCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                AppTheme.captureBoxFelt.opacity(0.68),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 7])
                            )
                    }
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.captureBoxFelt)
            }
            .aspectRatio(1, contentMode: .fit)

            Text("Start a Game")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("On this iPad or remotely")
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }
}

private struct GameRackCard: View {
    let presentation: GameCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameThumbnail(state: presentation.boardState, moveCount: presentation.moves.count)
                .aspectRatio(1, contentMode: .fit)

            Text(presentation.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            Text(presentation.status)
                .font(.subheadline)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(1)
            Text(presentation.lastActivityAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk.opacity(0.78))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }
}

private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(AppTheme.panelWarmth)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.panelStroke, lineWidth: 1)
        }
}

private struct GameRackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.80 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

private struct StartGameTypeChooserView: View {
    let onStartLocal: () -> Void
    let onStartRemote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start a Game")
                .font(AppTheme.panelTitleFont)
                .foregroundStyle(AppTheme.ink)
            Text("Choose who will be at the board.")
                .font(AppTheme.panelBodyFont)
                .foregroundStyle(AppTheme.mutedInk)

            VStack(spacing: 12) {
                Button(action: onStartLocal) {
                    StartGameChoiceCard(
                        title: "On this iPad",
                        subtitle: "Take turns around one board",
                        symbol: "person.2.fill",
                        isPrimary: true
                    )
                }
                .buttonStyle(GameRackButtonStyle())

                Button(action: onStartRemote) {
                    StartGameChoiceCard(
                        title: "With someone else",
                        subtitle: "Invite a player to their own board",
                        symbol: "network",
                        isPrimary: false
                    )
                }
                .buttonStyle(GameRackButtonStyle())
            }
        }
        .padding(24)
    }
}

private struct StartGameChoiceCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(isPrimary ? AppTheme.lightSquare : AppTheme.captureBoxFelt)
                .frame(width: 48, height: 48)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isPrimary ? AppTheme.captureBoxFelt : AppTheme.panelWarmth)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }
}

private struct IncomingInviteNoticeView: View {
    let inviterName: String
    let onView: () -> Void
    let onLater: () -> Void

    var body: some View {
        GameOverlayCard(
            title: "Invitation from \(inviterName)",
            message: "There’s a new board ready when you are.",
            secondaryTitle: "Not now",
            onSecondary: onLater,
            primaryTitle: "View invitation",
            onPrimary: onView
        )
    }
}

private struct InvitationSentNoticeView: View {
    let onKeepLooking: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GameOverlayCard(
            title: "Invitation sent",
            message: "This board will be ready when the invitation is accepted.",
            secondaryTitle: "Cancel invite",
            onSecondary: onCancel,
            primaryTitle: "Keep looking",
            onPrimary: onKeepLooking
        )
    }
}

private struct GameOverlayCard: View {
    let title: String
    let message: String
    let secondaryTitle: String
    let onSecondary: () -> Void
    let primaryTitle: String
    let onPrimary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(AppTheme.panelTitleFont)
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(AppTheme.panelBodyFont)
                .foregroundStyle(AppTheme.mutedInk)
            HStack(spacing: 12) {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameOverlayButtonStyle(isPrimary: false))

                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameOverlayButtonStyle(isPrimary: true))
            }
        }
        .padding(26)
        .frame(width: 430)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.boardFrame, lineWidth: 8)
                }
        }
        .shadow(color: AppTheme.captureBoxShadow, radius: 22, y: 12)
    }
}

private struct GameOverlayButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(isPrimary ? AppTheme.whitePiece : AppTheme.ink)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? AppTheme.captureBoxFelt : AppTheme.panelWarmth)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.20, dampingFraction: 0.86), value: configuration.isPressed)
        }
    }

private struct GameThumbnail: View {
    let state: GameState
    let moveCount: Int

    private let squares = (1...8).reversed().flatMap { rank in
        Square.File.allCases.map { Square(file: $0, rank: rank) }
    }

    var body: some View {
        GeometryReader { proxy in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 0) {
                ForEach(squares, id: \.self) { square in
                    ZStack {
                        Rectangle()
                            .fill(square.isLightSquare ? AppTheme.lightSquare : AppTheme.darkSquare)
                        if let piece = state.board[square] {
                            PieceIconView(piece: piece)
                                .padding(1)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.boardFrame.opacity(0.82), lineWidth: 4)
        }
        .accessibilityLabel("Chess board after \(moveCount) moves")
    }
}

private struct InviteLinkRequest: Equatable {
    let id = UUID()
    let lookup: RemotePlayFlow.InviteLookup
    let expectedStage: RemotePlayFlow.Stage
    let expectedJoinCode: String
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
