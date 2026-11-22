import SwiftUI
import UIKit

/// One native paragraph: links may break across lines without changing the
/// baseline or reserving a button-sized rectangle in the middle of a sentence.
struct CoachingMessageView: View {
    let content: ModelCoachingVisualContent
    let board: Board
    var fontSize: CGFloat = 18
    let onReference: (Int) -> Void

    var body: some View {
        CoachingLinkedText(content: content, board: board, fontSize: fontSize, onReference: onReference)
            .fixedSize(horizontal: false, vertical: true)
    }
}
/// TextKit supplies line wrapping, link hit testing and accessibility, including
/// when the physical table rotates the panel by a quarter turn.
private struct CoachingLinkedText: UIViewRepresentable {
    let content: ModelCoachingVisualContent
    let board: Board
    let fontSize: CGFloat
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
        let message = NSMutableAttributedString()
        for (index, run) in content.runs.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(descriptor: descriptor, size: fontSize), .foregroundColor: UIColor(AppTheme.ink)
            ]
            if run.referencedSquare != nil {
                attributes[.link] = URL(string: "coach-reference://\(index)")
            }
            message.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        if view.attributedText != message { view.attributedText = message }
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

    static func arrow(_ path: CoachFocusPath?, board: Board) -> String {
        guard let path else { return "" }
        let source = piece(at: path.source, board: board)
        let destination = ModelCoachingPositionEncoder.squareName(path.destination)
        if path.geometryKind == .relocation { return "Try \(source) at \(destination) instead." }
        if path.role == .attacker { return "\(source) attacks \(piece(at: path.destination, board: board))." }
        return "Move \(source) to \(destination)."
    }

    private static func piece(at square: Square, board: Board) -> String {
        let name = ModelCoachingPositionEncoder.squareName(square)
        guard let piece = board[square] else { return "square \(name)" }
        return "\(piece.color.rawValue.capitalized) \(piece.kind.rawValue) on \(name)"
    }

    private static func square(_ name: String) -> Square? {
        guard name.utf8.count == 2, let byte = name.utf8.first,
              let file = Square.File(rawValue: Int(byte) - 96),
              let rank = Int(String(name.suffix(1))), (1...8).contains(rank) else { return nil }
        return Square(file: file, rank: rank)
    }
}
