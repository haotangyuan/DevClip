import SwiftUI

struct DevClipWorkspaceBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor).opacity(0.30),
                    Color.orange.opacity(0.07),
                    Color.teal.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct DevClipPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
    }
}

extension View {
    func devClipPanel() -> some View {
        modifier(DevClipPanelModifier())
    }
}
