import SwiftUI

struct PieceIconView: View {
    let piece: Piece

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .scaledToFit()
            .padding(.vertical, 2)
            .shadow(color: shadowColor, radius: 3, x: 0, y: 2)
            .accessibilityLabel("\(piece.color.rawValue) \(piece.kind.rawValue)")
    }

    private var shadowColor: Color {
        switch piece.color {
        case .white:
            .black.opacity(0.20)
        case .black:
            .black.opacity(0.26)
        }
    }
}
