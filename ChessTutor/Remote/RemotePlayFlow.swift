import Foundation
import Observation

struct KnownRemotePlayer: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: RemotePlayerID
    let displayName: String
}

@Observable
final class RemotePlayFlow {
    enum InviteTarget: Equatable, Hashable {
        case known(KnownRemotePlayer)
        case newPlayer
    }

    enum WhiteChoice: Equatable, Hashable {
        case localPlayer
        case invitee
        case inviteeChooses
    }

    enum LocalNameAction: Equatable, Hashable {
        case sendInvite
        case joinWithCode
        case edit
    }

    enum LocalNameSaveResult: Equatable {
        case sentInvite(PendingInvite)
        case needsConfirmation(RemoteInviteConfirmation)
        case saved
    }

    enum JoinCodeResult: Equatable {
        case needsConfirmation(RemoteInviteConfirmation)
    }

    struct PendingInvite: Equatable, Hashable {
        let target: InviteTarget
        let whiteChoice: WhiteChoice
        let code: String
        let token: String?
        let remoteInviteID: RemoteInviteID?

        init(
            target: InviteTarget,
            whiteChoice: WhiteChoice,
            code: String,
            token: String? = nil,
            remoteInviteID: RemoteInviteID? = nil
        ) {
            self.target = target
            self.whiteChoice = whiteChoice
            self.code = code
            self.token = token
            self.remoteInviteID = remoteInviteID
        }

        var formattedCode: String {
            InviteCode(rawValue: code).formatted
        }
    }

    struct InviteSharePresentation: Equatable {
        let codeSectionTitle: String
        let code: String
        let codeInstructions: String
        let linkSectionTitle: String
        let copyLinkButtonTitle: String
        let isCopyLinkButtonEnabled: Bool
        let inviteURL: URL
        let linkInstructions: String
    }

    struct InviteLookup: Equatable {
        let code: InviteCode
        let token: RemoteInviteToken?
    }

    enum Stage: Equatable, Hashable {
        case closed
        case choosing
        case choosingWhite(InviteTarget)
        case waitingForInvitee(PendingInvite)
        case enteringLocalName(LocalNameAction)
    }

    private let nextInviteCode: String
    private let nextJoinWhiteChoice: WhiteChoice
    private var pendingLocalNameInviteTarget: InviteTarget?
    private var pendingLocalNameJoinWhiteChoice: WhiteChoice?
    private var pendingLocalNameJoinLookup: InviteLookup?
    private var localNameEditReturnStage: Stage?
    private var inviteWhiteChoicesByCode: [String: WhiteChoice] = [:]
    private(set) var knownPlayers: [KnownRemotePlayer]
    private(set) var stage: Stage = .closed
    private(set) var localDisplayName: String?
    private(set) var localNameDraft = ""
    var selectedWhiteChoice: WhiteChoice = .localPlayer
    private(set) var joinCode = ""
    private(set) var joinErrorMessage: String?
    private var copiedInviteURL: URL?

    var canSubmitLocalName: Bool {
        Self.trimmedNonEmptyName(localNameDraft) != nil
    }

    var showsLocalIdentitySummary: Bool {
        localDisplayName != nil && stage == .choosing
    }

    var sheetTitle: String {
        if case .choosingWhite(let target) = stage {
            return title(for: target)
        }

        if case .waitingForInvitee = stage {
            return "Share invite"
        }

        return "Play Remotely"
    }

    var whiteChoicePromptTitle: String {
        "Who plays White and goes first?"
    }

