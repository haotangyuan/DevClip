import SwiftUI

// MARK: - Background

struct DevClipWorkspaceBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

// MARK: - Panel Modifier

struct DevClipPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }
}

extension View {
    func devClipPanel() -> some View {
        modifier(DevClipPanelModifier())
    }
}

// MARK: - Card Modifier

struct DevClipCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }
}

extension View {
    func devClipCard() -> some View {
        modifier(DevClipCardModifier())
    }
}

// MARK: - Section Header

struct DevClipSectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
