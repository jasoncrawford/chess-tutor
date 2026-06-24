import SwiftUI

struct MoveHistoryView: View {
    let moves: [Move]

    var body: some View {
        List(Array(moves.enumerated()), id: \.offset) { index, move in
            Text(verbatim: "\(index + 1). \(move.from.file)\(move.from.rank) → \(move.to.file)\(move.to.rank)")
        }
    }
}
