import SwiftUI

struct RemoteGameStartAnnouncementView: View {
    let announcement: RemoteGameStartAnnouncement
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text(announcement.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: 14) {
                RemoteGameSeatView(seat: announcement.whiteSeat)
                RemoteGameSeatView(seat: announcement.blackSeat)
            }

            Button(announcement.buttonTitle) {
                onStart()
            }
            .buttonStyle(RemoteGameStartButtonStyle())
            .accessibilityIdentifier("remote-game-start-button")
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
        .accessibilityIdentifier("remote-game-start-announcement")
    }

    private static var panelBackground: Color {
        Color(red: 1.00, green: 0.98, blue: 0.92)
    }
}

struct RemoteGameSeatView: View {
    let seat: RemoteGameSeat

    var body: some View {
        VStack(spacing: 10) {
            PieceIconView(piece: Piece(kind: .king, color: seat.color))
                .frame(width: 76, height: 76)
                .padding(10)
                .background(squareColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.boardFrame.opacity(0.18), lineWidth: 1)
                }

            VStack(spacing: 3) {
                Text(seat.color.rawValue.capitalized)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)

                Text(seat.playerName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.panelWarmth.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.panelStroke, lineWidth: 1)
        }
    }

    private var squareColor: Color {
        switch seat.squareTone {
        case .light:
            AppTheme.lightSquare.opacity(0.74)
        case .dark:
            AppTheme.darkSquare.opacity(0.72)
        }
    }
}

struct RemoteGameStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.whitePiece)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.boardFrame)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.86), value: configuration.isPressed)
    }
}