    func inviteSharePresentation(for pendingInvite: PendingInvite) -> InviteSharePresentation {
        let inviteeName = shareInviteeName(for: pendingInvite.target)
        let inviteURL = Self.inviteURL(for: pendingInvite)
        let isCopiedInviteURL = copiedInviteURL == inviteURL
        return InviteSharePresentation(
            codeSectionTitle: "Join code",
            code: pendingInvite.formattedCode,
            codeInstructions: "\(inviteeName) can join by tapping Play Remotely and entering this code.",
            linkSectionTitle: "Invite link",
            copyLinkButtonTitle: isCopiedInviteURL ? "Copied!" : "Copy link",
            isCopyLinkButtonEnabled: !isCopiedInviteURL,
            inviteURL: inviteURL,
            linkInstructions: "You can send the link by Messages, Mail, or another app."
        )
    }

    var canSubmitJoinCode: Bool {
        joinCode.count == 6
    }

    init(
        knownPlayers: [KnownRemotePlayer] = [],
        localDisplayName: String? = nil,
        nextInviteCode: String = "428193",
        nextJoinWhiteChoice: WhiteChoice = .localPlayer
    ) {
        self.knownPlayers = knownPlayers
        self.localDisplayName = Self.trimmedNonEmptyName(localDisplayName ?? "")
        self.nextInviteCode = nextInviteCode
        self.nextJoinWhiteChoice = nextJoinWhiteChoice
    }

    func canShowEntryPoint(for session: GameSession) -> Bool {
        session.state.result == .ongoing
            && !session.hasGameInProgress
            && session.whitePlayer == .humanLocal
            && session.blackPlayer == .humanLocal
    }

    func open() {
        selectedWhiteChoice = .localPlayer
        pendingLocalNameInviteTarget = nil
        pendingLocalNameJoinWhiteChoice = nil
        pendingLocalNameJoinLookup = nil
        localNameEditReturnStage = nil
        joinErrorMessage = nil
        stage = .choosing
    }

    func invite(_ player: KnownRemotePlayer) {
        selectedWhiteChoice = .localPlayer
        stage = .choosingWhite(.known(player))
    }

    func inviteSomeoneNew() {
        selectedWhiteChoice = .localPlayer
        stage = .choosingWhite(.newPlayer)
    }

    func chooseWhite(_ choice: WhiteChoice) {
        selectedWhiteChoice = choice
    }

    func markInviteLinkCopied(_ inviteURL: URL) {
        copiedInviteURL = inviteURL
    }

    func showCreatedRemoteInvite(_ invite: RemotePendingInvite, target: InviteTarget) {
        let pendingInvite = PendingInvite(
            target: target,
            whiteChoice: Self.whiteChoice(from: invite.whiteAssignment),
            code: invite.code.rawValue,
            token: invite.token.rawValue,
            remoteInviteID: invite.id
        )
        inviteWhiteChoicesByCode[pendingInvite.code] = pendingInvite.whiteChoice
        stage = .waitingForInvitee(pendingInvite)
    }

    func clearCopiedInviteLink() {
        copiedInviteURL = nil
    }

    func updateLocalDisplayName(_ displayName: String?) {
        localDisplayName = Self.trimmedNonEmptyName(displayName ?? "")
    }

    func updateLocalNameDraft(_ draft: String) {
        localNameDraft = draft
    }

    func editLocalDisplayName() {
        localNameDraft = localDisplayName ?? ""
        localNameEditReturnStage = stage
        stage = .enteringLocalName(.edit)
    }

    @discardableResult
    func requestSendInvite() -> PendingInvite? {
        guard localDisplayName != nil else {
            localNameDraft = ""
            pendingLocalNameInviteTarget = selectedInviteTarget()
            stage = .enteringLocalName(.sendInvite)
            return nil
        }

        return sendInvite()
    }

    @discardableResult
    func requestJoinCode() -> JoinCodeResult? {
        guard localDisplayName != nil else {
            localNameDraft = ""
            pendingLocalNameInviteTarget = nil
            pendingLocalNameJoinWhiteChoice = whiteChoiceForCurrentJoinCode()
            pendingLocalNameJoinLookup = InviteLookup(code: InviteCode(rawValue: joinCode), token: nil)
            stage = .enteringLocalName(.joinWithCode)
            return nil
        }

        return acceptJoinCode(whiteChoice: whiteChoiceForCurrentJoinCode())
    }

