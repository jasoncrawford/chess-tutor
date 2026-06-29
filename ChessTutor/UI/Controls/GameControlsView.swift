import SwiftUI

enum GameControlsPlacement {
    case done
    case newGame
}

struct GameControlsView: View {
    @Bindable var session: GameSession
    let placement: GameControlsPlacement
    let onAbout: (() -> Void)?
    @State private var isConfirmingNewGame = false

    init(session: GameSession, placement: GameControlsPlacement, onAbout: (() -> Void)? = nil) {
        self.session = session
        self.placement = placement
        self.onAbout = onAbout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if placement == .done {
                turnControls
            } else {
                newGameControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .controlSize(.regular)
        .transaction { transaction in
            transaction.animation = nil
        }
        .alert("Start a new game?", isPresented: $isConfirmingNewGame) {
            Button("Keep Playing", role: .cancel) {}
            Button("New Game", role: .destructive) {
                session.newGame()
            }
        } message: {
            Text("This will abandon the current game.")
        }
    }

    private var turnControls: some View {
        doneButton
        .labelStyle(.titleAndIcon)
        .tint(AppTheme.boardFrame)
    }

    private var doneButton: some View {
        Button {
            guard session.canFinishTurn else {
                return
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                session.finishTurn()
            }
        } label: {
            Label("Done", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!session.canFinishTurn)
    }

    private var newGameButton: some View {
        Button {
            if session.hasGameInProgress {
                isConfirmingNewGame = true
            } else {
                session.newGame()
            }
        } label: {
            Label("New Game...", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.ink.opacity(0.72))
    }

    private var aboutButton: some View {
        Button {
            onAbout?()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(AppTheme.ink.opacity(0.62))
        .accessibilityLabel("About")
    }

    private var newGameControls: some View {
        HStack(spacing: 6) {
            newGameButton

            aboutButton
        }
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
