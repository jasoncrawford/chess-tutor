import SwiftUI

struct PieceIconView: View {
    let piece: Piece

    private var fill: Color {
        piece.color == .white ? AppTheme.whitePiece : AppTheme.blackPiece
    }

    private var stroke: Color {
        piece.color == .white ? AppTheme.boardFrame.opacity(0.72) : Color.black.opacity(0.82)
    }

    private var mark: Color {
        piece.color == .white ? AppTheme.boardFrame : AppTheme.whitePiece.opacity(0.92)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                VStack(spacing: -size * 0.02) {
                    top(size: size)
                        .frame(width: size * 0.54, height: size * 0.42)
                    Capsule()
                        .fill(fill)
                        .overlay(Capsule().stroke(stroke, lineWidth: size * 0.035))
                        .frame(width: size * 0.34, height: size * 0.26)
                    RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                        .fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: size * 0.10, style: .continuous).stroke(stroke, lineWidth: size * 0.035))
                        .frame(width: size * 0.70, height: size * 0.22)
                }

                Text(letter)
                    .font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
                    .foregroundStyle(mark.opacity(piece.kind == .pawn ? 0 : 1))
                    .offset(y: size * 0.08)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("\(piece.color.rawValue) \(piece.kind.rawValue)")
    }

    @ViewBuilder
    private func top(size: CGFloat) -> some View {
        switch piece.kind {
        case .king:
            ZStack {
                Circle()
                    .fill(fill)
                    .overlay(Circle().stroke(stroke, lineWidth: size * 0.035))
                Cross()
                    .fill(mark)
                    .frame(width: size * 0.24, height: size * 0.24)
                    .offset(y: -size * 0.02)
            }
        case .queen:
            ZStack {
                Crown()
                    .fill(fill)
                    .overlay(Crown().stroke(stroke, lineWidth: size * 0.035))
                Circle()
                    .fill(mark)
                    .frame(width: size * 0.09, height: size * 0.09)
                    .offset(y: -size * 0.13)
            }
        case .rook:
            RookTop()
                .fill(fill)
                .overlay(RookTop().stroke(stroke, lineWidth: size * 0.035))
        case .bishop:
            Teardrop()
                .fill(fill)
                .overlay(Teardrop().stroke(stroke, lineWidth: size * 0.035))
                .overlay {
                    Capsule()
                        .fill(mark)
                        .frame(width: size * 0.07, height: size * 0.26)
                        .rotationEffect(.degrees(34))
                }
        case .knight:
            KnightHead()
                .fill(fill)
                .overlay(KnightHead().stroke(stroke, lineWidth: size * 0.035))
        case .pawn:
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(stroke, lineWidth: size * 0.035))
        }
    }

    private var letter: String {
        switch piece.kind {
        case .king: "K"
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        case .pawn: ""
        }
    }
}

private struct Cross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        let arm = rect.width * 0.18
        path.addRoundedRect(in: CGRect(x: midX - arm / 2, y: rect.minY, width: arm, height: rect.height), cornerSize: CGSize(width: arm / 2, height: arm / 2))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: midY - arm / 2, width: rect.width, height: arm), cornerSize: CGSize(width: arm / 2, height: arm / 2))
        return path
    }
}

private struct Crown: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RookTop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = rect.width / 5
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.minY + rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + notch * 2, y: rect.minY + rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + notch * 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + notch * 3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + notch * 3, y: rect.minY + rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + notch * 4, y: rect.minY + rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + notch * 4, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Teardrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28),
            control2: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28)
        )
        return path
    }
}

private struct KnightHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.36))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
