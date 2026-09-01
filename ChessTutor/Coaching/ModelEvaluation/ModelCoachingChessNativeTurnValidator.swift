import Foundation

enum ModelCoachingChessNativeTurnValidator {
    private static let maximumMessageWords = 18
    private static let maximumActions = 3
    private static let maximumFocus = 4

    static func issues(
        for turn: ModelCoachingChessNativeTurn,
        compilation: ModelCoachingChessNativeContextCompilation
    ) -> [String] {
        issues(
            for: turn,
            contract: ModelCoachingChessNativeResponseContract(
                availableActions: compilation.availableActions,
                availableMoveFocus: compilation.availableMoveFocus
            )
        )
    }

    static func issues(
        for turn: ModelCoachingChessNativeTurn,
        contract: ModelCoachingChessNativeResponseContract
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

        let permittedActions = Set(contract.availableActions)
        issues.append(contentsOf: unknownActions(in: turn.actions, permitted: permittedActions))
        issues.append(contentsOf: duplicateActions(in: turn.actions))
        if turn.actions.count > maximumActions {
            issues.append("Actions must contain at most 3 names.")
        }

        let permittedMoves = Set(contract.availableMoveFocus)
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
        let normalizedMessage = message
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )

        if normalizedMessage.contains("+") || normalizedMessage.contains("#") {
            return true
        }

        let figurines = CharacterSet(charactersIn: "♔♕♖♗♘♙♚♛♜♝♞♟")
        if normalizedMessage.rangeOfCharacter(from: figurines) != nil {
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
            normalizedMessage.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
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
    case duplicateObjectKey(String)
    case invalidTurnJSON
    case validationFailed([String])
}

enum ModelCoachingChessNativeTurnDecoder {
    private static let allowedProperties: Set<String> = [
        "message",
        "actions",
        "focus",
        "expects",
    ]

    static func decodeAndValidate(
        _ data: Data,
        compilation: ModelCoachingChessNativeContextCompilation,
        requiresExpectedResponse: Bool = false
    ) throws -> ModelCoachingChessNativeTurn {
        try decodeAndValidate(
            data,
            contract: ModelCoachingChessNativeResponseContract(
                availableActions: compilation.availableActions,
                availableMoveFocus: compilation.availableMoveFocus
            ),
            requiresExpectedResponse: requiresExpectedResponse
        )
    }

    static func decodeAndValidate(
        _ data: Data,
        contract: ModelCoachingChessNativeResponseContract,
        requiresExpectedResponse: Bool = false
    ) throws -> ModelCoachingChessNativeTurn {
        do {
            var validator = ModelCoachingRawJSONValidator(data: data)
            try validator.validate()
        } catch ModelCoachingRawJSONValidator.ValidationError.duplicateObjectKey(let key) {
            throw ModelCoachingChessNativeTurnDecodingError.duplicateObjectKey(key)
        } catch {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTurnJSON
        }

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
        if requiresExpectedResponse, dictionary["expects"] == nil {
            throw ModelCoachingChessNativeTurnDecodingError.invalidTurnJSON
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
            contract: contract
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

struct ModelCoachingRawJSONValidator {
    enum ValidationError: Error {
        case malformed
        case duplicateObjectKey(String)
    }

    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw ValidationError.malformed
        }
    }

    private mutating func parseValue() throws {
        skipWhitespace()
        guard let byte = currentByte else {
            throw ValidationError.malformed
        }

        switch byte {
        case 0x7B:
            try parseObject()
        case 0x5B:
            try parseArray()
        case 0x22:
            _ = try parseString()
        case 0x74:
            try consumeLiteral("true")
        case 0x66:
            try consumeLiteral("false")
        case 0x6E:
            try consumeLiteral("null")
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw ValidationError.malformed
        }
    }

    private mutating func parseObject() throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) {
            return
        }

        var keys = Set<String>()
        while true {
            guard currentByte == 0x22 else {
                throw ValidationError.malformed
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw ValidationError.duplicateObjectKey(key)
            }

            skipWhitespace()
            guard consume(0x3A) else {
                throw ValidationError.malformed
            }
            try parseValue()
            skipWhitespace()

            if consume(0x7D) {
                return
            }
            guard consume(0x2C) else {
                throw ValidationError.malformed
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) {
            return
        }

        while true {
            try parseValue()
            skipWhitespace()
            if consume(0x5D) {
                return
            }
            guard consume(0x2C) else {
                throw ValidationError.malformed
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        guard consume(0x22) else {
            throw ValidationError.malformed
        }

        while let byte = currentByte {
            switch byte {
            case 0x22:
                index += 1
                let encodedString = Data(bytes[start..<index])
                do {
                    return try JSONDecoder().decode(String.self, from: encodedString)
                } catch {
                    throw ValidationError.malformed
                }
            case 0x5C:
                index += 1
                try parseEscapeSequence()
            case 0x00...0x1F:
                throw ValidationError.malformed
            default:
                index += 1
            }
        }

        throw ValidationError.malformed
    }

    private mutating func parseEscapeSequence() throws {
        guard let escape = currentByte else {
            throw ValidationError.malformed
        }

        switch escape {
        case 0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
            index += 1
        case 0x75:
            index += 1
            guard index + 4 <= bytes.count,
                  bytes[index..<(index + 4)].allSatisfy(isHexDigit) else {
                throw ValidationError.malformed
            }
            index += 4
        default:
            throw ValidationError.malformed
        }
    }

    private mutating func parseNumber() throws {
        _ = consume(0x2D)

        if consume(0x30) {
            guard currentByte.map({ !isDigit($0) }) ?? true else {
                throw ValidationError.malformed
            }
        } else {
            guard let byte = currentByte, (0x31...0x39).contains(byte) else {
                throw ValidationError.malformed
            }
            index += 1
            while let byte = currentByte, isDigit(byte) {
                index += 1
            }
        }

        if consume(0x2E) {
            try consumeDigits()
        }

        if currentByte == 0x65 || currentByte == 0x45 {
            index += 1
            if currentByte == 0x2B || currentByte == 0x2D {
                index += 1
            }
            try consumeDigits()
        }
    }

    private mutating func consumeDigits() throws {
        guard let byte = currentByte, isDigit(byte) else {
            throw ValidationError.malformed
        }
        while let byte = currentByte, isDigit(byte) {
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            guard consume(byte) else {
                throw ValidationError.malformed
            }
        }
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func consume(_ expected: UInt8) -> Bool {
        guard currentByte == expected else {
            return false
        }
        index += 1
        return true
    }

    private var currentByte: UInt8? {
        guard index < bytes.count else {
            return nil
        }
        return bytes[index]
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }

    private func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
            || (0x41...0x46).contains(byte)
            || (0x61...0x66).contains(byte)
    }
}
