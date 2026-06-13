import AppKit
import DevClipCore
import SwiftUI

struct HistoryListPaneView: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            entriesList
        }
        .frame(width: 372)
        .background(.thinMaterial)
    }

    private var searchBar: some View {
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
            clearButton
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
    }

    @ViewBuilder
    private var clearButton: some View {
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

    private var entriesList: some View {
        List(selection: $viewModel.selectedEntryID) {
            ForEach(viewModel.entries) { entry in
                HistoryEntryRow(entry: entry, viewModel: viewModel)
                    .tag(Optional(entry.id))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct HistoryEntryRow: View {
    var entry: ClipboardEntry
    @ObservedObject var viewModel: HistoryViewModel
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            iconOrThumbnail
            entryTexts
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .task(id: entry.id) {
            if entry.detectedKind == .image {
                thumbnail = await viewModel.loadThumbnailForRow(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var iconOrThumbnail: some View {
        if entry.detectedKind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: entry.isPinned ? "pin.fill" : ClipboardKindPresentation.iconName(entry.detectedKind))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                )
        }
    }

    private var entryTexts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(entry.previewText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            metadataLine
        }
    }

    private var metadataLine: some View {
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
}
