import Foundation

enum ModelCoachingChessNativeTurnValidator {
    private static let maximumMessageWords = 18
    private static let maximumActions = 3
    private static let maximumFocus = 4

    static func issues(
        for turn: ModelCoachingChessNativeTurn,
        compilation: ModelCoachingChessNativeContextCompilation
    ) -> [String] {
        var issues: [String] = []

        if turn.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Message must not be empty.")
        } else {
            if wordCount(in: turn.message) > maximumMessageWords {
                issues.append("Message must be 18 words or fewer.")
            }
            if containsChessNotation(turn.message) {
                issues.append("Message must use ordinary language without chess notation.")
            }
        }

        let permittedActions = Set(compilation.availableActions)
        issues.append(contentsOf: unknownActions(in: turn.actions, permitted: permittedActions))
        issues.append(contentsOf: duplicateActions(in: turn.actions))
        if turn.actions.count > maximumActions {
            issues.append("Actions must contain at most 3 names.")
        }

        let permittedMoves = Set(compilation.availableMoveFocus)
        issues.append(contentsOf: invalidFocus(in: turn.focus, permittedMoves: permittedMoves))
        issues.append(contentsOf: duplicateFocus(in: turn.focus))
        if turn.focus.count > maximumFocus {
            issues.append("Focus must contain at most 4 objects.")
        }

        return issues
    }

    private static func unknownActions(
        in actions: [String],
        permitted: Set<String>
    ) -> [String] {
        var reported = Set<String>()
        return actions.compactMap { action in
            guard !permitted.contains(action), reported.insert(action).inserted else {
                return nil
            }
            return "Unavailable action: \(action)."
        }
    }

    private static func duplicateActions(in actions: [String]) -> [String] {
        var seen = Set<String>()
        var reported = Set<String>()
        return actions.compactMap { action in
            guard !seen.insert(action).inserted, reported.insert(action).inserted else {
                return nil
            }
            return "Duplicate action: \(action)."
        }
    }

    private static func invalidFocus(
        in focus: [ModelCoachingChessNativeFocus],
        permittedMoves: Set<ModelCoachingChessNativeMoveFocus>
    ) -> [String] {
        var reported = Set<ModelCoachingChessNativeFocus>()
        return focus.compactMap { item in
            guard reported.insert(item).inserted else {
                return nil
            }

            switch item {
            case .square(let square):
                guard !isBoardSquare(square) else {
                    return nil
                }
                return "Off-board focus square: \(square)."
            case .move(let from, let to):
                let move = ModelCoachingChessNativeMoveFocus(from: from, to: to)
                guard isBoardSquare(from), isBoardSquare(to), permittedMoves.contains(move) else {
                    return "Unavailable move focus: \(from)-\(to)."
                }
                return nil
            }
        }
    }

    private static func duplicateFocus(in focus: [ModelCoachingChessNativeFocus]) -> [String] {
        var seen = Set<ModelCoachingChessNativeFocus>()
        var reported = Set<ModelCoachingChessNativeFocus>()
        return focus.compactMap { item in
            guard !seen.insert(item).inserted, reported.insert(item).inserted else {
                return nil
            }
            return "Duplicate focus object: \(description(of: item))."
        }
    }

    private static func description(of focus: ModelCoachingChessNativeFocus) -> String {
        switch focus {
        case .square(let square):
            return "square \(square)"
        case .move(let from, let to):
            return "move \(from)-\(to)"
        }
    }

    private static func isBoardSquare(_ value: String) -> Bool {
        value.range(of: #"^[a-h][1-8]$"#, options: .regularExpression) != nil
    }

    private static func containsChessNotation(_ message: String) -> Bool {
        if message.contains("+") || message.contains("#") {
            return true
        }

        let patterns = [
            #"(?<![A-Za-z0-9])(?:O-O(?:-O)?|0-0(?:-0)?)(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])[KQRBN](?:[a-h1-8]{0,2})x?[a-h][1-8](?:=[QRBN])?(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])[a-h]x[a-h][1-8](?:=[QRBN])?(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])[a-h][18]=[QRBN](?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])[a-h][1-8][a-h][1-8][qrbn]?(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9])[a-h][1-8][-\u{2013}\u{2014}][a-h][1-8](?![A-Za-z0-9])"#,
            #"(?<![A-Za-z])[x](?![A-Za-z])"#,
            #"(?<![A-Za-z0-9])[KQRBNP](?![A-Za-z0-9])"#,
        ]
        return patterns.contains { pattern in
            message.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func wordCount(in message: String) -> Int {
        message.split(whereSeparator: { $0.isWhitespace }).count
    }
}

enum ModelCoachingChessNativeTurnDecodingError: Error, Equatable {
    case invalidTopLevelObject
    case additionalProperties([String])
    case invalidFocusObject(Int)
    case additionalFocusProperties(index: Int, properties: [String])
    case invalidTurnJSON
    case validationFailed([String])
}

enum ModelCoachingChessNativeTurnDecoder {
    private static let allowedProperties: Set<String> = [
        "message",
        "actions",
        "focus",
    ]

    static func decodeAndValidate(
        _ data: Data,
        compilation: ModelCoachingChessNativeContextCompilation
    ) throws -> ModelCoachingChessNativeTurn {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTurnJSON
        }

        guard let dictionary = object as? [String: Any] else {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTopLevelObject
        }

        let unknownProperties = Set(dictionary.keys)
            .subtracting(allowedProperties)
            .sorted()
        guard unknownProperties.isEmpty else {
            throw ModelCoachingChessNativeTurnDecodingError.additionalProperties(unknownProperties)
        }

        try validateRawFocus(dictionary["focus"])

        let turn: ModelCoachingChessNativeTurn
        do {
            turn = try JSONDecoder().decode(ModelCoachingChessNativeTurn.self, from: data)
        } catch {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTurnJSON
        }

        let issues = ModelCoachingChessNativeTurnValidator.issues(
            for: turn,
            compilation: compilation
        )
        guard issues.isEmpty else {
            throw ModelCoachingChessNativeTurnDecodingError.validationFailed(issues)
        }

        return turn
    }

    private static func validateRawFocus(_ rawFocus: Any?) throws {
        guard let rawFocus else {
            return
        }
        guard let focus = rawFocus as? [Any] else {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTurnJSON
        }

        for (index, rawItem) in focus.enumerated() {
            guard let item = rawItem as? [String: Any], let type = item["type"] as? String else {
                throw ModelCoachingChessNativeTurnDecodingError.invalidFocusObject(index)
            }

            let allowed: Set<String>
            switch type {
            case "square":
                allowed = ["type", "square"]
            case "move":
                allowed = ["type", "from", "to"]
            default:
                throw ModelCoachingChessNativeTurnDecodingError.invalidFocusObject(index)
            }

            let unknown = Set(item.keys).subtracting(allowed).sorted()
            guard unknown.isEmpty else {
                throw ModelCoachingChessNativeTurnDecodingError.additionalFocusProperties(
                    index: index,
                    properties: unknown
                )
            }
        }
    }
}
