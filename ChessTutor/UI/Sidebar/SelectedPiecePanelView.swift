import SwiftUI

struct SelectedPiecePanelLayout: Equatable {
    static let current = SelectedPiecePanelLayout(
        iconSlotHeight: 90,
        selectedPieceSpacing: 6,
        squareBadgeHeight: 22,
        titleLineHeight: 24,
        titleSummarySpacing: 3,
        twoLineSummaryHeight: 41,
        coverageButtonSpacing: 8,
        coverageButtonHeight: 36
    )

    let iconSlotHeight: CGFloat
    let selectedPieceSpacing: CGFloat
    let squareBadgeHeight: CGFloat
    let titleLineHeight: CGFloat
    let titleSummarySpacing: CGFloat
    let twoLineSummaryHeight: CGFloat
    let coverageButtonSpacing: CGFloat
    let coverageButtonHeight: CGFloat

    var textSlotHeight: CGFloat {
        titleLineHeight + titleSummarySpacing + twoLineSummaryHeight
    }

    var requiredContentHeight: CGFloat {
        iconSlotHeight + selectedPieceSpacing + textSlotHeight
    }

    var coverageFooterHeight: CGFloat {
        coverageButtonSpacing + coverageButtonHeight
    }

    func remainingSlack(inPanelLength panelLength: CGFloat) -> CGFloat {
        panelLength - SidebarPanelMetrics.contentPadding * 2 - requiredContentHeight
    }

    func verticalInset(inPanelLength panelLength: CGFloat) -> CGFloat {
        max(0, remainingSlack(inPanelLength: panelLength) / 2)
    }

    func fittedIconSlotHeight(inContentLength contentLength: CGFloat) -> CGFloat {
        max(
            68,
            min(iconSlotHeight, contentLength - selectedPieceSpacing - textSlotHeight)
        )
    }
}

struct CoverageButtonPresentation: Equatable {
    let isVisible: Bool

    var title: String {
        isVisible ? "Hide coverage" : "Show coverage"
    }

    var systemImage: String {
        isVisible ? "eye.slash" : "eye"
    }
}

struct SelectedPiecePanelView: View {
    let selectedPieceInfo: SelectedPieceInfo?
    let isCoverageVisible: Bool
    let isCoverageAvailable: Bool
    let onToggleCoverage: () -> Void
    private let layout = SelectedPiecePanelLayout.current

    var body: some View {
        VStack(spacing: 0) {
            pieceContent

            if isCoverageAvailable {
                coverageButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pieceContent: some View {
        GeometryReader { proxy in
            if let selectedPieceInfo {
                let iconSlotHeight = layout.fittedIconSlotHeight(inContentLength: proxy.size.height)
                let verticalInset = layout.verticalInset(
                    inPanelLength: proxy.size.height + SidebarPanelMetrics.contentPadding * 2
                )

                VStack(alignment: .leading, spacing: layout.selectedPieceSpacing) {
                    Spacer(minLength: verticalInset)
                        .frame(height: verticalInset)

                    selectedPieceIcon(selectedPieceInfo.piece, slotHeight: iconSlotHeight)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: iconSlotHeight)

                    VStack(alignment: .leading, spacing: layout.titleSummarySpacing) {
                        titleRow(for: selectedPieceInfo)

                        Text(selectedPieceInfo.movementSummary)
                            .font(AppTheme.pieceBodyFont)
                            .foregroundStyle(AppTheme.mutedInk)
                            .lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(height: layout.textSlotHeight, alignment: .topLeading)

                    Spacer(minLength: verticalInset)
                        .frame(height: verticalInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: layout.selectedPieceSpacing) {
                    Spacer(minLength: 0)

                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(AppTheme.mutedInk.opacity(0.42))
                        .frame(maxWidth: .infinity)

                    Text("Choose a piece")
                        .font(AppTheme.emptyPanelFont)
                        .foregroundStyle(AppTheme.mutedInk.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var coverageButton: some View {
        let presentation = CoverageButtonPresentation(isVisible: isCoverageVisible)

        return Button(action: onToggleCoverage) {
            Label(presentation.title, systemImage: presentation.systemImage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(CoverageButtonStyle(isVisible: isCoverageVisible))
        .frame(height: layout.coverageFooterHeight)
        .contentShape(Rectangle())
        .accessibilityValue(isCoverageVisible ? "Shown" : "Hidden")
    }

    private func selectedPieceIcon(_ piece: Piece, slotHeight: CGFloat) -> some View {
        let iconSize = min(78, slotHeight - 14)

        return PieceIconView(piece: piece)
            .frame(width: iconSize, height: iconSize)
            .padding(7)
            .background {
                Circle()
                    .fill(AppTheme.selectedPiecePlinth)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.panelStroke, lineWidth: 1)
                    }
            }
    }

    private func titleRow(for selectedPieceInfo: SelectedPieceInfo) -> some View {
        HStack(spacing: 8) {
            Text(selectedPieceInfo.squareID)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.lightSquare)
                .padding(.horizontal, 10)
                .frame(height: layout.squareBadgeHeight)
                .background {
                    Capsule()
                        .fill(AppTheme.boardFrame)
                }

            Text(selectedPieceInfo.title)
                .font(AppTheme.pieceTitleFont)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(height: layout.titleLineHeight, alignment: .leading)
    }
}

private struct CoverageButtonStyle: ButtonStyle {
    let isVisible: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isVisible ? AppTheme.lightSquare : AppTheme.boardFrame)
            .frame(height: SelectedPiecePanelLayout.current.coverageButtonHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isVisible
                            ? AppTheme.coverageControlActive
                            : AppTheme.coverageControlFill
                    )
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(AppTheme.panelStroke.opacity(0.92), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                .spring(response: 0.22, dampingFraction: 0.84),
                value: configuration.isPressed
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
    }
}
