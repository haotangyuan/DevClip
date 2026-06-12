import DevClipCore
import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()

            switch viewModel.mode {
            case .actions:
                actionPanel
            case .history, .diff:
                resultList
            }

            if viewModel.isPreviewVisible {
                Divider()
                previewPane
            }

            Divider()
            statusBar
        }
        .frame(width: 740, height: viewModel.isPreviewVisible ? 600 : 470)
        .background(quickPanelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.focusTrigger) { _, _ in
            isSearchFocused = true
        }
        .onChange(of: viewModel.queryText) { _, newValue in
            Task {
                await viewModel.updateQuery(newValue)
            }
        }
    }

    private var quickPanelBackground: some View {
        DevClipWorkspaceBackground()
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索剪贴板", text: $viewModel.queryText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .font(.system(size: 18, weight: .medium, design: .default))

            if viewModel.mode == .diff, let title = viewModel.diffBaseTitle {
                Text("旧记录：\(title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results.indices, id: \.self) { index in
                        QuickPanelResultRow(
                            result: viewModel.results[index],
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.select(index: index)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .overlay {
                if viewModel.results.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "doc.on.clipboard")
                }
            }
            .onChange(of: viewModel.selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var actionPanel: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.smartActions.indices, id: \.self) { index in
                            QuickPanelActionRow(
                                action: viewModel.smartActions[index],
                                isSelected: index == viewModel.selectedActionIndex
                            )
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectAction(index: index)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .overlay {
                    if viewModel.smartActions.isEmpty {
                        ContentUnavailableView("没有可用动作", systemImage: "wand.and.stars")
                    }
                }
                .onChange(of: viewModel.selectedActionIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let action = viewModel.selectedAction {
                    Label(action.displayName, systemImage: "wand.and.stars")
                        .font(.headline)

                    Text(ClipboardKindPresentation.categoryName(action.category))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(action.isDestructive ? "破坏性动作" : "预览不会修改原记录")
                        .font(.caption)
                        .foregroundStyle(action.isDestructive ? .red : .secondary)

                    Spacer()
                } else {
                    ContentUnavailableView("选择动作", systemImage: "command")
                }
            }
            .padding(16)
            .frame(width: 260, alignment: .topLeading)
        }
    }

    private var previewPane: some View {
        ScrollView {
            Text(viewModel.previewText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(height: 150)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let entry = viewModel.selectedResult?.entry {
                Text(entry.sourceAppName ?? "未知应用")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct QuickPanelResultRow: View {
    var result: SearchResult
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(result.entry.detectedKind))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(result.entry.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(ClipboardKindPresentation.displayName(result.entry.detectedKind))
                    Text(result.entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let sourceAppName = result.entry.sourceAppName {
                        Text(sourceAppName)
                    }
                }
                .font(.caption2)
                .foregroundStyle(
                    isSelected ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(.tertiary)
                )
                .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
    }
}

private struct QuickPanelActionRow: View {
    var action: TransformDefinition
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(ClipboardKindPresentation.categoryName(action.category))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.76) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
    }
}
