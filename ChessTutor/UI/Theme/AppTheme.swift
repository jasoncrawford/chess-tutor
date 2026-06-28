import SwiftUI

enum AppTheme {
    static let table = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let panel = Color(red: 1.00, green: 0.98, blue: 0.92).opacity(0.80)
    static let panelInset = Color(red: 0.38, green: 0.28, blue: 0.17).opacity(0.08)
    static let panelStroke = Color(red: 0.35, green: 0.28, blue: 0.20).opacity(0.12)
    static let panelShadow = Color.black.opacity(0.07)
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.11)
    static let mutedInk = Color(red: 0.43, green: 0.42, blue: 0.36)
    static let boardFrame = Color(red: 0.35, green: 0.28, blue: 0.20)
    static let lightSquare = Color(red: 0.91, green: 0.84, blue: 0.68)
    static let darkSquare = Color(red: 0.38, green: 0.55, blue: 0.43)
    static let selectedSquare = Color(red: 0.97, green: 0.74, blue: 0.27).opacity(0.72)
    static let legalMove = Color(red: 0.11, green: 0.39, blue: 0.66).opacity(0.38)
    static let captureMove = Color(red: 0.72, green: 0.23, blue: 0.17).opacity(0.62)
    static let check = Color(red: 0.85, green: 0.20, blue: 0.18).opacity(0.45)
    static let whitePiece = Color(red: 0.98, green: 0.94, blue: 0.84)
    static let blackPiece = Color(red: 0.17, green: 0.19, blue: 0.18)
}
