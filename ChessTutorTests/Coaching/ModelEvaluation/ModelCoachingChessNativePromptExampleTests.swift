import CryptoKit
import Foundation
import XCTest
@testable import ChessTutor

final class ModelCoachingChessNativePromptExampleTests: XCTestCase {
    private let expectedIDs = [
        "01-quiet-help",
        "02-attacked-piece",
        "03-selected-piece",
        "04-replaced-tentative-move",
        "05-tactical-reply",
        "06-inspected-reply",
        "07-answering-check",
        "08-long-history",
    ]

    func testArtifactsUseExactlyEightCanonicalFixturesAndAreDeterministic() throws {
        let first = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        let second = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        let records = try decodeRecords(first.examplesJSONL)

        XCTAssertEqual(first, second)
        XCTAssertEqual(records.count, 8)
        XCTAssertEqual(records.map(\.id), expectedIDs)
        XCTAssertEqual(Set(records.map(\.id)).count, 8)
        XCTAssertEqual(records.map(\.id), ModelCoachingNeutralPromptExamples.fixtures.map(\.id))
        XCTAssertEqual(
            first.userPrompts.keys.sorted(),
            expectedIDs.map { "\($0).md" }
        )
        XCTAssertEqual(
            first.systemPrompt,
            try Data(contentsOf: repositoryRoot.appendingPathComponent("Tools/CoachingEval/prompts/tutor-v6.md"))
        )
    }

    func testArtifactsCarryExactRequestsCompilationsAndUniqueHashes() throws {
        let artifacts = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        let records = try decodeRecords(artifacts.examplesJSONL)
        let systemHash = sha256(artifacts.systemPrompt)

        for (fixture, record) in zip(ModelCoachingNeutralPromptExamples.fixtures, records) {
            let expectedRequest = ModelCoachingNeutralRequestBuilder.build(
                snapshot: fixture.snapshot,
                requestID: fixture.id
            )
            let expectedCompilation = ModelCoachingChessNativeContextCompiler.compile(
                expectedRequest,
                promptVersion: "tutor-v6"
            )
            let userPrompt = try XCTUnwrap(artifacts.userPrompts[fixture.fileName])

            XCTAssertEqual(record.fileName, fixture.fileName)
            XCTAssertEqual(record.visibility, .visible)
            XCTAssertEqual(record.request, expectedRequest)
            XCTAssertEqual(record.compilation, expectedCompilation)
            XCTAssertEqual(record.compilation.promptVersion, "tutor-v6")
            XCTAssertEqual(userPrompt, Data(expectedCompilation.markdown.utf8))
            XCTAssertEqual(record.requestSHA256, sha256(try sortedJSON(expectedRequest)))
            XCTAssertEqual(record.systemPromptSHA256, systemHash)
            XCTAssertEqual(record.userPromptSHA256, sha256(userPrompt))
        }

        XCTAssertEqual(Set(records.map(\.requestSHA256)).count, 8)
        XCTAssertEqual(Set(records.map(\.userPromptSHA256)).count, 8)
        XCTAssertTrue(records.allSatisfy { $0.requestSHA256.count == 64 })
        XCTAssertTrue(records.allSatisfy { $0.systemPromptSHA256.count == 64 })
        XCTAssertTrue(records.allSatisfy { $0.userPromptSHA256.count == 64 })

        let manifest = try JSONDecoder().decode(
            ModelCoachingChessNativePromptPreviewManifest.self,
            from: artifacts.manifestJSON
        )
        XCTAssertEqual(manifest.schemaVersion, "model-coaching-chess-native-preview-manifest.v2")
        XCTAssertEqual(manifest.promptVersion, "tutor-v6")
        XCTAssertEqual(manifest.requestSchemaVersion, "model-coaching-neutral-request.v1")
        XCTAssertEqual(manifest.contextSchemaVersion, "model-coaching-chess-native-context.v1")
        XCTAssertEqual(manifest.exampleIDs, expectedIDs)
        XCTAssertEqual(manifest.systemPromptSHA256, systemHash)
        XCTAssertEqual(manifest.examplesJSONLSHA256, sha256(artifacts.examplesJSONL))
        XCTAssertEqual(manifest.examples, records.map {
            ModelCoachingChessNativePromptPreviewManifest.Example(
                id: $0.id,
                fileName: $0.fileName,
                requestSHA256: $0.requestSHA256,
                systemPromptSHA256: $0.systemPromptSHA256,
                userPromptSHA256: $0.userPromptSHA256
            )
        })
    }

