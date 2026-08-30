struct ModelCoachingChessNativeContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let availableActions: [String]
    let availableMoveFocus: [ModelCoachingChessNativeMoveFocus]
}

struct ModelCoachingChessNativeMoveFocus: Codable, Equatable, Hashable, Sendable {
    let from: String
    let to: String
}
