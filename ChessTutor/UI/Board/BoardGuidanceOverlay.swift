import SwiftUI

struct BoardGuidanceStyle: Equatable {
    static let current = BoardGuidanceStyle(
        arrowheadLengthInCells: 0.14,
        pathLineWidthInCells: 0.028,
        dangerBurstScale: 0.92,
        shieldScale: 0.16,
        supporterEchoScale: 0.94
    )

    let arrowheadLengthInCells: CGFloat
    let pathLineWidthInCells: CGFloat
    let dangerBurstScale: CGFloat
    let shieldScale: CGFloat
    let supporterEchoScale: CGFloat
}

enum CoveragePipShape: Equatable {
    case circle
    case diamond
}

struct CoveragePipMarker: Equatable {
    let shape: CoveragePipShape
    let frame: CGRect
}

enum CoveragePipLayout {
    static func markers(
        showsSideToMove: Bool,
        showsOtherSide: Bool,
        cellSize: CGFloat
    ) -> [CoveragePipMarker] {
        let markerSize = cellSize * 0.11
        let y = cellSize * 0.76
        var markers: [CoveragePipMarker] = []

        if showsSideToMove {
            markers.append(
                CoveragePipMarker(
                    shape: .circle,
                    frame: CGRect(
                        x: cellSize * 0.10,
                        y: y,
                        width: markerSize,
                        height: markerSize
                    )
                )
            )
        }
        if showsOtherSide {
            markers.append(
                CoveragePipMarker(
                    shape: .diamond,
                    frame: CGRect(
                        x: cellSize * 0.25,
                        y: y,
                        width: markerSize,
                        height: markerSize
                    )
                )
            )
        }

        return markers
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

struct CoveragePipsLayer: View {
    let guidance: BoardGuidancePresentation
    let side: CGFloat
    let origin: CGPoint
    let viewingAngle: BoardViewingAngle

    var body: some View {
        if let coverage = guidance.coverage {
            let geometry = BoardGuidanceGeometry(
                side: side,
                origin: origin,
                viewingAngle: viewingAngle
            )
            let squares = coverage.sideToMoveSquares
                .union(coverage.otherSideSquares)
                .sorted(by: squareOrder)

            ZStack {
                ForEach(squares, id: \.self) { square in
                    let squareOrigin = geometry.origin(of: square)
                    let markers = CoveragePipLayout.markers(
                        showsSideToMove: coverage.sideToMoveSquares.contains(square),
                        showsOtherSide: coverage.otherSideSquares.contains(square),
                        cellSize: geometry.cellSize
                    )

                    ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                        coverageMarker(marker.shape)
                            .frame(width: marker.frame.width, height: marker.frame.height)
                            .position(
                                x: squareOrigin.x + marker.frame.midX,
                                y: squareOrigin.y + marker.frame.midY
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func coverageMarker(_ shape: CoveragePipShape) -> some View {
        switch shape {
        case .circle:
            Circle()
                .fill(AppTheme.guidanceYellow)
                .overlay {
                    Circle().stroke(AppTheme.boardFrame.opacity(0.48), lineWidth: 0.8)
                }
                .shadow(color: AppTheme.boardFrame.opacity(0.18), radius: 1, y: 0.5)
        case .diamond:
            GuidanceDiamondShape()
                .fill(AppTheme.guidanceRed)
                .overlay {
                    GuidanceDiamondShape()
                        .stroke(AppTheme.boardFrame.opacity(0.48), lineWidth: 0.8)
                }
                .shadow(color: AppTheme.boardFrame.opacity(0.18), radius: 1, y: 0.5)
        }
    }

    private func squareOrder(_ lhs: Square, _ rhs: Square) -> Bool {
        if lhs.rank == rhs.rank {
            return lhs.file.rawValue < rhs.file.rawValue
        }
        return lhs.rank < rhs.rank
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
        let paths = guidance.selectedPaths.sorted(by: pathOrder)

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

struct DangerBurstView: View {
    let cellSize: CGFloat
    let opacity: Double
    let reducesMotion: Bool

    var body: some View {
        DangerBurstShape()
            .fill(AppTheme.guidanceCoral.opacity(0.76))
            .overlay {
                DangerBurstShape()
                    .stroke(AppTheme.guidanceRed.opacity(0.88), lineWidth: 1.2)
            }
            .frame(
                width: cellSize * BoardGuidanceStyle.current.dangerBurstScale,
                height: cellSize * BoardGuidanceStyle.current.dangerBurstScale
            )
            .opacity(opacity)
            .shadow(color: AppTheme.guidanceRed.opacity(0.20), radius: 2, y: 1)
            .transition(
                reducesMotion
                    ? .opacity
                    : .scale(scale: 0.84).combined(with: .opacity)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DefenseShieldView: View {
    let cellSize: CGFloat
    let readableRotationDegrees: Double
    let opacity: Double
    let reducesMotion: Bool

    var body: some View {
        Image(systemName: "shield.fill")
            .font(.system(size: cellSize * BoardGuidanceStyle.current.shieldScale, weight: .bold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(AppTheme.guidanceTeal, Color.white.opacity(0.92))
            .rotationEffect(.degrees(readableRotationDegrees))
            .opacity(opacity * 0.80)
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