    func testManifestInventoriesAuditOnlyAndModelFacingFilesByRole() throws {
        let manifest = try JSONDecoder().decode(
            ModelCoachingChessNativePromptPreviewManifest.self,
            from: ModelCoachingChessNativePromptExampleExporter.artifacts().manifestJSON
        )
        XCTAssertEqual(manifest.schemaVersion, "model-coaching-chess-native-preview-manifest.v2")

        XCTAssertEqual(
            manifest.declaredFiles,
            [
                .init(path: "examples.jsonl", role: .auditOnly),
                .init(path: "preview-manifest.json", role: .auditOnly),
                .init(path: "system-prompt.md", role: .modelFacingSystemMessage),
                .init(path: "user-prompts/01-quiet-help.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/02-attacked-piece.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/03-selected-piece.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/04-replaced-tentative-move.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/05-tactical-reply.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/06-inspected-reply.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/07-answering-check.md", role: .modelFacingUserMessage),
                .init(path: "user-prompts/08-long-history.md", role: .modelFacingUserMessage),
            ]
        )
        XCTAssertEqual(Set(manifest.declaredFiles.map(\.path)).count, 11)
        XCTAssertEqual(
            manifest.declaredFiles.filter { $0.role != .auditOnly }.map(\.path),
            ["system-prompt.md"] + expectedIDs.map { "user-prompts/\($0).md" }
        )
        XCTAssertTrue(
            manifest.declaredFiles
                .filter { $0.role != .auditOnly }
                .allSatisfy { $0.path.hasSuffix(".md") }
        )
        XCTAssertEqual(
            manifest.declaredFiles.first { $0.path == "examples.jsonl" }?.role,
            .auditOnly
        )
    }

    func testEveryCompleteHistoryReplaysToFENAndTentativeMoveStaysSeparate() throws {
        let records = try decodeRecords(
            ModelCoachingChessNativePromptExampleExporter.artifacts().examplesJSONL
        )

        for record in records {
            var replayedState = GameState.startingPosition()
            for historyMove in record.request.gameHistory {
                let legalMove = try XCTUnwrap(
                    LegalMoveGenerator.allLegalMoves(in: replayedState).first {
                        ModelCoachingPositionEncoder.canonicalMove($0) == historyMove.canonicalMove
                    },
                    "\(record.id): \(historyMove.canonicalMove) is not legal in replay order"
                )
                replayedState.apply(legalMove)
            }

            XCTAssertEqual(
                ModelCoachingPositionEncoder.fen(for: replayedState),
                record.request.position.fen,
                record.id
            )
            let positionLines = try sectionLines(named: "Position", in: record.compilation.markdown)
            let expectedHistoryLine =
                "Moves: \(record.request.gameHistory.isEmpty ? "none" : record.request.gameHistory.map(\.displayNotation).joined(separator: " "))"
            let expectedTentativeLine =
                "Tentative move: \(record.request.interaction.tentativeMove?.san ?? "none")"
            XCTAssertEqual(
                positionLines.filter { $0.hasPrefix("Moves:") },
                [expectedHistoryLine],
                record.id
            )
            XCTAssertEqual(
                positionLines.filter { $0.hasPrefix("Tentative move:") },
                [expectedTentativeLine],
                record.id
            )
        }
    }

    func testExactPositionLineAuditRejectsMergedTentativeMoveMutation() throws {
        let record = try XCTUnwrap(
            decodeRecords(ModelCoachingChessNativePromptExampleExporter.artifacts().examplesJSONL)
                .first { $0.id == "04-replaced-tentative-move" }
        )
        let historyLine = "Moves: e4 e5"
        let tentativeLine = "Tentative move: Nf3"
        let mutatedMarkdown = record.compilation.markdown.replacingOccurrences(
            of: historyLine,
            with: "\(historyLine) Nf3"
        )
        let mutatedPositionLines = try sectionLines(named: "Position", in: mutatedMarkdown)

        XCTAssertTrue(mutatedMarkdown.contains(historyLine))
        XCTAssertNotEqual(mutatedPositionLines.filter { $0.hasPrefix("Moves:") }, [historyLine])
        XCTAssertEqual(
            mutatedPositionLines.filter { $0.hasPrefix("Tentative move:") },
            [tentativeLine]
        )
    }

