import CoreGraphics

struct CoachArrowGeometry: Equatable {
    let points: [CGPoint]
    let arrowhead: [CGPoint]

    static func make(source: Square, destination: Square, kind: CoachFocusPath.GeometryKind,
                     geometry: BoardGuidanceGeometry) -> CoachArrowGeometry? {
        guard source != destination else { return nil }
        let start = geometry.center(of: source), end = geometry.center(of: destination)
        var points = [start]
        if kind == .knight {
            // Bend in board coordinates, then transform, so rotations preserve the L.
            let fileDistance = abs(source.file.rawValue - destination.file.rawValue)
            let bend = fileDistance == 2
                ? Square(file: destination.file, rank: source.rank)
                : Square(file: source.file, rank: destination.rank)
            points.append(geometry.center(of: bend))
        }
        points.append(end)
        let previous = points[points.count - 2]
        let length = hypot(end.x - previous.x, end.y - previous.y)
        guard length > 0 else { return nil }
        let dx = (end.x - previous.x) / length, dy = (end.y - previous.y) / length
        let tip = CGPoint(x: end.x - dx * geometry.cellSize * 0.33, y: end.y - dy * geometry.cellSize * 0.33)
        points[points.count - 1] = tip
        let firstEnd = points[1]
        let firstLength = hypot(firstEnd.x - start.x, firstEnd.y - start.y)
        let inset = min(geometry.cellSize * 0.25, firstLength * 0.25)
        points[0] = CGPoint(x: start.x + (firstEnd.x - start.x) / firstLength * inset,
                            y: start.y + (firstEnd.y - start.y) / firstLength * inset)
        let depth = geometry.cellSize * 0.19, width = geometry.cellSize * 0.11
        return .init(points: points, arrowhead: [tip,
            CGPoint(x: tip.x - dx * depth - dy * width, y: tip.y - dy * depth + dx * width),
            CGPoint(x: tip.x - dx * depth + dy * width, y: tip.y - dy * depth - dx * width)])
    }
}
