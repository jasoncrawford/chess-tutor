import SwiftUI

struct CapturedPiecesPanelView: View {
    let capturedPieces: [CapturedPiece]
    let captureNamespace: Namespace.ID
    let panelLength: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            captureBox(for: .black)
            captureBox(for: .white)
        }
        .frame(width: panelLength, height: panelLength)
    }

    private func captureBox(for color: PieceColor) -> some View {
        let pieces = capturedPieces.filter { $0.piece.color == color }
        let groups = CaptureTrayGroup.groups(for: pieces)

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.captureBoxWood.opacity(0.94),
                            AppTheme.captureBoxWood,
                            AppTheme.captureBoxWood.opacity(0.82),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: AppTheme.captureBoxShadow, radius: 14, y: 8)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.captureBoxFelt)
                .padding(9)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1)
                        .padding(9)
                }
                .shadow(color: .black.opacity(0.20), radius: 5, y: -1)

            GeometryReader { proxy in
                let layout = CaptureTrayLayout.make(
                    widthMultipliers: groups.map(\.widthMultiplier),
                    in: proxy.size
                )

                HStack(alignment: .center, spacing: CaptureTrayLayout.pieceSpacing) {
                    ForEach(Array(zip(groups.indices, groups)), id: \.1.id) { index, group in
                        CapturedPieceStackView(
                            group: group,
                            pieceSize: layout.pieceSize,
                            captureNamespace: captureNamespace
                        )
                        .frame(width: layout.itemWidths[index], height: layout.pieceSize, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pieces)
    }
}

struct CapturedPieceStackView: View {
    let group: CaptureTrayGroup
    let pieceSize: CGFloat
    let captureNamespace: Namespace.ID

    private var stackOffset: CGFloat {
        min(8, pieceSize * 0.16)
    }

    private var countBadgeFontSize: CGFloat {
        max(12, pieceSize * 0.36)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if group.pieces.count > 1 {
                pieceView(group.pieces[1])
                    .offset(x: stackOffset, y: -stackOffset)
                    .zIndex(0)
            }

            pieceView(group.pieces[0])
                .zIndex(1)

            if let countText = group.countText {
                Text(countText)
                    .font(.system(size: countBadgeFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppTheme.lightSquare.opacity(0.90))
                            .overlay {
                                Capsule()
                                    .stroke(AppTheme.boardFrame.opacity(0.22), lineWidth: 1)
                            }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 2)
                    .offset(y: -pieceSize * 0.04)
                    .zIndex(2)
            }
        }
        .frame(width: pieceSize * group.widthMultiplier, height: pieceSize)
    }

    private func pieceView(_ capturedPiece: CapturedPiece) -> some View {
        PieceIconView(piece: capturedPiece.piece)
            .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
            .frame(width: pieceSize, height: pieceSize)
            .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
            .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
    }
}

struct CaptureTrayGroup: Equatable, Identifiable {
    static let countBadgeWidthMultiplier: CGFloat = 1.38

    let kind: Piece.Kind
    let pieces: [CapturedPiece]

    var id: String {
        "\(pieces[0].piece.color.rawValue)-\(kind.rawValue)"
    }

    var countText: String? {
        guard pieces.count > 2 else {
            return nil
        }

        return "x\(pieces.count)"
    }

    var widthMultiplier: CGFloat {
        countText == nil ? 1 : Self.countBadgeWidthMultiplier
    }

    static func groups(for pieces: [CapturedPiece]) -> [CaptureTrayGroup] {
        var groupedPieces: [(kind: Piece.Kind, pieces: [CapturedPiece])] = []

        for piece in pieces {
            if let index = groupedPieces.firstIndex(where: { $0.kind == piece.piece.kind }) {
                groupedPieces[index].pieces.append(piece)
            } else {
                groupedPieces.append((kind: piece.piece.kind, pieces: [piece]))
            }
        }

        return groupedPieces.map { CaptureTrayGroup(kind: $0.kind, pieces: $0.pieces) }
    }
}

struct CaptureTrayLayout: Equatable {
    static let pieceSpacing: CGFloat = 4
    private static let maximumPieceSize: CGFloat = 56
    private static let minimumPieceSize: CGFloat = 18

    let columns: Int
    let itemWidth: CGFloat
    let itemWidths: [CGFloat]
    let pieceSize: CGFloat

    static func make(widthMultipliers: [CGFloat], in size: CGSize) -> CaptureTrayLayout {
        guard !widthMultipliers.isEmpty else {
            return CaptureTrayLayout(
                columns: 1,
                itemWidth: maximumPieceSize,
                itemWidths: [maximumPieceSize],
                pieceSize: maximumPieceSize
            )
        }

        let availableWidth = max(1, size.width)
        let availableHeight = max(1, size.height)
        let totalSpacing = CGFloat(widthMultipliers.count - 1) * pieceSpacing
        let totalWidthMultiplier = widthMultipliers.reduce(0, +)
        let widthBound = (availableWidth - totalSpacing) / totalWidthMultiplier
        let pieceSize = max(minimumPieceSize, min(maximumPieceSize, availableHeight, widthBound))
        let itemWidths = widthMultipliers.map { pieceSize * $0 }

        return CaptureTrayLayout(
            columns: widthMultipliers.count,
            itemWidth: itemWidths.first ?? pieceSize,
            itemWidths: itemWidths,
            pieceSize: pieceSize
        )
    }

    static func make(
        for pieceCount: Int,
        reservesCountBadgeSpace: Bool = false,
        in size: CGSize
    ) -> CaptureTrayLayout {
        guard pieceCount > 0 else {
            return CaptureTrayLayout(
                columns: 1,
                itemWidth: maximumPieceSize,
                itemWidths: [maximumPieceSize],
                pieceSize: maximumPieceSize
            )
        }

        let availableWidth = max(1, size.width)
        let availableHeight = max(1, size.height)
        let widthMultiplier: CGFloat = reservesCountBadgeSpace ? CaptureTrayGroup.countBadgeWidthMultiplier : 1
        let rows = (1...3).first { rowCount in
            let columnCount = Int(ceil(Double(pieceCount) / Double(rowCount)))
            let itemWidth = (availableWidth - CGFloat(columnCount - 1) * pieceSpacing) / CGFloat(columnCount)
            let widthBound = itemWidth / widthMultiplier
            let heightBound = (availableHeight - CGFloat(rowCount - 1) * pieceSpacing) / CGFloat(rowCount)

            return min(widthBound, heightBound) >= minimumPieceSize
        } ?? 3
        let columns = max(1, Int(ceil(Double(pieceCount) / Double(rows))))
        let itemWidth = (availableWidth - CGFloat(columns - 1) * pieceSpacing) / CGFloat(columns)
        let widthBound = itemWidth / widthMultiplier
        let heightBound = (availableHeight - CGFloat(rows - 1) * pieceSpacing) / CGFloat(rows)
        let pieceSize = max(minimumPieceSize, min(maximumPieceSize, widthBound, heightBound))

        return CaptureTrayLayout(
            columns: columns,
            itemWidth: itemWidth,
            itemWidths: Array(repeating: itemWidth, count: columns),
            pieceSize: pieceSize
        )
    }
}