    func testExportContainsNoNumberedAliasesResponseTraceHiddenOrOracleData() throws {
        let artifacts = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        let aliasPattern = #"(?:relationship|move|piece|action)-[0-9]+"#
        let sourceText = String(decoding: artifacts.systemPrompt, as: UTF8.self)
            + String(decoding: artifacts.examplesJSONL, as: UTF8.self)
            + String(decoding: artifacts.manifestJSON, as: UTF8.self)
            + artifacts.userPrompts.values.map { String(decoding: $0, as: UTF8.self) }.joined()

        XCTAssertNil(sourceText.range(of: aliasPattern, options: .regularExpression))
        XCTAssertNil(ModelCoachingChessNativePromptArtifactAudit.hiddenIdentifier(in: sourceText))
        XCTAssertFalse(sourceText.lowercased().contains("oracle"))

        let records = try jsonValues(inJSONL: artifacts.examplesJSONL)
        let manifest = try JSONSerialization.jsonObject(with: artifacts.manifestJSON)
        assertNoForbiddenKeys(in: records)
        assertNoForbiddenKeys(in: manifest)
    }

    func testHiddenIdentifierAuditDetectsLiteralKnownAndPatternMutations() {
        let mutations = [
            "HIDDEN-case",
            "t1OutsidePawnMove",
            "t3WrongAttacker",
            "t7UnsafeCapture",
            "t12WrongChecker",
            "t99WrongChecker",
        ]

        for mutation in mutations {
            XCTAssertNotNil(
                ModelCoachingChessNativePromptArtifactAudit.hiddenIdentifier(
                    in: "{\"id\":\"\(mutation)\"}"
                ),
                mutation
            )
        }
    }

    func testModelFacingUserPromptsUnconditionallyOmitConclusionBearingProse() throws {
        let artifacts = try ModelCoachingChessNativePromptExampleExporter.artifacts()

        for (fileName, data) in artifacts.userPrompts {
            XCTAssertNil(
                ModelCoachingChessNativePromptArtifactAudit.conclusionBearingPhrase(
                    in: String(decoding: data, as: UTF8.self)
                ),
                fileName
            )
        }
    }

    func testConclusionBearingAuditDetectsEveryForbiddenPhraseMutation() {
        for phrase in ModelCoachingChessNativePromptArtifactAudit.conclusionBearingPhrases {
            XCTAssertEqual(
                ModelCoachingChessNativePromptArtifactAudit.conclusionBearingPhrase(
                    in: "Authored conclusion: \(phrase)."
                ),
                phrase
            )
        }
    }

    func testExample06IsCompactAndOmitsDownstreamRelationships() throws {
        let artifacts = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        let promptData = try XCTUnwrap(artifacts.userPrompts["06-inspected-reply.md"])
        let prompt = String(decoding: promptData, as: UTF8.self)
        let source = String(decoding: artifacts.systemPrompt, as: UTF8.self) + "\n" + prompt

        XCTAssertEqual(occurrences(of: "Qxe4+", in: prompt), 1)
        XCTAssertEqual(occurrences(of: "Qxf2+", in: prompt), 1)
        XCTAssertEqual(occurrences(of: "Qxh2", in: prompt), 1)
        XCTAssertFalse(prompt.lowercased().contains("relationship"))
        XCTAssertFalse(prompt.lowercased().contains("after reply"))
        XCTAssertFalse(prompt.lowercased().contains("downstream"))
        XCTAssertLessThan(source.split(whereSeparator: { $0.isWhitespace }).count, 1_500)
    }

    func testArtifactsRejectAnyNoncanonicalFixtureSet() throws {
        let fixture = try XCTUnwrap(ModelCoachingNeutralPromptExamples.fixtures.first)
        let renamed = ModelCoachingNeutralPromptFixture(
            id: "09-extra-case",
            fileName: "09-extra-case.md",
            visibility: .visible,
            snapshot: fixture.snapshot
        )

        XCTAssertThrowsError(
            try ModelCoachingChessNativePromptExampleExporter.artifacts(fixtures: [renamed])
        ) { error in
            XCTAssertEqual(error as? ModelCoachingChessNativePromptExportError, .invalidFixtureSet)
        }
        XCTAssertThrowsError(
            try ModelCoachingChessNativePromptExampleExporter.artifacts(
                fixtures: Array(ModelCoachingNeutralPromptExamples.fixtures.reversed())
            )
        ) { error in
            XCTAssertEqual(error as? ModelCoachingChessNativePromptExportError, .invalidFixtureSet)
        }
    }

    func testWriterRefusesToOverwriteNonemptyDestination() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chess-native-preview-nonempty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try Data("keep".utf8).write(to: outputURL.appendingPathComponent("existing.txt"))

