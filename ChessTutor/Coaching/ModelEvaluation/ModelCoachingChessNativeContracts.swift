struct ModelCoachingChessNativeContextCompilation: Codable, Equatable, Sendable {
    let schemaVersion: String
    let promptVersion: String
    let requestID: String
    let positionRevision: Int
    let markdown: String
    let availableActions: [String]
    let availableMoveFocus: [ModelCoachingChessNativeMoveFocus]
}

struct ModelCoachingChessNativeResponseContract: Codable, Equatable, Sendable {
    let availableActions: [String]
    let availableMoveFocus: [ModelCoachingChessNativeMoveFocus]
}

struct ModelCoachingChessNativeMoveFocus: Codable, Equatable, Hashable, Sendable {
    let from: String
    let to: String
}

enum ModelCoachingChessNativeFocus: Codable, Equatable, Hashable, Sendable {
    case square(String)
    case move(from: String, to: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case square
        case from
        case to
    }

    private enum Kind: String, Codable {
        case square
        case move
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .square:
            self = .square(try container.decode(String.self, forKey: .square))
        case .move:
            self = .move(
                from: try container.decode(String.self, forKey: .from),
                to: try container.decode(String.self, forKey: .to)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .square(let square):
            try container.encode(Kind.square, forKey: .type)
            try container.encode(square, forKey: .square)
        case .move(let from, let to):
            try container.encode(Kind.move, forKey: .type)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        }
    }
}

struct ModelCoachingChessNativeTurn: Codable, Equatable, Sendable {
    let message: String
    let actions: [String]
    let focus: [ModelCoachingChessNativeFocus]
}
