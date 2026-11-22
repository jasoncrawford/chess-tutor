import SwiftUI

/// Readable prose with native, local-only reference buttons. Each link has its
/// own 44-point layout box, so neighboring hit targets cannot overlap.
struct CoachingMessageView: View {
    let content: ModelCoachingVisualContent
    let board: Board
    let onReference: (Int) -> Void

    @ViewBuilder var body: some View {
        if !content.runs.contains(where: { $0.referencedSquare != nil }) {
            Text(content.plainText).fixedSize(horizontal: false, vertical: true)
        } else {
            linkedProse
        }
    }

    private var linkedProse: some View {
        CoachingProseLayout {
            ForEach(Array(content.runs.enumerated()), id: \.offset) { index, run in
                if let square = run.referencedSquare {
                    Button { onReference(index) } label: {
                        HStack(spacing: 3) {
                            if case .piece = run, let piece = piece(at: square) {
                                PieceIconView(piece: piece)
                                    .frame(width: 19, height: 25)
                                    .accessibilityHidden(true)
                            }
                            Text(run.text).underline().fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(AppTheme.coachFocusRing)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(run.text)
                    .accessibilityValue(CoachingVisualAccessibility.reference(run, board: board))
                    .accessibilityHint("Highlight on the board")
                    .accessibilityIdentifier("coach-reference-\(index)")
                } else {
                    ForEach(Array(run.text.split(separator: " ", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, word in
                        Text(String(word) + (index < run.text.split(separator: " ", omittingEmptySubsequences: false).count - 1 ? " " : ""))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(run.text)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func piece(at name: String) -> Piece? {
        guard name.utf8.count == 2, let byte = name.utf8.first,
              let file = Square.File(rawValue: Int(byte) - 96),
              let rank = Int(String(name.suffix(1))), (1...8).contains(rank) else { return nil }
        return board[Square(file: file, rank: rank)]
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

private struct CoachingProseLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 260, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, item) in result.items.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                  anchor: .topLeading, proposal: ProposedViewSize(item.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, items: [CGRect]) {
        var items: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        var lineStart = 0
        func alignLine() {
            for i in lineStart..<items.count { items[i].origin.y += (lineHeight - items[i].height) / 2 }
        }
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                alignLine()
                y += lineHeight
                x = 0; lineHeight = 0; lineStart = items.count
            }
            items.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        alignLine()
        return (CGSize(width: width, height: y + lineHeight), items)
    }
}
