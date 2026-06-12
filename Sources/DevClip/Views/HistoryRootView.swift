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
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 980, minHeight: 560)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("DevClip")
                    .font(.title2.weight(.bold))
            }
            .padding(.bottom, 16)
            .padding(.top, 4)

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
                            .background(
                                Capsule().fill(.quaternary)
                            )
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

            Spacer()

            Text(viewModel.statusMessage)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(width: 180)
        .background(.thinMaterial)
    }

    // MARK: - List Pane

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("搜索历史、类型、来源应用", text: $viewModel.queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onChange(of: viewModel.queryText) { _, _ in
                        viewModel.debouncedRefresh()
                    }
                if !viewModel.queryText.isEmpty {
                    Button {
                        viewModel.queryText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(selection: $viewModel.selectedEntryID) {
                ForEach(viewModel.entries) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        viewModel: viewModel
                    )
                    .tag(Optional(entry.id))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 360)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = viewModel.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: ClipboardKindPresentation.iconName(entry.detectedKind))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(entry.title)
                                .font(.system(size: 18, weight: .semibold))
                                .lineLimit(2)
                        }

                        Spacer()

                        if entry.isSensitive {
                            Label("敏感", systemImage: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(.orange.opacity(0.12))
                                )
                        }

                        if entry.isPinned {
                            Label("已固定", systemImage: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }

                    metadataBar(entry)
                }
                .padding(20)

                Divider()

                // Preview content
                detailContent(entry)

                Divider()

                // Action bar
                actionBar(entry)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: entry.id) { _, _ in
                Task { @MainActor in
                    await viewModel.loadThumbnail(for: entry)
                }
            }
            .task {
                await viewModel.loadThumbnail(for: entry)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("选择一条记录查看详情")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(_ entry: ClipboardEntry) -> some View {
        if entry.detectedKind == .image {
            imagePreview(entry)
        } else {
            textPreview(entry)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardEntry) -> some View {
        ScrollView([.vertical, .horizontal]) {
            if let image = viewModel.thumbnailImage {
                VStack(spacing: 0) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载图片中...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textPreview(_ entry: ClipboardEntry) -> some View {
        ScrollView {
            Text(entry.previewText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Metadata Bar

    private func metadataBar(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 16) {
            metadataChip("square.and.arrow.down", entry.sourceAppName ?? "未知应用")
            metadataChip("doc", ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
            metadataChip("clock", entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            metadataChip("repeat", "复制 \(entry.copyCount) 次")
            Spacer()
        }
    }

    private func metadataChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Action Bar

    private func actionBar(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { @MainActor in await viewModel.copySelectedOriginal() }
            } label: {
                Label("复制原始格式", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task { @MainActor in await viewModel.pasteSelectedPlainText() }
            } label: {
                Label("纯文本粘贴", systemImage: "textformat")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button {
                Task { @MainActor in await viewModel.togglePinned() }
            } label: {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(entry.isPinned ? "取消固定" : "固定")

            Button(role: .destructive) {
                Task { @MainActor in await viewModel.deleteSelected() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("删除")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }
}

// MARK: - History Entry Row

private struct HistoryEntryRow: View {
    var entry: ClipboardEntry
    @ObservedObject var viewModel: HistoryViewModel
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Thumbnail or icon
            Group {
                if entry.detectedKind == .image, let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(entry.detectedKind))
                        .font(.system(size: 14))
                        .foregroundStyle(entry.isSensitive ? .orange : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(entry.previewText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                    Text("·")
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let appName = entry.sourceAppName {
                        Text("·")
                        Text(appName)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .task(id: entry.id) {
            if entry.detectedKind == .image {
                thumbnail = await viewModel.loadThumbnailForRow(entry: entry)
            }
        }
    }
}