    @discardableResult
    func saveLocalNameAndContinue() -> LocalNameSaveResult? {
        guard case .enteringLocalName(let action) = stage,
              let displayName = Self.trimmedNonEmptyName(localNameDraft) else {
            return nil
        }

        localDisplayName = displayName
        localNameDraft = ""

        switch action {
        case .sendInvite:
            let pendingInvite = sendInvite(target: pendingLocalNameInviteTarget)
            pendingLocalNameInviteTarget = nil
            return .sentInvite(pendingInvite)
        case .joinWithCode:
            stage = .choosing
            let whiteChoice = pendingLocalNameJoinWhiteChoice ?? nextJoinWhiteChoice
            pendingLocalNameJoinWhiteChoice = nil
            pendingLocalNameJoinLookup = nil
            switch acceptJoinCode(whiteChoice: whiteChoice) {
            case .needsConfirmation(let confirmation):
                return .needsConfirmation(confirmation)
            case nil:
                return nil
            }
        case .edit:
            stage = localNameEditReturnStage ?? .choosing
            localNameEditReturnStage = nil
            return .saved
        }
    }

    @discardableResult
    func saveLocalNameForPendingJoin() -> InviteLookup? {
        guard case .enteringLocalName(.joinWithCode) = stage,
              let displayName = Self.trimmedNonEmptyName(localNameDraft) else {
            return nil
        }

        let lookup = pendingLocalNameJoinLookup ?? InviteLookup(code: InviteCode(rawValue: joinCode), token: nil)
        localDisplayName = displayName
        localNameDraft = ""
        pendingLocalNameJoinWhiteChoice = nil
        pendingLocalNameJoinLookup = nil
        stage = .choosing
        return lookup
    }

