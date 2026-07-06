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
        case joined
        case saved
    }

    struct PendingInvite: Equatable, Hashable {
        let target: InviteTarget
        let whiteChoice: WhiteChoice
        let code: String

        var formattedCode: String {
            guard code.count == 6 else {
                return code
            }
            let splitIndex = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<splitIndex]) \(code[splitIndex...])"
        }
    }

    struct InviteSharePresentation: Equatable {
        let codeSectionTitle: String
        let code: String
        let codeInstructions: String
        let linkSectionTitle: String
        let copyLinkButtonTitle: String
        let inviteURL: URL
        let linkInstructions: String
    }

    enum Stage: Equatable, Hashable {
        case closed
        case choosing
        case choosingWhite(InviteTarget)
        case waitingForInvitee(PendingInvite)
        case enteringLocalName(LocalNameAction)
    }

    private let nextInviteCode: String
    private var pendingLocalNameInviteTarget: InviteTarget?
    private var localNameEditReturnStage: Stage?
    private(set) var knownPlayers: [KnownRemotePlayer]
    private(set) var stage: Stage = .closed
    private(set) var localDisplayName: String?
    private(set) var localNameDraft = ""
    var selectedWhiteChoice: WhiteChoice = .localPlayer
    private(set) var joinCode = ""
    private(set) var joinErrorMessage: String?

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
        return InviteSharePresentation(
            codeSectionTitle: "Join code",
            code: pendingInvite.formattedCode,
            codeInstructions: "\(inviteeName) can join by tapping Play Remotely and entering this code.",
            linkSectionTitle: "Invite link",
            copyLinkButtonTitle: "Copy link",
            inviteURL: Self.inviteURL(for: pendingInvite.code),
            linkInstructions: "You can send the link by Messages, Mail, or another app."
        )
    }

    var canSubmitJoinCode: Bool {
        joinCode.count == 6
    }

    init(
        knownPlayers: [KnownRemotePlayer] = [],
        localDisplayName: String? = nil,
        nextInviteCode: String = "428193"
    ) {
        self.knownPlayers = knownPlayers
        self.localDisplayName = Self.trimmedNonEmptyName(localDisplayName ?? "")
        self.nextInviteCode = nextInviteCode
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
    func requestJoinCode() -> Bool {
        guard localDisplayName != nil else {
            localNameDraft = ""
            pendingLocalNameInviteTarget = nil
            stage = .enteringLocalName(.joinWithCode)
            return false
        }

        return acceptJoinCode()
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
            return acceptJoinCode() ? .joined : nil
        case .edit:
            stage = localNameEditReturnStage ?? .choosing
            localNameEditReturnStage = nil
            return .saved
        }
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
    func requestJoinInvite(from url: URL) -> Bool {
        guard let code = Self.inviteCode(from: url) else {
            open()
            joinErrorMessage = "That link did not match an open invite."
            return false
        }

        if stage == .closed {
            open()
        }
        updateJoinCode(code)
        return requestJoinCode()
    }

    private func acceptJoinCode() -> Bool {
        guard canSubmitJoinCode, joinCode == nextInviteCode else {
            joinErrorMessage = "That code did not match an open invite."
            return false
        }

        joinCode = ""
        joinErrorMessage = nil
        stage = .closed
        return true
    }

    @discardableResult
    private func sendInvite(target explicitTarget: InviteTarget? = nil) -> PendingInvite {
        let target = explicitTarget ?? selectedInviteTarget()

        let pendingInvite = PendingInvite(
            target: target,
            whiteChoice: selectedWhiteChoice,
            code: nextInviteCode
        )
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

    private static func inviteURL(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = "chesstutor"
        components.host = "invite"
        components.queryItems = [
            URLQueryItem(name: "code", value: code)
        ]
        return components.url!
    }

    private static func inviteCode(from url: URL) -> String? {
        guard url.scheme == "chesstutor",
              url.host == "invite",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawCode = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }

        let code = String(rawCode.filter(\.isNumber).prefix(6))
        return code.count == 6 ? code : nil
    }

    func goBack() {
        switch stage {
        case .choosingWhite, .waitingForInvitee:
            selectedWhiteChoice = .localPlayer
            stage = .choosing
        case .closed, .choosing, .enteringLocalName:
            break
        }
    }

    func cancel() {
        selectedWhiteChoice = .localPlayer
        pendingLocalNameInviteTarget = nil
        localNameEditReturnStage = nil
        localNameDraft = ""
        joinCode = ""
        joinErrorMessage = nil
        stage = .closed
    }

    private static func trimmedNonEmptyName(_ displayName: String) -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
