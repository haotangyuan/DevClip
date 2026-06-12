import DevClipCore
import SwiftUI

struct ClipboardStackRootView: View {
    @StateObject private var viewModel: ClipboardStackViewModel
    @State private var selection: UUID?

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: ClipboardStackViewModel(dependencies: dependencies))
    }

    var body: some View {
        TabView {
            stackTab
                .tabItem {
                    Label("栈", systemImage: "square.stack.3d.up")
                }

            snippetsTab
                .tabItem {
                    Label("片段", systemImage: "text.quote")
                }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 420)
        .background(DevClipWorkspaceBackground())
        .task {
            await viewModel.refresh()
            selection = viewModel.stacks.first?.id
        }
    }

    private var stackTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    Task { @MainActor in
                        selection = await viewModel.createStackFromRecentEntries()
                    }
                } label: {
                    Label("用最近记录创建栈", systemImage: "plus")
                }

                Button {
                    guard let selection else {
                        return
                    }

                    Task { @MainActor in
                        await viewModel.pasteNext(stackID: selection)
                    }
                } label: {
                    Label("粘贴下一个", systemImage: "arrow.down.doc")
                }
                .disabled(selection == nil)

                Spacer()
            }

            HStack(alignment: .top, spacing: 18) {
                List(selection: $selection) {
                    ForEach(viewModel.stacks) { stack in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stack.name)
                                .lineLimit(1)
                            Text("\(stack.entryIDs.count) 条记录，下一条：\(stack.currentIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(stack.id)
                    }
                }
                .frame(minWidth: 220)
                .scrollContentBackground(.hidden)

                stackDetail
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            statusText
        }
    }

    @ViewBuilder
    private var stackDetail: some View {
        if let stack = viewModel.stack(id: selection) {
            VStack(alignment: .leading, spacing: 10) {
                Text(stack.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                ForEach(Array(stack.entryIDs.enumerated()), id: \.element) { index, entryID in
                    HStack(spacing: 8) {
                        Text(index == stack.currentIndex ? "下一条" : "\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(index == stack.currentIndex ? .primary : .secondary)
                            .frame(width: 44, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.title(for: entryID))
                                .lineLimit(1)
                            Text(viewModel.preview(for: entryID))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Spacer()
            }
        } else {
            ContentUnavailableView("暂无剪贴板栈", systemImage: "square.stack.3d.up")
        }
    }

    private var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    Task { @MainActor in
                        await viewModel.saveLatestEntryAsSnippet()
                    }
                } label: {
                    Label("将最新记录保存为片段", systemImage: "plus")
                }

                Spacer()
            }

            List(viewModel.snippets) { snippet in
                VStack(alignment: .leading, spacing: 4) {
                    Text(snippet.title)
                        .lineLimit(1)
                    Text(snippet.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .scrollContentBackground(.hidden)

            statusText
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if !viewModel.statusMessage.isEmpty {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class ClipboardStackViewModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var stacks: [ClipboardStack] = []
    @Published private(set) var snippets: [ClipboardSnippet] = []
    @Published private(set) var statusMessage = ""

    private let repository: any ClipboardRepository
    private let stackService: ClipboardStackService
    private let sequentialPasteService: SequentialPasteService
    private let snippetLibrary: SnippetLibrary

    init(dependencies: DependencyContainer) {
        self.repository = dependencies.repository
        self.stackService = dependencies.clipboardStackService
        self.sequentialPasteService = dependencies.sequentialPasteService
        self.snippetLibrary = dependencies.snippetLibrary
    }

    func refresh() async {
        do {
            entries = Array(try await repository.entries().reversed())
            stacks = try await stackService.stacks()
            snippets = try await snippetLibrary.snippets()
            statusMessage = entries.isEmpty ? "暂无可用历史记录" : "\(entries.count) 条历史记录"
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    func createStackFromRecentEntries() async -> UUID? {
        let entryIDs = entries.prefix(5).map(\.id)
        guard !entryIDs.isEmpty else {
            statusMessage = "没有可加入栈的历史记录"
            return nil
        }

        do {
            let stack = try await stackService.createStack(
                name: "最近 \(entryIDs.count) 条",
                entryIDs: Array(entryIDs)
            )
            stacks = try await stackService.stacks()
            statusMessage = "已创建剪贴板栈"
            return stack.id
        } catch {
            statusMessage = "创建栈失败：\(error.localizedDescription)"
            return nil
        }
    }

    func pasteNext(stackID: UUID) async {
        do {
            let result = try await sequentialPasteService.pasteNext(stackID: stackID)
            stacks = try await stackService.stacks()
            statusMessage = result.pasteResult.didPaste ? "已粘贴并移动到下一条" : "已复制并移动到下一条"
        } catch {
            statusMessage = "顺序粘贴失败：\(error.localizedDescription)"
        }
    }

    func saveLatestEntryAsSnippet() async {
        guard let entry = entries.first else {
            statusMessage = "没有可保存为片段的历史记录"
            return
        }

        do {
            _ = try await snippetLibrary.save(
                title: entry.title,
                content: entry.searchableText.isEmpty ? entry.previewText : entry.searchableText,
                kind: entry.detectedKind
            )
            snippets = try await snippetLibrary.snippets()
            statusMessage = "已保存片段"
        } catch {
            statusMessage = "保存片段失败：\(error.localizedDescription)"
        }
    }

    func stack(id: UUID?) -> ClipboardStack? {
        guard let id else {
            return nil
        }

        return stacks.first { $0.id == id }
    }

    func title(for entryID: UUID) -> String {
        entries.first { $0.id == entryID }?.title ?? "记录已不存在"
    }

    func preview(for entryID: UUID) -> String {
        entries.first { $0.id == entryID }?.previewText ?? ""
    }
}
