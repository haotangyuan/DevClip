import DevClipCore
import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var viewModel: QuickPanelViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)

            switch viewModel.mode {
            case .actions:
                actionPanel
            case .history, .diff:
                resultList
            }

            if viewModel.isPreviewVisible {
                Divider().opacity(0.5)
                previewPane
            }

            Divider().opacity(0.5)
            statusBar
        }
        .frame(width: 740, height: viewModel.isPreviewVisible ? 600 : 470)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Rectangle().fill(.regularMaterial).opacity(0.7)
            }
        )
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))

            TextField("搜索剪贴板", text: $viewModel.queryText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium, design: .default))
                .focused($isSearchFocused)

            if !viewModel.queryText.isEmpty {
                Button {
                    viewModel.queryText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if viewModel.mode == .diff, let title = viewModel.diffBaseTitle {
                Text("旧记录：\(title)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Result List

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
                .padding(.vertical, 4)
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

    // MARK: - Action Panel

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
                    .padding(.vertical, 6)
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
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Label(action.displayName, systemImage: "")
                            .font(.system(size: 14, weight: .semibold))
                            .labelStyle(.titleOnly)
                    }

                    Text(ClipboardKindPresentation.categoryName(action.category))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(action.isDestructive ? "破坏性动作" : "预览不会修改原记录")
                        .font(.system(size: 11))
                        .foregroundStyle(action.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))

                    Spacer()
                } else {
                    ContentUnavailableView("选择动作", systemImage: "command")
                }
            }
            .padding(16)
            .frame(width: 260, alignment: .topLeading)
        }
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        ScrollView {
            Text(viewModel.previewText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(height: 150)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let entry = viewModel.selectedResult?.entry {
                HStack(spacing: 6) {
                    if let appName = entry.sourceAppName {
                        Text(appName)
                            .foregroundStyle(.tertiary)
                    }
                    Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.thinMaterial.opacity(0.5))
    }
}

// MARK: - Result Row

private struct QuickPanelResultRow: View {
    var result: SearchResult
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(result.entry.detectedKind))
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.system(size: 13))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(result.entry.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(ClipboardKindPresentation.displayName(result.entry.detectedKind))
                    Text(result.entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let sourceAppName = result.entry.sourceAppName {
                        Text(sourceAppName)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(
                    isSelected ? AnyShapeStyle(.white.opacity(0.72)) : AnyShapeStyle(.tertiary)
                )
                .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Action Row

private struct QuickPanelActionRow: View {
    var action: TransformDefinition
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(isSelected ? .white : .secondary)
                .font(.system(size: 13))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(ClipboardKindPresentation.categoryName(action.category))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.76) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
    }
}
