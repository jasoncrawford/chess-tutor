import SwiftUI
import UIKit

struct ContentView: View {
    @State private var session = GameSession()
    @State private var pendingPromotion: PendingPromotion?
    @State private var baselineOrientation = UIInterfaceOrientation.landscapeLeft
    @State private var viewingAngle: BoardViewingAngle
    @State private var tableRotationDegrees: Double
    @Namespace private var captureNamespace

    init() {
        let initialViewingAngle = Self.currentViewingAngle()
        _viewingAngle = State(initialValue: initialViewingAngle)
        _tableRotationDegrees = State(initialValue: initialViewingAngle.tableRotationDegrees)
    }

    var body: some View {
        GeometryReader { proxy in
            let tabletopSize = tabletopSize(for: proxy.size)

            ZStack {
                AppTheme.table.ignoresSafeArea()
                tabletop
                    .frame(width: tabletopSize.width, height: tabletopSize.height)
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

    private var tabletop: some View {
        HStack(alignment: .top, spacing: 28) {
            chessBoard
            sidePanelContainer
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
    }

    private var chessBoard: some View {
        ChessBoardView(
            session: session,
            captureNamespace: captureNamespace,
            viewingAngle: viewingAngle,
            readableRotationDegrees: readableRotationDegrees
        ) { result in
            if case let .needsPromotion(from, to) = result {
                pendingPromotion = PendingPromotion(from: from, to: to)
            }
        }
        .frame(maxWidth: 760)
    }

    private var sidePanelContainer: some View {
        sidePanel
            .frame(width: 260)
            .frame(height: 760, alignment: .top)
    }

    private var sidePanel: some View {
        VStack(spacing: 12) {
            ForEach(viewingAngle.sidebarSegmentsInTabletopOrder, id: \.self) { segment in
                sidebarTile(segment) {
                    sidebarSegment(segment)
                }
            }
        }
        .frame(width: 260, height: 760, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewingAngle.sidebarSegmentsInTabletopOrder)
    }

    private var turnTile: some View {
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

            Spacer(minLength: 0)

            GameControlsView(session: session, placement: .done)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var newGameTile: some View {
        VStack {
            Spacer()
            GameControlsView(session: session, placement: .newGame)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sidebarSegment(_ segment: SidebarSegment) -> some View {
        switch segment {
        case .messageAndDone:
            turnTile
        case .capturedPieces:
            captureTrays
        case .newGame:
            newGameTile
        }
    }

    private func sidebarTile<Content: View>(
        _ segment: SidebarSegment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(width: 240, height: 240)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.panel)
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
            )
            .rotationEffect(.degrees(readableRotationDegrees))
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: tableRotationDegrees)
    }

    private var captureTrays: some View {
        VStack(spacing: 6) {
            captureTray(for: .black)
            captureTray(for: .white)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(.vertical, 2)
    }

    private func captureTray(for color: PieceColor) -> some View {
        let pieces = session.capturedPieces.filter { $0.piece.color == color }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6),
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(pieces) { capturedPiece in
                PieceIconView(piece: capturedPiece.piece)
                    .matchedGeometryEffect(id: capturedPiece.id, in: captureNamespace)
                    .frame(width: 28, height: 28)
                    .opacity(capturedPiece.state == .tentative ? 0.62 : 1)
                    .scaleEffect(capturedPiece.state == .tentative ? 0.92 : 1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: pieces)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.ink.opacity(pieces.isEmpty ? 0.04 : 0.07))
        )
    }

    private func tabletopSize(for size: CGSize) -> CGSize {
        CGSize(width: max(size.width, size.height), height: min(size.width, size.height))
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

#Preview {
    ContentView()
}