        XCTAssertThrowsError(
            try ModelCoachingChessNativePromptExampleExporter.write(to: outputURL)
        ) { error in
            XCTAssertEqual(error as? ModelCoachingChessNativePromptExportError, .nonemptyOutputDirectory)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputURL.path), ["existing.txt"])
    }

    func testWriterProducesRelativeInventoryFromAbsoluteSymlinkedTemporaryPath() throws {
        let outputURL = URL(
            fileURLWithPath: "/tmp/chess-native-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try ModelCoachingChessNativePromptExampleExporter.write(to: outputURL)

        XCTAssertEqual(
            try relativeFilePaths(in: outputURL),
            [
                "examples.jsonl",
                "preview-manifest.json",
                "system-prompt.md",
                "user-prompts/01-quiet-help.md",
                "user-prompts/02-attacked-piece.md",
                "user-prompts/03-selected-piece.md",
                "user-prompts/04-replaced-tentative-move.md",
                "user-prompts/05-tactical-reply.md",
                "user-prompts/06-inspected-reply.md",
                "user-prompts/07-answering-check.md",
                "user-prompts/08-long-history.md",
            ]
        )
    }

    func testOptInWriterProducesExactlyElevenDeclaredByteIdenticalFiles() throws {
        let artifacts = try ModelCoachingChessNativePromptExampleExporter.artifacts()
        guard let outputPath = configuredValue(
            "COACHING_CHESS_NATIVE_PREVIEW_DIR",
            in: ProcessInfo.processInfo.environment
        ) else {
            return
        }
        let outputURL = outputPath.hasPrefix("/")
            ? URL(fileURLWithPath: outputPath, isDirectory: true)
            : repositoryRoot.appendingPathComponent(outputPath, isDirectory: true)

        try ModelCoachingChessNativePromptExampleExporter.write(to: outputURL)

        XCTAssertEqual(
            try relativeFilePaths(in: outputURL),
            [
                "examples.jsonl",
                "preview-manifest.json",
                "system-prompt.md",
                "user-prompts/01-quiet-help.md",
                "user-prompts/02-attacked-piece.md",
                "user-prompts/03-selected-piece.md",
                "user-prompts/04-replaced-tentative-move.md",
                "user-prompts/05-tactical-reply.md",
                "user-prompts/06-inspected-reply.md",
                "user-prompts/07-answering-check.md",
                "user-prompts/08-long-history.md",
            ]
        )
        XCTAssertEqual(try Data(contentsOf: outputURL.appendingPathComponent("examples.jsonl")), artifacts.examplesJSONL)
        XCTAssertEqual(
            try Data(contentsOf: outputURL.appendingPathComponent("preview-manifest.json")),
            artifacts.manifestJSON
        )
        XCTAssertEqual(try Data(contentsOf: outputURL.appendingPathComponent("system-prompt.md")), artifacts.systemPrompt)

        for (fileName, expectedData) in artifacts.userPrompts {
            let exportedData = try Data(
                contentsOf: outputURL.appendingPathComponent("user-prompts/\(fileName)")
            )
            XCTAssertEqual(exportedData, expectedData)
        }
    }

    private func decodeRecords(_ data: Data) throws -> [ModelCoachingChessNativePromptExampleRecord] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map {
                try JSONDecoder().decode(
                    ModelCoachingChessNativePromptExampleRecord.self,
                    from: Data($0.utf8)
                )
            }
    }

    private func jsonValues(inJSONL data: Data) throws -> [Any] {
        try String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
    }

    private func sectionLines(named heading: String, in markdown: String) throws -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        let headingIndex = try XCTUnwrap(lines.firstIndex(of: "## \(heading)"))
        let nextHeadingIndex = lines[(headingIndex + 1)...]
            .firstIndex { $0.hasPrefix("## ") }
            ?? lines.endIndex
        return lines[(headingIndex + 1)..<nextHeadingIndex].filter { !$0.isEmpty }
    }

    private func assertNoForbiddenKeys(
        in value: Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lowered = key.lowercased()
                XCTAssertFalse(lowered.contains("response"), "forbidden key: \(key)", file: file, line: line)
                XCTAssertFalse(lowered.contains("output"), "forbidden key: \(key)", file: file, line: line)
                XCTAssertFalse(lowered.contains("trace"), "forbidden key: \(key)", file: file, line: line)
                XCTAssertFalse(lowered.contains("hidden"), "forbidden key: \(key)", file: file, line: line)
                XCTAssertFalse(lowered.contains("oracle"), "forbidden key: \(key)", file: file, line: line)
                assertNoForbiddenKeys(in: child, file: file, line: line)
            }
        } else if let array = value as? [Any] {
            for child in array {
                assertNoForbiddenKeys(in: child, file: file, line: line)
            }
        }
    }

    private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func configuredValue(_ key: String, in environment: [String: String]) -> String? {
        guard let value = environment[key], !value.isEmpty, !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    private func relativeFilePaths(in directory: URL) throws -> [String] {
        let normalizedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedDirectoryPrefix = normalizedDirectory.path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: normalizedDirectory,
                includingPropertiesForKeys: keys
            )
        )
        return try enumerator.compactMap { element -> String? in
            let url = try XCTUnwrap(element as? URL)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else {
                return nil
            }
            return String(try XCTUnwrap(url.path.removingPrefix(normalizedDirectoryPrefix)))
        }.sorted()
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

