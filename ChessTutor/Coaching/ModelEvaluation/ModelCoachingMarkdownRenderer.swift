import Foundation

enum ModelCoachingMarkdownRenderer {
    static func render(_ document: ModelCoachingContextDocument) -> String {
        var blocks = ["# Chess coaching context"]

        if !document.metadataLines.isEmpty {
            blocks.append(document.metadataLines.joined(separator: "\n"))
        }

        for section in document.sections {
            let heading = section.heading.hasPrefix("#")
                ? section.heading
                : "## \(section.heading)"
            let body = section.lines.map { line in
                line.hasPrefix("```") ? line : sanitize(line)
            }.joined(separator: "\n")
            blocks.append(body.isEmpty ? heading : "\(heading)\n\n\(body)")
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func sanitize(_ text: String) -> String {
        let escapedBackticks = text.replacingOccurrences(of: "`", with: "\\`")
        let scalars = escapedBackticks.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) ? " " : Character(String(scalar))
        }
        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
