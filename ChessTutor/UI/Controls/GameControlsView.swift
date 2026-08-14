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

    enum SupplementalAction: Equatable {
        case help
    }

    let primaryAction: PrimaryAction
    let supplementalActions: [SupplementalAction]
    let secondaryActions: [SecondaryAction]

    init(
        result: GameResult,
        isRemoteGameEnded: Bool = false,
        isRemotePlayAvailable: Bool = false,
        canRequestCoaching: Bool = false
    ) {
        supplementalActions = canRequestCoaching ? [.help] : []

        switch (isRemoteGameEnded, result) {
        case (true, _):
            primaryAction = .newGame
            secondaryActions = [.about]
        case (false, .ongoing):
            primaryAction = isRemotePlayAvailable ? .playRemotely : .done
            secondaryActions = [.newGame, .about]
        case (false, .checkmate), (false, .stalemate):
            primaryAction = .newGame
            secondaryActions = [.about]
        }
    }
}

struct GameControlsView: View {
    @Bindable var session: GameSession
    let isRemotePlayAvailable: Bool
    let onPlayRemotely: () -> Void
    let onNewGame: () -> Void
    let onCommittedMove: (Move) -> Void

    init(
        session: GameSession,
        isRemotePlayAvailable: Bool = false,
        onPlayRemotely: @escaping () -> Void = {},
        onNewGame: @escaping () -> Void = {},
        onCommittedMove: @escaping (Move) -> Void = { _ in }
    ) {
        self.session = session
        self.isRemotePlayAvailable = isRemotePlayAvailable
        self.onPlayRemotely = onPlayRemotely
        self.onNewGame = onNewGame
        self.onCommittedMove = onCommittedMove
    }

    var body: some View {
        let presentation = GameControlsPresentation(
            result: session.state.result,
            isRemoteGameEnded: session.isRemoteGameEnded,
            isRemotePlayAvailable: isRemotePlayAvailable,
            canRequestCoaching: session.canRequestCoaching
        )

        HStack(spacing: 8) {
            primaryButton(for: presentation.primaryAction)

            ForEach(presentation.supplementalActions, id: \.self) { action in
                supplementalButton(for: action)
            }
        }
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
        Button(action: onNewGame) {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(PrimaryGameButtonStyle(isEnabled: true))
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func supplementalButton(
        for action: GameControlsPresentation.SupplementalAction
    ) -> some View {
        switch action {
        case .help:
            Button {
                session.startCoaching()
            } label: {
                Label("Help me", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .frame(width: 94)
            .buttonStyle(SupplementalGameButtonStyle())
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .labelStyle(.titleAndIcon)
        }
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

private struct SupplementalGameButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.mutedInk)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppTheme.panelWarmth.opacity(configuration.isPressed ? 0.94 : 0.58))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: configuration.isPressed)
    }
}

struct AboutSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticsShareItem: DiagnosticsShareItem?
    @State private var diagnosticsErrorMessage: String?
    @State private var isPreparingDiagnostics = false
    let diagnosticsLog: DiagnosticsLog
    let buildInfo: AppBuildInfo

    init(diagnosticsLog: DiagnosticsLog = .shared, buildInfo: AppBuildInfo = .current()) {
        self.diagnosticsLog = diagnosticsLog
        self.buildInfo = buildInfo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(AboutAttribution.appName)
                    .font(AppTheme.aboutTitleFont)
                    .foregroundStyle(AppTheme.ink)

                Text(AboutAttribution.appSummary)
                    .font(AppTheme.panelBodyFont)
                    .foregroundStyle(AppTheme.ink.opacity(0.72))

                VStack(alignment: .leading, spacing: 3) {
                    Text(buildInfo.versionDisplayText)
                    Text(buildInfo.revisionDisplayText)
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.58))
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

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    shareDiagnostics()
                } label: {
                    Label(
                        isPreparingDiagnostics ? "Preparing Diagnostics..." : "Share Diagnostics",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingDiagnostics)
                .foregroundStyle(AppTheme.boardFrame)

                if let diagnosticsErrorMessage {
                    Text(diagnosticsErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.72, green: 0.23, blue: 0.17))
                }
            }

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
        .sheet(item: $diagnosticsShareItem) { item in
            DiagnosticsShareSheet(url: item.url)
        }
    }

    private func shareDiagnostics() {
        isPreparingDiagnostics = true
        diagnosticsErrorMessage = nil
        Task { @MainActor in
            do {
                let exportURL = try await diagnosticsLog.exportFile()
                diagnosticsShareItem = DiagnosticsShareItem(url: exportURL)
            } catch {
                diagnosticsErrorMessage = "Could not prepare diagnostics."
            }
            isPreparingDiagnostics = false
        }
    }
}
