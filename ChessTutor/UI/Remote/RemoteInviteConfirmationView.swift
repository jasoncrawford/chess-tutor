import SwiftUI

struct RemoteInviteConfirmationView: View {
    let confirmation: RemoteInviteConfirmation
    let onSelectColor: (PieceColor) -> Void
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text(confirmation.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if confirmation.requiresColorChoice {
                Text("Choose your color")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
            }

            if confirmation.showsColorSeats {
                HStack(spacing: 14) {
                    colorSeat(confirmation.whiteSeat)
                    colorSeat(confirmation.blackSeat)
                }
            }

            if confirmation.isTerminal {
                Button(confirmation.acknowledgementButtonTitle) {
                    onCancel()
                }
                .buttonStyle(RemoteInviteCancelButtonStyle())
            } else {
                HStack(spacing: 12) {
                    Button(confirmation.cancelButtonTitle) {
                        onCancel()
                    }
                    .buttonStyle(RemoteInviteCancelButtonStyle())

                    Button(confirmation.startButtonTitle) {
                        onStart()
                    }
                    .buttonStyle(RemoteGameStartButtonStyle())
                    .disabled(!confirmation.canStart)
                    .opacity(confirmation.canStart ? 1 : 0.45)
                    .accessibilityIdentifier("remote-invite-start-button")
                }
            }
        }
        .padding(26)
        .frame(width: 430)
        .background(Self.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.panelStroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("remote-invite-confirmation")
    }

    @ViewBuilder
    private func colorSeat(_ seat: RemoteGameSeat) -> some View {
        if confirmation.allowsColorChoice {
            Button {
                onSelectColor(seat.color)
            } label: {
                RemoteGameSeatView(seat: seat)
            }
            .buttonStyle(RemoteInviteSeatButtonStyle(isSelected: confirmation.localPlayerColor == seat.color))
        } else {
            RemoteGameSeatView(seat: seat)
        }
    }

    private static var panelBackground: Color {
        Color(red: 1.00, green: 0.98, blue: 0.92)
    }
}

private struct RemoteInviteSeatButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppTheme.boardFrame : Color.clear, lineWidth: 3)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

private struct RemoteInviteCancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.panelInset)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
    }
}