enum ModelCoachingChessNativePromptArtifactAudit {
    static let conclusionBearingPhrases = [
        "best",
        "useful",
        "important",
        "purpose",
        "needs help",
        "looks safe",
        "what to teach",
        "selected move ideas",
        "danger scan",
        "safe captures",
    ]

    private static let legacyHiddenIdentifierPattern =
        #"t[0-9]+(?:OutsidePawnMove|WrongAttacker|UnsafeCapture|WrongChecker)"#

    static func hiddenIdentifier(in text: String) -> String? {
        if let range = text.range(of: "hidden", options: .caseInsensitive) {
            return String(text[range])
        }
        guard let range = text.range(
            of: legacyHiddenIdentifierPattern,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        return String(text[range])
    }

    static func conclusionBearingPhrase(in text: String) -> String? {
        let lowered = text.lowercased()
        return conclusionBearingPhrases.first { lowered.contains($0) }
    }
}

struct ModelCoachingChessNativePromptExampleRecord: Codable, Equatable {
    let id: String
    let fileName: String
    let visibility: ModelCoachingNeutralPromptExampleVisibility
    let request: ModelCoachingNeutralRequest
    let compilation: ModelCoachingChessNativeContextCompilation
    let requestSHA256: String
    let systemPromptSHA256: String
    let userPromptSHA256: String
}

struct ModelCoachingChessNativePromptPreviewManifest: Codable, Equatable {
    struct Example: Codable, Equatable {
        let id: String
        let fileName: String
        let requestSHA256: String
        let systemPromptSHA256: String
        let userPromptSHA256: String
    }

    struct DeclaredFile: Codable, Equatable {
        enum Role: String, Codable, Equatable {
            case auditOnly
            case modelFacingSystemMessage
            case modelFacingUserMessage
        }

        let path: String
        let role: Role
    }

    let schemaVersion: String
    let promptVersion: String
    let requestSchemaVersion: String
    let contextSchemaVersion: String
    let exampleIDs: [String]
    let systemPromptSHA256: String
    let examplesJSONLSHA256: String
    let examples: [Example]
    let declaredFiles: [DeclaredFile]
}

struct ModelCoachingChessNativePromptExampleArtifacts: Equatable {
    let examplesJSONL: Data
    let manifestJSON: Data
    let systemPrompt: Data
    let userPrompts: [String: Data]
}

enum ModelCoachingChessNativePromptExportError: Error, Equatable {
    case invalidFixtureSet
    case nonemptyOutputDirectory
    case outputPathIsNotDirectory
}

enum ModelCoachingChessNativePromptExampleExporter {
    static func artifacts(
        fixtures: [ModelCoachingNeutralPromptFixture] = ModelCoachingNeutralPromptExamples.fixtures
    ) throws -> ModelCoachingChessNativePromptExampleArtifacts {
        guard fixtures == ModelCoachingNeutralPromptExamples.fixtures else {
            throw ModelCoachingChessNativePromptExportError.invalidFixtureSet
        }

        return try ModelCoachingChessNativePromptArtifactFactory.artifacts(fixtures: fixtures)
    }

