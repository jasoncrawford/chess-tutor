import SwiftUI

struct CoverageSurfaceColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct BoardGuidanceStyle: Equatable {
    static let current = BoardGuidanceStyle(
        arrowheadLengthInCells: 0.14,
        pathLineWidthInCells: 0.028,
        ambientDangerBadgeScale: 0.28,
        prominentDangerBurstScale: 0.92,
        shieldScale: 0.22,
        supporterEchoScale: 0.94,
        coverageSideToMoveColor: CoverageSurfaceColor(
            red: 0.94,
            green: 0.78,
            blue: 0.37,
            alpha: 1
        ),
        coverageOtherSideColor: CoverageSurfaceColor(
            red: 0.86,
            green: 0.50,
            blue: 0.42,
            alpha: 1
        ),
        coverageNeitherColor: CoverageSurfaceColor(
            red: 0.50,
            green: 0.51,
            blue: 0.47,
            alpha: 1
        ),
        coverageGridLineWidth: 0.75,
        coverageGridOpacity: 0.18,
        coverageRecessedPieceOpacity: 0.68,
        coverageTransitionDuration: 0.18
    )

    let arrowheadLengthInCells: CGFloat
    let pathLineWidthInCells: CGFloat
    let ambientDangerBadgeScale: CGFloat
    let prominentDangerBurstScale: CGFloat
    let shieldScale: CGFloat
    let supporterEchoScale: CGFloat
    let coverageSideToMoveColor: CoverageSurfaceColor
    let coverageOtherSideColor: CoverageSurfaceColor
    let coverageNeitherColor: CoverageSurfaceColor
    let coverageGridLineWidth: CGFloat
    let coverageGridOpacity: Double
    let coverageRecessedPieceOpacity: Double
    let coverageTransitionDuration: Double
}

enum CoverageSurfaceState: Equatable {
    case neither
    case sideToMoveOnly
    case otherSideOnly
    case both

    init(sideToMoveCovers: Bool, otherSideCovers: Bool) {
        switch (sideToMoveCovers, otherSideCovers) {
        case (false, false):
            self = .neither
        case (true, false):
            self = .sideToMoveOnly
        case (false, true):
            self = .otherSideOnly
        case (true, true):
            self = .both
        }
    }
}

struct CoverageDiagonalHalfShape: Shape {
    enum Half {
        case sideToMove
        case otherSide
    }

