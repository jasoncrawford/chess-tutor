enum MoveAttemptResult: Equatable, Sendable {
    case moved
    case illegal(String)
    case needsPromotion(from: Square, to: Square)
}
