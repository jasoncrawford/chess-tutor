import SwiftUI
import UIKit

/// One native paragraph: links may break across lines without changing the
/// baseline or reserving a button-sized rectangle in the middle of a sentence.
struct CoachingMessageView: View {
    let content: ModelCoachingVisualContent
    let board: Board
    var fontSize: CGFloat = 18
    var arrowDescription: String = ""
    let onReference: (Int) -> Void

    var body: some View {
        CoachingLinkedText(content: content, board: board, fontSize: fontSize,
                           arrowDescription: arrowDescription, onReference: onReference)
            .fixedSize(horizontal: false, vertical: true)
    }
}
/// TextKit supplies line wrapping, link hit testing and accessibility, including
/// when the physical table rotates the panel by a quarter turn.
private struct CoachingLinkedText: UIViewRepresentable {
    let content: ModelCoachingVisualContent
    let board: Board
    let fontSize: CGFloat
    let arrowDescription: String
    let onReference: (Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.linkTextAttributes = [.foregroundColor: UIColor(AppTheme.coachFocusRing),
                                   .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onReference = onReference
        let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withDesign(.rounded)!
        let font = UIFont(descriptor: descriptor, size: fontSize)
        let message = NSMutableAttributedString()
        for (index, run) in content.runs.enumerated() {
            let plainAttributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor(AppTheme.ink)
            ]
            var attributes = plainAttributes
            var words = run.text
            if run.referencedSquare != nil {
                attributes[.link] = URL(string: "coach-reference://\(index)")
            }
            if case .piece(_, let name) = run, let square = CoachingVisualAccessibility.square(name),
               let piece = board[square], let image = UIImage(named: piece.assetName) {
                // The model may put interword spacing in either neighboring run.
                // Keep that spacing before the icon, never between it and the noun.
                let leadingSpace = words.prefix(while: \.isWhitespace)
                message.append(NSAttributedString(string: String(leadingSpace), attributes: plainAttributes))
                words.removeFirst(leadingSpace.count)
                let icon = NSTextAttachment()
                icon.image = image
                // Center within the capital-height band, with the image fully
                // inside the font's ascent/descent so it cannot make a tall row.
                let height = font.pointSize
                icon.bounds = CGRect(x: 0, y: (font.capHeight - height) / 2,
                                     width: height * image.size.width / image.size.height, height: height)
                let attachment = NSMutableAttributedString(attachment: icon)
                attachment.addAttributes(attributes, range: NSRange(location: 0, length: attachment.length))
                message.append(attachment)
                // Keep the icon beside the first word, not the whole phrase.
                message.append(NSAttributedString(string: "\u{00a0}", attributes: attributes))
            }
            message.append(NSAttributedString(string: words, attributes: attributes))
        }
        if view.attributedText != message { view.attributedText = message }
        view.accessibilityHint = arrowDescription.isEmpty ? nil : arrowDescription
        view.accessibilityCustomActions = content.runs.enumerated().compactMap { index, run in
            guard run.referencedSquare != nil else { return nil }
            return UIAccessibilityCustomAction(name: "Highlight \(CoachingVisualAccessibility.reference(run, board: board))") { _ in
                onReference(index)
                return true
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReference: onReference) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onReference: (Int) -> Void
        init(onReference: @escaping (Int) -> Void) { self.onReference = onReference }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, url.scheme == "coach-reference",
                  let host = url.host, let index = Int(host) else { return nil }
            return UIAction { [weak self] _ in self?.onReference(index) }
        }
    }
}

/// Spoken equivalents of validated board gestures, without adding visible copy.
enum CoachingVisualAccessibility {
    static func reference(_ run: ModelCoachingVisualMessageRun, board: Board) -> String {
        guard let name = run.referencedSquare else { return "" }
        guard case .piece = run, let square = square(name) else { return "Square \(name)" }
        return piece(at: square, board: board)
    }

    static func arrow(_ path: CoachFocusPath?, board: Board, isStagedMove: Bool = false) -> String {
        guard let path else { return "" }
        let source = piece(at: path.source, board: board)
        let destination = ModelCoachingPositionEncoder.squareName(path.destination)
        if path.geometryKind == .relocation { return "Try \(source) at \(destination) instead." }
        if path.role == .attacker { return "\(source) attacks \(piece(at: path.destination, board: board))." }
        if isStagedMove {
            return "\(piece(at: path.destination, board: board)) moved from \(ModelCoachingPositionEncoder.squareName(path.source))."
        }
        return "Move \(source) to \(destination)."
    }

    private static func piece(at square: Square, board: Board) -> String {
        let name = ModelCoachingPositionEncoder.squareName(square)
        guard let piece = board[square] else { return "square \(name)" }
        return "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) on \(name)"
    }

    static func square(_ name: String) -> Square? {
        guard name.utf8.count == 2, let byte = name.utf8.first,
              let file = Square.File(rawValue: Int(byte) - 96),
              let rank = Int(String(name.suffix(1))), (1...8).contains(rank) else { return nil }
        return Square(file: file, rank: rank)
    }
}