    let half: Half

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch half {
        case .sideToMove:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .otherSide:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

struct CoverageSurfaceView: View {
    let state: CoverageSurfaceState

    var body: some View {
        let style = BoardGuidanceStyle.current

        switch state {
        case .neither:
            Rectangle()
                .fill(style.coverageNeitherColor.color)
        case .sideToMoveOnly:
            Rectangle()
                .fill(style.coverageSideToMoveColor.color)
        case .otherSideOnly:
            Rectangle()
                .fill(style.coverageOtherSideColor.color)
        case .both:
            ZStack {
                CoverageDiagonalHalfShape(half: .sideToMove)
                    .fill(style.coverageSideToMoveColor.color)
                CoverageDiagonalHalfShape(half: .otherSide)
                    .fill(style.coverageOtherSideColor.color)
            }
        }
    }
}

struct CoverageGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1..<8 {
            let progress = CGFloat(index) / 8
            let x = rect.minX + rect.width * progress
            let y = rect.minY + rect.height * progress
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

struct CoverageGridView: View {
    var body: some View {
        let style = BoardGuidanceStyle.current
        CoverageGridShape()
            .stroke(
                AppTheme.boardFrame.opacity(style.coverageGridOpacity),
                lineWidth: style.coverageGridLineWidth
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct CoverageMapRenderingPolicy: Equatable {
    let isCoverageVisible: Bool

    var showsCoordinates: Bool {
        !isCoverageVisible
    }

    var showsAmbientThreats: Bool {
        !isCoverageVisible
    }

    func pieceOpacity(isContextual: Bool) -> Double {
        guard isCoverageVisible, !isContextual else {
            return 1
        }
        return BoardGuidanceStyle.current.coverageRecessedPieceOpacity
    }
}

enum CoverageContext {
    static func squares(in guidance: BoardGuidancePresentation) -> Set<Square> {
        guard let selectedSquare = guidance.selectedSquare else {
            return []
        }

        var squares: Set<Square> = [selectedSquare]
        for path in guidance.selectedPaths {
            squares.insert(path.source)
            squares.insert(path.destination)
            if let captureSquare = path.captureSquare {
                squares.insert(captureSquare)
            }
        }
        squares.formUnion(guidance.supporterSquares)
        squares.formUnion(guidance.prominentThreatSquares)
        squares.formUnion(guidance.visibleDefenseSquares)
        return squares
    }
}

struct GuidancePathLayout: Equatable {
    let start: CGPoint
    let shaftEnd: CGPoint
    let tip: CGPoint
    let arrowhead: [CGPoint]
    let arrowheadLength: CGFloat
    let shaftLength: CGFloat

    static func make(from source: CGPoint, to destination: CGPoint, cellSize: CGFloat) -> GuidancePathLayout {
        let deltaX = destination.x - source.x
        let deltaY = destination.y - source.y
        let distance = hypot(deltaX, deltaY)
        guard distance > 0 else {
            return GuidancePathLayout(
                start: source,
                shaftEnd: source,
                tip: source,
                arrowhead: [source, source, source],
                arrowheadLength: 0,
                shaftLength: 0
            )
        }

        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let sourceInset = min(cellSize * 0.26, distance * 0.20)
        let destinationInset = min(cellSize * 0.30, distance * 0.22)
        let arrowheadLength = min(
            BoardGuidanceStyle.current.arrowheadLengthInCells * cellSize,
            max(0, distance - sourceInset - destinationInset) * 0.32
        )
        let start = CGPoint(
            x: source.x + unitX * sourceInset,
            y: source.y + unitY * sourceInset
        )
        let tip = CGPoint(
            x: destination.x - unitX * destinationInset,
            y: destination.y - unitY * destinationInset
        )
        let shaftEnd = CGPoint(
            x: tip.x - unitX * arrowheadLength,
            y: tip.y - unitY * arrowheadLength
        )
        let halfWidth = arrowheadLength * 0.48
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let left = CGPoint(
            x: shaftEnd.x + perpendicularX * halfWidth,
            y: shaftEnd.y + perpendicularY * halfWidth
        )
        let right = CGPoint(
            x: shaftEnd.x - perpendicularX * halfWidth,
            y: shaftEnd.y - perpendicularY * halfWidth
        )

        return GuidancePathLayout(
            start: start,
            shaftEnd: shaftEnd,
            tip: tip,
            arrowhead: [tip, left, right],
            arrowheadLength: arrowheadLength,
            shaftLength: hypot(shaftEnd.x - start.x, shaftEnd.y - start.y)
        )
    }
}

struct BoardGuidanceGeometry {
    let side: CGFloat
    let origin: CGPoint
    let viewingAngle: BoardViewingAngle

    var cellSize: CGFloat {
        side / 8
    }

    func center(of square: Square) -> CGPoint {
        let files = viewingAngle.files
        let ranks = viewingAngle.ranks
        guard let column = files.firstIndex(of: square.file),
              let row = ranks.firstIndex(of: square.rank) else {
            return origin
        }

        return CGPoint(
            x: origin.x + (CGFloat(column) + 0.5) * cellSize,
            y: origin.y + (CGFloat(row) + 0.5) * cellSize
        )
    }

    func origin(of square: Square) -> CGPoint {
        let center = center(of: square)
        return CGPoint(x: center.x - cellSize / 2, y: center.y - cellSize / 2)
    }

    func readableFootOffset(distance: CGFloat) -> CGPoint {
        let radians = viewingAngle.tableRotationDegrees * .pi / 180
        return CGPoint(
            x: sin(radians) * distance,
            y: cos(radians) * distance
        )
    }
}

enum BoardPieceMarkerLayer: Double, Equatable {
    case prominentDanger = 0
    case piece = 1
    case foregroundStatus = 2

    var zIndex: Double { rawValue }
}

struct BoardPieceMarkerLayout: Equatable {
    let prominentDangerCenter: CGPoint
    let ambientDangerCenter: CGPoint
    let defenseCenter: CGPoint

    static func make(
        pieceCenter: CGPoint,
        readableFootOffset: CGPoint
    ) -> BoardPieceMarkerLayout {
        let footCenter = CGPoint(
            x: pieceCenter.x + readableFootOffset.x,
            y: pieceCenter.y + readableFootOffset.y
        )
        return BoardPieceMarkerLayout(
            prominentDangerCenter: pieceCenter,
            ambientDangerCenter: footCenter,
            defenseCenter: footCenter
        )
    }
}

enum GuidancePathRenderingPolicy {
    private struct Ray: Hashable {
        let source: Square
        let role: BoardGuidancePath.Role
        let color: PieceColor
        let fileStep: Int
        let rankStep: Int
    }

    static func visiblePaths(
        in paths: Set<BoardGuidancePath>
    ) -> Set<BoardGuidancePath> {
        var farthestByRay: [Ray: BoardGuidancePath] = [:]

        for path in paths {
            let fileDelta = path.destination.file.rawValue - path.source.file.rawValue
            let rankDelta = path.destination.rank - path.source.rank
            let divisor = greatestCommonDivisor(abs(fileDelta), abs(rankDelta))
            let ray = Ray(
                source: path.source,
                role: path.role,
                color: path.color,
                fileStep: divisor == 0 ? 0 : fileDelta / divisor,
                rankStep: divisor == 0 ? 0 : rankDelta / divisor
            )

            guard let current = farthestByRay[ray] else {
                farthestByRay[ray] = path
                continue
            }
            if distanceSquared(of: path) > distanceSquared(of: current) {
                farthestByRay[ray] = path
            }
        }

        return Set(farthestByRay.values)
    }

    private static func distanceSquared(of path: BoardGuidancePath) -> Int {
        let fileDelta = path.destination.file.rawValue - path.source.file.rawValue
        let rankDelta = path.destination.rank - path.source.rank
        return fileDelta * fileDelta + rankDelta * rankDelta
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var dividend = lhs
        var divisor = rhs
        while divisor != 0 {
            let remainder = dividend % divisor
            dividend = divisor
            divisor = remainder
        }
        return dividend
    }
}

struct GuidancePathsLayer: View {
    let guidance: BoardGuidancePresentation
    let side: CGFloat
    let origin: CGPoint
    let viewingAngle: BoardViewingAngle

    var body: some View {
        let geometry = BoardGuidanceGeometry(
            side: side,
            origin: origin,
            viewingAngle: viewingAngle
        )
        let paths = GuidancePathRenderingPolicy.visiblePaths(
            in: guidance.selectedPaths
        ).sorted(by: pathOrder)

        Canvas { context, _ in
            for guidancePath in paths {
                let layout = GuidancePathLayout.make(
                    from: geometry.center(of: guidancePath.source),
                    to: geometry.center(of: guidancePath.destination),
                    cellSize: geometry.cellSize
                )
                guard layout.shaftLength > 0 else {
                    continue
                }

                let color = guidancePath.color == guidance.sideToMove
                    ? AppTheme.guidanceYellow
                    : AppTheme.guidanceRed
                let opacity = guidancePath.role == .attacker ? 0.92 : 0.72
                var shaft = Path()
                shaft.move(to: layout.start)
                shaft.addLine(to: layout.shaftEnd)
                context.stroke(
                    shaft,
                    with: .color(color.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: geometry.cellSize * BoardGuidanceStyle.current.pathLineWidthInCells,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                var head = Path()
                head.move(to: layout.arrowhead[0])
                head.addLine(to: layout.arrowhead[1])
                head.addLine(to: layout.arrowhead[2])
                head.closeSubpath()
                context.fill(head, with: .color(color.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pathOrder(_ lhs: BoardGuidancePath, _ rhs: BoardGuidancePath) -> Bool {
        if lhs.role != rhs.role {
            return lhs.role == .allowed
        }
        if lhs.source == rhs.source {
            if lhs.destination.rank == rhs.destination.rank {
                return lhs.destination.file.rawValue < rhs.destination.file.rawValue
            }
            return lhs.destination.rank < rhs.destination.rank
        }
        if lhs.source.rank == rhs.source.rank {
            return lhs.source.file.rawValue < rhs.source.file.rawValue
        }
        return lhs.source.rank < rhs.source.rank
    }
}

struct DangerBurstShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tipCount = 16
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.70
        var path = Path()

        for index in 0..<(tipCount * 2) {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / CGFloat(tipCount)
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

enum DangerBurstTreatment: Equatable {
    case ambient
    case prominent
}

struct DangerBurstView: View {
    let cellSize: CGFloat
    let treatment: DangerBurstTreatment
    let isVisible: Bool
    let reducesMotion: Bool

    var body: some View {
        DangerBurstShape()
            .fill(
                AppTheme.guidanceCoral.opacity(isProminent ? 0.76 : 0.58)
            )
            .overlay {
                DangerBurstShape()
                    .stroke(
                        AppTheme.guidanceRed.opacity(isProminent ? 0.88 : 0.70),
                        lineWidth: isProminent ? 1.2 : 1
                    )
            }
            .frame(width: cellSize * scale, height: cellSize * scale)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(reducesMotion ? 1 : (isVisible ? 1 : hiddenScale))
            .shadow(
                color: AppTheme.guidanceRed.opacity(isProminent ? 0.20 : 0.12),
                radius: isProminent ? 2 : 1,
                y: isProminent ? 1 : 0.5
            )
            .animation(
                reducesMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.28, dampingFraction: 0.84),
                value: isVisible
            )
            .transition(
                reducesMotion
                    ? .opacity
                    : .scale(scale: 0.84).combined(with: .opacity)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var isProminent: Bool {
        treatment == .prominent
    }

    private var scale: CGFloat {
        isProminent
            ? BoardGuidanceStyle.current.prominentDangerBurstScale
            : BoardGuidanceStyle.current.ambientDangerBadgeScale
    }

    private var hiddenScale: CGFloat {
        isProminent ? 0.30 : 0.86
    }
}

struct DefenseShieldView: View {
    let cellSize: CGFloat
    let readableRotationDegrees: Double
    let reducesMotion: Bool

    var body: some View {
        Image(systemName: "shield.fill")
            .font(.system(size: cellSize * BoardGuidanceStyle.current.shieldScale, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(AppTheme.guidanceTeal, Color.white.opacity(0.92))
            .rotationEffect(.degrees(readableRotationDegrees))
            .opacity(0.90)
            .shadow(color: AppTheme.boardFrame.opacity(0.30), radius: 1.2, y: 0.7)
            .transition(
                reducesMotion
                    ? .opacity
                    : .scale(scale: 0.82).combined(with: .opacity)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SupporterEchoView: View {
    let cellSize: CGFloat
    let reducesMotion: Bool

    var body: some View {
        Circle()
            .strokeBorder(AppTheme.guidanceTeal.opacity(0.90), lineWidth: max(1.8, cellSize * 0.026))
            .background {
                Circle()
                    .strokeBorder(Color.white.opacity(0.42), lineWidth: max(3.2, cellSize * 0.045))
            }
            .frame(
                width: cellSize * BoardGuidanceStyle.current.supporterEchoScale,
                height: cellSize * BoardGuidanceStyle.current.supporterEchoScale
            )
            .transition(
                reducesMotion
                    ? .opacity
                    : .scale(scale: 0.90).combined(with: .opacity)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct GuidanceDiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
