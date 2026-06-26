import SwiftUI

struct MoveHistoryView: View {
    let moves: [Move]

    var body: some View {
        let rows = MoveHistoryFormatter.rows(for: moves)

        ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    Text("Moves will appear here.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                ForEach(rows) { row in
                    Text(row.displayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                            .fill(AppTheme.boardFrame.opacity(0.10))
                            .frame(height: 1)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
