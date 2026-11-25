import Foundation

enum ModelCoachingVisualMessageRun: Codable, Equatable, Sendable {
    case text(String)
    case piece(text: String, square: String)
    case square(text: String, square: String)

    var text: String {
        switch self {
        case .text(let text), .piece(let text, _), .square(let text, _): text
        }
    }

    var referencedSquare: String? {
        switch self {
        case .text: nil
        case .piece(_, let square), .square(_, let square): square
        }
    }

    private enum CodingKeys: String, CodingKey { case type, text, square }
    private enum Kind: String, Codable { case text, piece, square }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text: self = .text(text)
        case .piece: self = .piece(text: text, square: try container.decode(String.self, forKey: .square))
        case .square: self = .square(text: text, square: try container.decode(String.self, forKey: .square))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        switch self {
        case .text: try container.encode(Kind.text, forKey: .type)
        case .piece(_, let square):
            try container.encode(Kind.piece, forKey: .type)
            try container.encode(square, forKey: .square)
        case .square(_, let square):
            try container.encode(Kind.square, forKey: .type)
            try container.encode(square, forKey: .square)
        }
    }
}

enum ModelCoachingVisualCue: Codable, Equatable, Sendable {
    case attack(from: String, to: String)
    case move(from: String, to: String)

    var endpoints: ModelCoachingChessNativeMoveFocus {
        switch self {
        case .attack(let from, let to), .move(let from, let to): .init(from: from, to: to)
        }
    }

    private enum CodingKeys: String, CodingKey { case type, from, to }
    private enum Kind: String, Codable { case attack, move }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let from = try container.decode(String.self, forKey: .from)
        let to = try container.decode(String.self, forKey: .to)
        switch try container.decode(Kind.self, forKey: .type) {
        case .attack: self = .attack(from: from, to: to)
        case .move: self = .move(from: from, to: to)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoints.from, forKey: .from)
        try container.encode(endpoints.to, forKey: .to)
        switch self {
        case .attack: try container.encode(Kind.attack, forKey: .type)
        case .move: try container.encode(Kind.move, forKey: .type)
        }
    }
}

struct ModelCoachingVisualContent: Codable, Equatable, Sendable {
    let runs: [ModelCoachingVisualMessageRun]
    let visuals: [ModelCoachingVisualCue]

    var plainText: String { runs.map(\.text).joined() }
}
