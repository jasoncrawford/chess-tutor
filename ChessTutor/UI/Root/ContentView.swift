import SwiftUI
import UIKit

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?
    @State private var isShowingAbout = false
    @State private var baselineOrientation = UIInterfaceOrientation.landscapeLeft
    @State private var viewingAngle: BoardViewingAngle
    @State private var tableRotationDegrees: Double
    #if DEBUG
    @State private var isCaptureTestModeEnabled = false
    #endif
    @Namespace private var captureNamespace

    init() {
        let initialViewingAngle = Self.currentViewingAngle()
        _viewingAngle = State(initialValue: initialViewingAngle)
        _tableRotationDegrees = State(initialValue: initialViewingAngle.tableRotationDegrees)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = PlaySurfaceLayout.make(for: proxy.size)

            ZStack {
                AppTheme.table.ignoresSafeArea()
                tabletop(boardSide: layout.boardSide)
                    .frame(width: layout.tabletopSize.width, height: layout.tabletopSize.height)
                    .rotationEffect(.degrees(tableRotationDegrees))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .onAppear {
            syncToCurrentInterfaceOrientation(animated: false)
            DispatchQueue.main.async {
                syncToCurrentInterfaceOrientation(animated: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            guard orientation.isValidBoardViewingOrientation else {
                return
            }
            let nextAngle = BoardViewingAngle(deviceOrientation: orientation, baseline: baselineOrientation.deviceOrientation)
            applyViewingAngle(nextAngle, animated: true)
        }
        .sheet(item: $pendingPromotion) { promotion in
            PromotionPickerView(color: session.state.sideToMove) { kind in
                session.promote(from: promotion.from, to: promotion.to, to: kind)
                pendingPromotion = nil
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutSheetView()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
    }

    private func tabletop(boardSide: CGFloat) -> some View {
        HStack(alignment: .top, spacing: PlaySurfaceLayout.boardPanelSpacing) {
            chessBoard
                .frame(width: boardSide, height: boardSide)
            sidePanelContainer(sideLength: boardSide)
        }
        .frame(
            width: boardSide + PlaySurfaceLayout.boardPanelSpacing + PlaySurfaceLayout.sidePanelWidth,
            height: boardSide
        )
    }

    private var chessBoard: some View {
        let handleMoveAttempt: (MoveAttemptResult) -> Void = { result in
            if case let .needsPromotion(from, to) = result {
                pendingPromotion = PendingPromotion(from: from, to: to)
            }
        }

        #if DEBUG
        return ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            isCaptureTestModeEnabled: isCaptureTestModeEnabled,
            onMoveAttempt: handleMoveAttempt
        )
        #else
        return ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            onMoveAttempt: handleMoveAttempt
        )
        #endif
    }

    private func sidePanelContainer(sideLength: CGFloat) -> some View {
        #if DEBUG
        return SidePanelView(
            session: session,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            captureNamespace: captureNamespace,
            sideLength: sideLength,
            isCaptureTestModeEnabled: $isCaptureTestModeEnabled,
            onAbout: {
                isShowingAbout = true
            }
        )
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: sideLength, alignment: .top)
        #else
        return SidePanelView(
            session: session,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees,
            captureNamespace: captureNamespace,
            sideLength: sideLength,
            onAbout: {
                isShowingAbout = true
            }
        )
        .frame(width: PlaySurfaceLayout.sidePanelWidth, height: sideLength, alignment: .top)
        #endif
    }

    private func syncToCurrentInterfaceOrientation(animated: Bool) {
        applyViewingAngle(Self.currentViewingAngle(), animated: animated)
    }

    private func applyViewingAngle(_ nextAngle: BoardViewingAngle, animated: Bool) {
        let nextTableRotationDegrees = nextAngle.tableRotationDegrees(closestTo: tableRotationDegrees)
        let update = {
            viewingAngle = nextAngle
            tableRotationDegrees = nextTableRotationDegrees
        }

        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                update()
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                update()
            }
        }
    }

    private static func currentViewingAngle() -> BoardViewingAngle {
        if let orientation = UIApplication.shared.activeInterfaceOrientation {
            return BoardViewingAngle(interfaceOrientation: orientation, baseline: .landscapeLeft)
        }

        let orientation = UIDevice.current.orientation
        if orientation.isValidBoardViewingOrientation {
            return BoardViewingAngle(deviceOrientation: orientation, baseline: .landscapeLeft)
        }

        return .normal
    }

    private var readableRotationDegrees: Double {
        -tableRotationDegrees
    }
}

