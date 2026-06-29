import SwiftUI

enum SidebarPanelMetrics {
    static let contentPadding: CGFloat = 16
}

struct SidebarPanelView<Content: View>: View {
    let panelLength: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(SidebarPanelMetrics.contentPadding)
            .frame(width: panelLength, height: panelLength)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.panelWarmth)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.panelTopLight, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(AppTheme.panelStroke, lineWidth: 1)
                    }
                    .shadow(color: AppTheme.panelShadow, radius: 18, y: 8)
            )
    }
}
