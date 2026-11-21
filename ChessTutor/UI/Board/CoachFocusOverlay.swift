import SwiftUI

struct CoachFocusStyle: Equatable {
    static let current = CoachFocusStyle(
        emphasizedRingScale: 0.76,
        candidateRingScale: 0.80,
        ringLineWidthInCells: 0.026,
        candidateRingLineWidthInCells: 0.036,
        candidateRingKeylineWidthInCells: 0.072,
        pathLineWidthInCells: 0.020,
        candidatePathDashInCells: [0.08, 0.07]
    )

    let emphasizedRingScale: CGFloat
    let candidateRingScale: CGFloat
    let ringLineWidthInCells: CGFloat
    let candidateRingLineWidthInCells: CGFloat
    let candidateRingKeylineWidthInCells: CGFloat
    let pathLineWidthInCells: CGFloat
    let candidatePathDashInCells: [CGFloat]

    func pathDash(for role: CoachFocusPath.Role) -> [CGFloat] {
        role == .candidate ? candidatePathDashInCells : []
    }
}

struct CoachFocusPathLayout: Equatable {
    let start: CGPoint
    let end: CGPoint

    static func make(
        from source: Square,
        to destination: Square,
        geometry: BoardGuidanceGeometry
    ) -> CoachFocusPathLayout {
        CoachFocusPathLayout(
            start: geometry.center(of: source),
            end: geometry.center(of: destination)
        )
    }
}

struct CoachFocusMotionPolicy: Equatable {
    let reducesMotion: Bool

    var pulseScale: CGFloat {
        reducesMotion ? 1 : 1.08
    }
}

enum CoachBoardAccessibilityContext {
    static func instruction(for presentation: CoachingPresentation?) -> String? {
        guard case .identify = presentation?.boardTask else {
            return nil
        }
        return presentation?.instruction ?? "Tap a piece to answer the coach"
    }
}

struct CoachFocusOverlay: View {
    let focus: CoachFocusPresentation
    let side: CGFloat
    let origin: CGPoint
    let viewingAngle: BoardViewingAngle
    let reducesMotion: Bool

    @State private var pulseScale: CGFloat = 1

    var body: some View {
        let geometry = BoardGuidanceGeometry(
            side: side,
            origin: origin,
            viewingAngle: viewingAngle
        )
        let style = CoachFocusStyle.current

        Canvas { context, _ in
            drawPaths(in: &context, geometry: geometry, style: style)
            drawCandidateRings(in: &context, geometry: geometry, style: style)
            drawEmphasizedRings(in: &context, geometry: geometry, style: style)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: focus.pulseID) { await runPulse() }
        .onChange(of: reducesMotion) {
            if reducesMotion {
                pulseScale = 1
            }
        }
    }

    private func drawPaths(
        in context: inout GraphicsContext,
        geometry: BoardGuidanceGeometry,
        style: CoachFocusStyle
    ) {
        for focusPath in focus.paths.sorted(by: pathOrder) {
            guard let layout = CoachArrowGeometry.make(source: focusPath.source,
                destination: focusPath.destination, kind: focusPath.geometryKind, geometry: geometry) else { continue }
            var path = Path()
            path.addLines(layout.points)
            context.stroke(path, with: .color(AppTheme.moveInlayHighlight), style: .init(lineWidth: geometry.cellSize * 0.095, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(AppTheme.coachFocusRing), style: .init(lineWidth: geometry.cellSize * 0.055, lineCap: .round, lineJoin: .round))
            var head = Path()
            head.addLines(layout.arrowhead)
            head.closeSubpath()
            context.stroke(head, with: .color(AppTheme.moveInlayHighlight), lineWidth: geometry.cellSize * 0.035)
            context.fill(head, with: .color(AppTheme.coachFocusRing))
        }
    }

    private func drawCandidateRings(
        in context: inout GraphicsContext,
        geometry: BoardGuidanceGeometry,
        style: CoachFocusStyle
    ) {
        for square in focus.candidateSquares.sorted(by: squareOrder) {
            let rect = ringRect(
                center: geometry.center(of: square),
                diameter: geometry.cellSize * style.candidateRingScale * pulseScale
            )
            let ring = Path(ellipseIn: rect)
            context.stroke(
                ring,
                with: .color(AppTheme.coachCandidateKeyline),
                style: StrokeStyle(
                    lineWidth: geometry.cellSize * style.candidateRingKeylineWidthInCells,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.stroke(
                ring,
                with: .color(AppTheme.coachCandidateRing),
                style: StrokeStyle(
                    lineWidth: geometry.cellSize * style.candidateRingLineWidthInCells,
                    lineCap: .round,
                    dash: style.candidatePathDashInCells.map { $0 * geometry.cellSize }
                )
            )
        }
    }

    private func drawEmphasizedRings(
        in context: inout GraphicsContext,
        geometry: BoardGuidanceGeometry,
        style: CoachFocusStyle
    ) {
        for square in focus.emphasizedSquares.sorted(by: squareOrder) {
            let center = geometry.center(of: square)
            let diameter = geometry.cellSize * style.emphasizedRingScale * pulseScale
            context.stroke(
                Path(ellipseIn: ringRect(center: center, diameter: diameter)),
                with: .color(AppTheme.coachFocusRing),
                lineWidth: geometry.cellSize * style.ringLineWidthInCells
            )
            context.stroke(
                Path(ellipseIn: ringRect(center: center, diameter: diameter * 1.11)),
                with: .color(AppTheme.coachFocusRing.opacity(0.24)),
                lineWidth: geometry.cellSize * style.ringLineWidthInCells * 0.72
            )
        }
    }

    @MainActor private func runPulse() async {
        let policy = CoachFocusMotionPolicy(reducesMotion: reducesMotion)
        guard policy.pulseScale > 1 else {
            pulseScale = 1
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            pulseScale = policy.pulseScale
        }
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.22)) { pulseScale = 1 }
    }

    private func ringRect(center: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private func squareOrder(_ lhs: Square, _ rhs: Square) -> Bool {
        squareSortKey(lhs) < squareSortKey(rhs)
    }

    private func pathOrder(_ lhs: CoachFocusPath, _ rhs: CoachFocusPath) -> Bool {
        if lhs.role != rhs.role {
            return pathRoleOrder(lhs.role) < pathRoleOrder(rhs.role)
        }
        if squareSortKey(lhs.source) != squareSortKey(rhs.source) {
            return squareSortKey(lhs.source) < squareSortKey(rhs.source)
        }
        return squareSortKey(lhs.destination) < squareSortKey(rhs.destination)
    }

    private func pathRoleOrder(_ role: CoachFocusPath.Role) -> Int {
        switch role {
        case .candidate: 0
        case .defender: 1
        case .attacker: 2
        }
    }

    private func squareSortKey(_ square: Square) -> Int {
        square.rank * 8 + square.file.rawValue
    }
}
