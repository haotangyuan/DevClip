import DevClipCore
import SwiftUI

struct HistoryRootView: View {
    @StateObject private var viewModel: HistoryViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(dependencies: dependencies))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            listPane
            Divider()
            detailPane
        }
        .background(historyBackground)
        .frame(minWidth: 980, minHeight: 560)
        .task {
            await viewModel.load()
        }
    }

    private var historyBackground: some View {
        DevClipWorkspaceBackground()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DevClip", systemImage: "doc.on.clipboard")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 12)

            ForEach(HistoryViewModel.Scope.allCases) { scope in
                Button {
                    Task { @MainActor in
                        await viewModel.setScope(scope)
                    }
                } label: {
                    HStack {
                        Label(scope.title, systemImage: scope.iconName)
                        Spacer()
                        Text("\(viewModel.counts[scope] ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    if viewModel.scope == scope {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.thinMaterial)
                    }
                }
            }

            Spacer()

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .frame(width: 180)
    }

    private var listPane: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索历史、类型、来源应用", text: $viewModel.queryText)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.queryText) { _, _ in
                        viewModel.debouncedRefresh()
                    }
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            .devClipPanel()

            List(selection: $viewModel.selectedEntryID) {
                ForEach(viewModel.entries) { entry in
                    HistoryEntryRow(entry: entry)
                        .tag(Optional(entry.id))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(16)
        .frame(width: 360)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let entry = viewModel.selectedEntry {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            ClipboardKindPresentation.displayName(entry.detectedKind),
                            systemImage: ClipboardKindPresentation.iconName(entry.detectedKind)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(entry.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                    }

                    Spacer()

                    if entry.isSensitive {
                        Label("敏感", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                metadataGrid(entry)

                Text("预览")
                    .font(.headline)

                ScrollView {
                    Text(entry.previewText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .devClipPanel()

                HStack {
                    Button {
                        Task { @MainActor in await viewModel.copySelectedOriginal() }
                    } label: {
                        Label("复制原始格式", systemImage: "doc.on.doc")
                    }

                    Button {
                        Task { @MainActor in await viewModel.pasteSelectedPlainText() }
                    } label: {
                        Label("纯文本粘贴", systemImage: "textformat")
                    }

                    Spacer()

                    Button {
                        Task { @MainActor in await viewModel.togglePinned() }
                    } label: {
                        Label(entry.isPinned ? "取消固定" : "固定", systemImage: entry.isPinned ? "pin.slash" : "pin")
                    }

                    Button(role: .destructive) {
                        Task { @MainActor in await viewModel.deleteSelected() }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            .padding(22)
        } else {
            ContentUnavailableView("暂无历史", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metadataGrid(_ entry: ClipboardEntry) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                metadataItem("来源", entry.sourceAppName ?? "未知应用")
                metadataItem("大小", ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
            }
            GridRow {
                metadataItem("创建", entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                metadataItem("复制次数", "\(entry.copyCount)")
            }
        }
        .font(.caption)
    }

    private func metadataItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.tertiary)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct HistoryEntryRow: View {
    var entry: ClipboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(entry.detectedKind))
                .foregroundStyle(entry.isSensitive ? .orange : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(entry.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}