struct PlaySurfaceLayout: Equatable {
    static let maximumBoardSide: CGFloat = 760
    static let sidePanelWidth: CGFloat = 260
    static let boardPanelSpacing: CGFloat = 28
    static let horizontalPadding: CGFloat = 30
    static let verticalPadding: CGFloat = 24

    let tabletopSize: CGSize
    let boardSide: CGFloat

    var sidePanelHeight: CGFloat {
        boardSide
    }

    var contentSize: CGSize {
        CGSize(
            width: boardSide + Self.boardPanelSpacing + Self.sidePanelWidth,
            height: boardSide
        )
    }

    static func make(for viewportSize: CGSize) -> PlaySurfaceLayout {
        let tabletopSize = CGSize(
            width: max(viewportSize.width, viewportSize.height),
            height: min(viewportSize.width, viewportSize.height)
        )
        let availableHeight = max(1, tabletopSize.height - verticalPadding * 2)
        let availableWidth = max(
            1,
            tabletopSize.width - horizontalPadding * 2 - sidePanelWidth - boardPanelSpacing
        )
        let boardSide = min(maximumBoardSide, availableWidth, availableHeight)

        return PlaySurfaceLayout(tabletopSize: tabletopSize, boardSide: boardSide)
    }
}

private extension UIApplication {
    var activeInterfaceOrientation: UIInterfaceOrientation? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
            }?
            .interfaceOrientation
    }
}

private extension UIInterfaceOrientation {
    var deviceOrientation: UIDeviceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .unknown
        }
    }
}

private struct PendingPromotion: Identifiable {
    let id = UUID()
    let from: Square
    let to: Square
}

private struct PromotionPickerView: View {
    let color: PieceColor
    let promote: (Piece.Kind) -> Void

    private let choices: [Piece.Kind] = [.queen, .rook, .bishop, .knight]
    private let columns = [
        GridItem(.flexible(minimum: 132), spacing: 12),
        GridItem(.flexible(minimum: 132), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose promotion")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Pick the piece your pawn becomes.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(choices, id: \.self) { kind in
                    Button {
                        promote(kind)
                    } label: {
                        PromotionChoiceLabel(kind: kind, color: color)
                    }
                    .buttonStyle(PromotionChoiceButtonStyle())
                    .accessibilityLabel("Promote to \(kind.rawValue)")
                    .accessibilityIdentifier("promotion-\(kind.rawValue)-button")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .presentationBackground(AppTheme.table)
    }
}

private struct PromotionChoiceLabel: View {
    let kind: Piece.Kind
    let color: PieceColor

    var body: some View {
        HStack(spacing: 14) {
            PieceIconView(piece: Piece(kind: kind, color: color))
                .frame(width: 56, height: 56)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.lightSquare.opacity(0.72))
                )

            Text(kind.rawValue.capitalized)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PromotionChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SwiftUI.Color.white.opacity(configuration.isPressed ? 0.72 : 0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.boardFrame.opacity(configuration.isPressed ? 0.42 : 0.24), lineWidth: 1)
            )
            .shadow(color: SwiftUI.Color.black.opacity(configuration.isPressed ? 0.06 : 0.12), radius: configuration.isPressed ? 2 : 8, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
