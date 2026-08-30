import Foundation

enum ModelCoachingNeutralTurnValidator {
    private static let maximumMessageWords = 18
    private static let maximumActions = 3
    private static let maximumFocusReferences = 4

    static func issues(
        for turn: ModelCoachingNeutralTurn,
        compilation: ModelCoachingNeutralContextCompilation
    ) -> [String] {
        var issues: [String] = []

        if turn.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Message must not be empty.")
        } else if wordCount(in: turn.message) > maximumMessageWords {
            issues.append("Message must be 18 words or fewer.")
        }

        let actionAliases = Set(
            compilation.referenceBindings
                .filter { $0.category == .action }
                .map(\.alias)
        )
        issues.append(contentsOf: unknownAliases(
            in: turn.actions,
            permitted: actionAliases,
            field: "action"
        ))
        issues.append(contentsOf: duplicateAliases(in: turn.actions, field: "action"))
        if turn.actions.count > maximumActions {
            issues.append("Actions must contain at most 3 aliases.")
        }

        let focusAliases = Set(
            compilation.referenceBindings
                .filter { $0.category != .action }
                .map(\.alias)
        )
        issues.append(contentsOf: unknownAliases(
            in: turn.focus,
            permitted: focusAliases,
            field: "focus"
        ))
        issues.append(contentsOf: duplicateAliases(in: turn.focus, field: "focus"))
        if turn.focus.count > maximumFocusReferences {
            issues.append("Focus must contain at most 4 aliases.")
        }

        return issues
    }

    private static func unknownAliases(
        in aliases: [String],
        permitted: Set<String>,
        field: String
    ) -> [String] {
        var reported = Set<String>()
        return aliases.compactMap { alias in
            guard !permitted.contains(alias), reported.insert(alias).inserted else {
                return nil
            }
            return "Unknown \(field) alias: \(alias)."
        }
    }

    private static func duplicateAliases(
        in aliases: [String],
        field: String
    ) -> [String] {
        var seen = Set<String>()
        var reported = Set<String>()
        return aliases.compactMap { alias in
            guard !seen.insert(alias).inserted, reported.insert(alias).inserted else {
                return nil
            }
            return "Duplicate \(field) alias: \(alias)."
        }
    }

    private static func wordCount(in message: String) -> Int {
        message.split(whereSeparator: { $0.isWhitespace }).count
    }
}

enum ModelCoachingNeutralTurnDecodingError: Error, Equatable {
    case invalidTopLevelObject
    case additionalProperties([String])
    case invalidTurnJSON
    case validationFailed([String])
}

enum ModelCoachingNeutralTurnDecoder {
    private static let allowedProperties: Set<String> = [
        "message",
        "actions",
        "focus",
    ]

    static func decodeAndValidate(
        _ data: Data,
        compilation: ModelCoachingNeutralContextCompilation
    ) throws -> ModelCoachingNeutralTurn {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ModelCoachingNeutralTurnDecodingError.invalidTurnJSON
        }

        guard let dictionary = object as? [String: Any] else {
            throw ModelCoachingNeutralTurnDecodingError.invalidTopLevelObject
        }

        let unknownProperties = Set(dictionary.keys)
            .subtracting(allowedProperties)
            .sorted()
        guard unknownProperties.isEmpty else {
            throw ModelCoachingNeutralTurnDecodingError.additionalProperties(unknownProperties)
        }

        let turn: ModelCoachingNeutralTurn
        do {
            turn = try JSONDecoder().decode(ModelCoachingNeutralTurn.self, from: data)
        } catch {
            throw ModelCoachingNeutralTurnDecodingError.invalidTurnJSON
        }

        let issues = ModelCoachingNeutralTurnValidator.issues(
            for: turn,
            compilation: compilation
        )
        guard issues.isEmpty else {
            throw ModelCoachingNeutralTurnDecodingError.validationFailed(issues)
        }

        return turn
    }
}