    static func write(to outputURL: URL) throws {
        try ModelCoachingChessNativePromptArtifactFactory.write(
            try artifacts(),
            to: outputURL
        )
    }
}

enum ModelCoachingChessNativePromptArtifactFactory {
    static func artifacts(
        fixtures: [ModelCoachingNeutralPromptFixture]
    ) throws -> ModelCoachingChessNativePromptExampleArtifacts {
        let systemPrompt = try Data(contentsOf: systemPromptURL)
        let systemPromptSHA256 = sha256(systemPrompt)
        var records: [ModelCoachingChessNativePromptExampleRecord] = []
        var userPrompts: [String: Data] = [:]

        for fixture in fixtures {
            let request = ModelCoachingNeutralRequestBuilder.build(
                snapshot: fixture.snapshot,
                requestID: fixture.id
            )
            let compilation = ModelCoachingChessNativeContextCompiler.compile(
                request,
                promptVersion: "tutor-v6"
            )
            let userPrompt = Data(compilation.markdown.utf8)
            let record = ModelCoachingChessNativePromptExampleRecord(
                id: fixture.id,
                fileName: fixture.fileName,
                visibility: fixture.visibility,
                request: request,
                compilation: compilation,
                requestSHA256: sha256(try sortedJSON(request)),
                systemPromptSHA256: systemPromptSHA256,
                userPromptSHA256: sha256(userPrompt)
            )
            records.append(record)
            userPrompts[fixture.fileName] = userPrompt
        }

        let examplesJSONL = try jsonl(records)
        let manifest = ModelCoachingChessNativePromptPreviewManifest(
            schemaVersion: "model-coaching-chess-native-preview-manifest.v2",
            promptVersion: "tutor-v6",
            requestSchemaVersion: "model-coaching-neutral-request.v1",
            contextSchemaVersion: "model-coaching-chess-native-context.v1",
            exampleIDs: records.map(\.id),
            systemPromptSHA256: systemPromptSHA256,
            examplesJSONLSHA256: sha256(examplesJSONL),
            examples: records.map {
                ModelCoachingChessNativePromptPreviewManifest.Example(
                    id: $0.id,
                    fileName: $0.fileName,
                    requestSHA256: $0.requestSHA256,
                    systemPromptSHA256: $0.systemPromptSHA256,
                    userPromptSHA256: $0.userPromptSHA256
                )
            },
            declaredFiles: declaredFiles(for: records)
        )
        var manifestJSON = try sortedJSON(manifest)
        manifestJSON.append(0x0A)

        return ModelCoachingChessNativePromptExampleArtifacts(
            examplesJSONL: examplesJSONL,
            manifestJSON: manifestJSON,
            systemPrompt: systemPrompt,
            userPrompts: userPrompts
        )
    }

    static func write(
        _ artifacts: ModelCoachingChessNativePromptExampleArtifacts,
        to outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        let outputURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ModelCoachingChessNativePromptExportError.outputPathIsNotDirectory
            }
            guard try fileManager.contentsOfDirectory(atPath: outputURL.path).isEmpty else {
                throw ModelCoachingChessNativePromptExportError.nonemptyOutputDirectory
            }
        } else {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        let userPromptsURL = outputURL.appendingPathComponent("user-prompts", isDirectory: true)
        try fileManager.createDirectory(at: userPromptsURL, withIntermediateDirectories: false)
        try artifacts.examplesJSONL.write(
            to: outputURL.appendingPathComponent("examples.jsonl"),
            options: .atomic
        )
        try artifacts.manifestJSON.write(
            to: outputURL.appendingPathComponent("preview-manifest.json"),
            options: .atomic
        )
        try artifacts.systemPrompt.write(
            to: outputURL.appendingPathComponent("system-prompt.md"),
            options: .atomic
        )
        for (fileName, data) in artifacts.userPrompts.sorted(by: { $0.key < $1.key }) {
            try data.write(to: userPromptsURL.appendingPathComponent(fileName), options: .atomic)
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var systemPromptURL: URL {
        repositoryRoot.appendingPathComponent("Tools/CoachingEval/prompts/tutor-v6.md")
    }

    private static func declaredFiles(
        for records: [ModelCoachingChessNativePromptExampleRecord]
    ) -> [ModelCoachingChessNativePromptPreviewManifest.DeclaredFile] {
        [
            .init(path: "examples.jsonl", role: .auditOnly),
            .init(path: "preview-manifest.json", role: .auditOnly),
            .init(path: "system-prompt.md", role: .modelFacingSystemMessage),
        ] + records.map {
            .init(path: "user-prompts/\($0.fileName)", role: .modelFacingUserMessage)
        }
    }

    private static func jsonl<T: Encodable>(_ values: [T]) throws -> Data {
        var data = Data()
        for value in values {
            data.append(try sortedJSON(value))
            data.append(0x0A)
        }
        return data
    }

    private static func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
