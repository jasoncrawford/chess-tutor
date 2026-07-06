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
    }

    enum LocalNameSaveResult: Equatable {
        case sentInvite(PendingInvite)
        case joined
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

    enum Stage: Equatable, Hashable {
        case closed
        case choosing
        case choosingWhite(InviteTarget)
        case waitingForInvitee(PendingInvite)
        case enteringLocalName(LocalNameAction)
    }

    private let nextInviteCode: String
    private var pendingLocalNameInviteTarget: InviteTarget?
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
