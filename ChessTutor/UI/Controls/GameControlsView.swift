import SwiftUI

struct GameControlsPresentation: Equatable {
    enum PrimaryAction: Equatable {
        case playRemotely
        case done
        case newGame
    }

    enum SecondaryAction: Equatable {
        case newGame
        case about
    }

    let primaryAction: PrimaryAction
    let secondaryActions: [SecondaryAction]

    init(result: GameResult, isRemotePlayAvailable: Bool = false) {
        switch result {
        case .ongoing:
            primaryAction = isRemotePlayAvailable ? .playRemotely : .done
            secondaryActions = [.newGame, .about]
        case .checkmate, .stalemate:
            primaryAction = .newGame
            secondaryActions = [.about]
        }
    }
}

struct GameControlsView: View {
    @Bindable var session: GameSession
    let isRemotePlayAvailable: Bool
    let onPlayRemotely: () -> Void
    let onCommittedMove: (Move) -> Void

    init(
        session: GameSession,
        isRemotePlayAvailable: Bool = false,
        onPlayRemotely: @escaping () -> Void = {},
        onCommittedMove: @escaping (Move) -> Void = { _ in }
    ) {
        self.session = session
        self.isRemotePlayAvailable = isRemotePlayAvailable
        self.onPlayRemotely = onPlayRemotely
        self.onCommittedMove = onCommittedMove
    }

    var body: some View {
        let presentation = GameControlsPresentation(
            result: session.state.result,
            isRemotePlayAvailable: isRemotePlayAvailable
        )

        primaryButton(for: presentation.primaryAction)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .controlSize(.regular)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func primaryButton(for action: GameControlsPresentation.PrimaryAction) -> some View {
        switch action {
        case .playRemotely:
            playRemotelyButton
        case .done:
            doneButton
        case .newGame:
            primaryNewGameButton
        }
    }

    private var playRemotelyButton: some View {
        Button(action: onPlayRemotely) {
            Label("Play Remotely", systemImage: "person.2")
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(PrimaryGameButtonStyle(isEnabled: true))
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .labelStyle(.titleAndIcon)
    }

    private var doneButton: some View {
        Button {
            guard session.canFinishTurn else {
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                if let move = session.finishTurn() {
                    onCommittedMove(move)
                }
            }
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(PrimaryGameButtonStyle(isEnabled: session.canFinishTurn))
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .labelStyle(.titleAndIcon)
        .disabled(!session.canFinishTurn)
    }

    private var primaryNewGameButton: some View {
        Button {
            session.newGame()
        } label: {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(PrimaryGameButtonStyle(isEnabled: true))
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .labelStyle(.titleAndIcon)
    }

}

private struct PrimaryGameButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? AppTheme.whitePiece : AppTheme.mutedInk.opacity(0.54))
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isEnabled ? AppTheme.boardFrame : AppTheme.panelInset)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(AppTheme.panelTopLight.opacity(isEnabled ? 0.36 : 0.18))
                            .frame(height: 18)
                    }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .shadow(color: isEnabled ? AppTheme.panelShadow : .clear, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AboutAttribution.appName)
                    .font(AppTheme.aboutTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text(AboutAttribution.appSummary)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.72))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(AboutAttribution.pieceCreditTitle)
                    .font(AppTheme.aboutSectionTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text(AboutAttribution.pieceCredit)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.76))

                Text("\(AboutAttribution.pieceSource), \(AboutAttribution.pieceLicense)")
                    .font(.callout)
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.boardFrame)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.panel)
    }
}
