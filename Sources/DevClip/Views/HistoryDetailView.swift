import DevClipCore
import SwiftUI

struct HistoryDetailView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        if let entry = viewModel.selectedEntry {
            entryDetail(entry)
        } else {
            emptyState
        }
    }

    private func entryDetail(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(entry)
            Divider()
            detailContent(entry)
            Divider()
            actionBar(entry)
        }
        .background(.clear)
        .onChange(of: entry.id) { _, _ in
            Task { @MainActor in
                await viewModel.loadThumbnail(for: entry)
            }
        }
        .task {
            await viewModel.loadThumbnail(for: entry)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("选择一条记录查看详情")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
    }

    private func header(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    kindLabel(entry)
                    Text(entry.title)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                }
                Spacer()
                headerBadges(entry)
            }
            metadataBar(entry)
        }
        .padding(20)
    }

    private func kindLabel(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ClipboardKindPresentation.iconName(entry.detectedKind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(ClipboardKindPresentation.displayName(entry.detectedKind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func headerBadges(_ entry: ClipboardEntry) -> some View {
        if entry.isPinned {
            Label("已固定", systemImage: "pin.fill")
                .devClipStatusBadge(color: Color.accentColor)
        }
    }

    @ViewBuilder
    private func detailContent(_ entry: ClipboardEntry) -> some View {
        if entry.detectedKind == .image {
            imagePreview(entry)
        } else {
            textPreview(entry)
        }
    }

    private func imagePreview(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DevClipSectionHeader(title: "图片预览", systemImage: "photo")
                .padding(.horizontal, 20)
                .padding(.top, 18)
            imagePreviewBody
                .devClipPanel()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imagePreviewBody: some View {
        ScrollView([.vertical, .horizontal]) {
            if let image = viewModel.thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            } else {
                imagePreviewPlaceholder
            }
        }
    }

    private var imagePreviewPlaceholder: some View {
        VStack(spacing: 12) {
            if viewModel.imagePreviewMessage.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("加载图片中...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(viewModel.imagePreviewMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func textPreview(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DevClipSectionHeader(title: "内容预览", systemImage: "doc.text")
                .padding(.horizontal, 20)
                .padding(.top, 18)
            ScrollView {
                Text(entry.previewText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .devClipPanel()
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

private extension View {
    func devClipStatusBadge(color: Color) -> some View {
        font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