    func rememberKnownPlayer(_ player: KnownRemotePlayer) {
        if let existingIndex = knownPlayers.firstIndex(where: { $0.id == player.id }) {
            knownPlayers[existingIndex] = player
        } else {
            knownPlayers.append(player)
        }
        knownPlayers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func updateJoinCode(_ code: String) {
        joinCode = String(code.filter(\.isNumber).prefix(6))
        joinErrorMessage = nil
    }

    @discardableResult
    func requestJoinInvite(from url: URL) -> JoinCodeResult? {
        guard let lookup = Self.inviteLookup(from: url) else {
            open()
            joinErrorMessage = "That link did not match an open invite."
            return nil
        }

        if stage == .closed {
            open()
        }
        updateJoinCode(lookup.code.rawValue)

        guard localDisplayName != nil else {
            localNameDraft = ""
            pendingLocalNameInviteTarget = nil
            pendingLocalNameJoinWhiteChoice = whiteChoiceForCurrentJoinCode()
            pendingLocalNameJoinLookup = lookup
            stage = .enteringLocalName(.joinWithCode)
            return nil
        }

        return acceptJoinCode(whiteChoice: whiteChoiceForCurrentJoinCode())
    }

    @discardableResult
    func requestJoinInviteLookup(_ lookup: InviteLookup) -> InviteLookup? {
        updateJoinCode(lookup.code.rawValue)

        guard localDisplayName != nil else {
            if stage == .closed {
                open()
            }
            localNameDraft = ""
            pendingLocalNameInviteTarget = nil
            pendingLocalNameJoinWhiteChoice = whiteChoiceForCurrentJoinCode()
            pendingLocalNameJoinLookup = lookup
            stage = .enteringLocalName(.joinWithCode)
            return nil
        }

        return lookup
    }

    func showJoinInviteLookupError(_ lookup: InviteLookup, message: String) {
        if stage == .closed {
            open()
        }
        updateJoinCode(lookup.code.rawValue)
        joinErrorMessage = message
    }

    private func acceptJoinCode(whiteChoice: WhiteChoice) -> JoinCodeResult? {
        guard canSubmitJoinCode, joinCode == nextInviteCode else {
            joinErrorMessage = "That code did not match an open invite."
            return nil
        }

        joinCode = ""
        joinErrorMessage = nil

        switch whiteChoice {
        case .localPlayer:
            stage = .closed
            return .needsConfirmation(joinConfirmation(localPlayerColor: .black))
        case .invitee:
            stage = .closed
            return .needsConfirmation(joinConfirmation(localPlayerColor: .white))
        case .inviteeChooses:
            stage = .closed
            return .needsConfirmation(joinConfirmation(localPlayerColor: nil))
        }
    }

    private func joinConfirmation(localPlayerColor: PieceColor?) -> RemoteInviteConfirmation {
        RemoteInviteConfirmation(opponentName: "Maya", localPlayerColor: localPlayerColor)
    }

    private func whiteChoiceForCurrentJoinCode() -> WhiteChoice {
        inviteWhiteChoicesByCode[joinCode] ?? nextJoinWhiteChoice
    }

    @discardableResult
    private func sendInvite(target explicitTarget: InviteTarget? = nil) -> PendingInvite {
        let target = explicitTarget ?? selectedInviteTarget()
        copiedInviteURL = nil

        let pendingInvite = PendingInvite(
            target: target,
            whiteChoice: selectedWhiteChoice,
            code: nextInviteCode
        )
        inviteWhiteChoicesByCode[pendingInvite.code] = pendingInvite.whiteChoice
        stage = .waitingForInvitee(pendingInvite)
        return pendingInvite
    }

    private func selectedInviteTarget() -> InviteTarget {
        if case .choosingWhite(let selectedTarget) = stage {
            return selectedTarget
        } else {
            return .newPlayer
        }
    }

    private func title(for target: InviteTarget) -> String {
        switch target {
        case .known(let player):
            return "Invite \(player.displayName)"
        case .newPlayer:
            return "Invite Someone New"
        }
    }

    private func shareInviteeName(for target: InviteTarget) -> String {
        switch target {
        case .known(let player):
            return player.displayName
        case .newPlayer:
            return "The other player"
        }
    }

    private static func inviteURL(for pendingInvite: PendingInvite) -> URL {
        var queryItems = [URLQueryItem(name: "code", value: pendingInvite.code)]
        if let token = pendingInvite.token {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }

        var components = URLComponents()
        components.scheme = "chesstutor"
        components.host = "invite"
        components.queryItems = queryItems
        return components.url!
    }

    private static func whiteChoice(from assignment: RemoteInviteWhiteAssignment) -> WhiteChoice {
        switch assignment {
        case .inviter:
            return .localPlayer
        case .invitee:
            return .invitee
        case .inviteeChooses:
            return .inviteeChooses
        }
    }

    static func inviteLookup(from url: URL) -> InviteLookup? {
        guard url.scheme == "chesstutor",
              url.host == "invite",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }

        let code = String(rawCode.filter(\.isNumber).prefix(6))
        guard code.count == 6 else {
            return nil
        }

        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
            .map(RemoteInviteToken.init(rawValue:))
        return InviteLookup(code: InviteCode(rawValue: code), token: token)
    }

    func goBack() {
        switch stage {
        case .choosingWhite, .waitingForInvitee:
            selectedWhiteChoice = .localPlayer
            copiedInviteURL = nil
            stage = .choosing
        case .closed, .choosing, .enteringLocalName:
            break
        }
    }

    func cancel() {
        selectedWhiteChoice = .localPlayer
        pendingLocalNameInviteTarget = nil
        pendingLocalNameJoinWhiteChoice = nil
        pendingLocalNameJoinLookup = nil
        localNameEditReturnStage = nil
        localNameDraft = ""
        joinCode = ""
        joinErrorMessage = nil
        copiedInviteURL = nil
        stage = .closed
    }

    private static func trimmedNonEmptyName(_ displayName: String) -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
