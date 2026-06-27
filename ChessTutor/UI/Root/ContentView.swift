import SwiftUI

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?

    var body: some View {
        ZStack {
            AppTheme.table.ignoresSafeArea()
            HStack(alignment: .top, spacing: 28) {
                ChessBoardView(session: session) { result in
                    if case let .needsPromotion(from, to) = result {
                        pendingPromotion = PendingPromotion(from: from, to: to)
                    }
                }
                .frame(maxWidth: 760)
                sidePanel
                    .frame(width: 260)
                    .frame(minHeight: 240, alignment: .top)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .sheet(item: $pendingPromotion) { promotion in
            VStack(spacing: 16) {
                Text("Choose promotion")
                    .font(.title2.bold())
                ForEach([Piece.Kind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button(kind.rawValue.capitalized) {
                        session.promote(from: promotion.from, to: promotion.to, to: kind)
                        pendingPromotion = nil
                    }
                }
            }
            .padding()
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.statusText)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if let guidanceText = session.guidanceText {
                    Text(guidanceText)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, session.guidanceText == nil ? 0 : 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(session.guidanceText == nil ? Color.clear : Color.white.opacity(0.58))
            )

            GameControlsView(session: session)
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.panel)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        )
    }
}

private struct PendingPromotion: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
}

#Preview {
    ContentView()
}
