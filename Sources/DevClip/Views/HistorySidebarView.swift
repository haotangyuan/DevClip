import SwiftUI

struct HistorySidebarView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            scopeButtons
            Spacer()
            statusText
        }
        .padding(16)
        .frame(width: 184)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("DevClip")
                .font(.title2.weight(.bold))
        }
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private var scopeButtons: some View {
        ForEach(HistoryViewModel.Scope.allCases) { scope in
            Button {
                Task { @MainActor in
                    await viewModel.setScope(scope)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: scope.iconName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(scope.title)
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(viewModel.counts[scope] ?? 0)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background {
                if viewModel.scope == scope {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                }
            }
        }
    }

    private var statusText: some View {
        Text(viewModel.statusMessage)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .lineLimit(2)
    }
}
