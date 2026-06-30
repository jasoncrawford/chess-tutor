import SwiftUI

enum SidebarPanelMetrics {
    static let contentPadding: CGFloat = 16
}

struct SidebarPanelView<Content: View>: View {
    let panelSize: CGSize
    @ViewBuilder var content: () -> Content

    init(panelLength: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.panelSize = CGSize(width: panelLength, height: panelLength)
        self.content = content
    }

    init(panelSize: CGSize, @ViewBuilder content: @escaping () -> Content) {
        self.panelSize = panelSize
        self.content = content
    }

    var body: some View {
        content()
            .padding(SidebarPanelMetrics.contentPadding)
            .frame(width: panelSize.width, height: panelSize.height)
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
