enum RemoteGameStartRole {
    case inviter
    case joiner
}

enum RemoteGameStartPresentationPolicy {
    static func shouldShowAnnouncement(for role: RemoteGameStartRole) -> Bool {
        role == .inviter
    }
}
