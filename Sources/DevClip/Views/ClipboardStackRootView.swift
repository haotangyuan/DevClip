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
        .formStyle(.grouped)
        .frame(minWidth: 680, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.refresh()
            selection = viewModel.stacks.first?.id
        }
    }

    // MARK: - Stack Tab

    private var stackTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in
                        selection = await viewModel.createStackFromRecentEntries()
                    }
                } label: {
                    Label("用最近记录创建栈", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    guard let selection else { return }
                    Task { @MainActor in
                        await viewModel.pasteNext(stackID: selection)
                    }
                } label: {
                    Label("粘贴下一个", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selection == nil)

                Spacer()
            }
            .padding(14)

            Divider()

            // Content
            HStack(spacing: 0) {
                // Stack list
                List(selection: $selection) {
                    ForEach(viewModel.stacks) { stack in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                                Text(stack.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                            HStack(spacing: 4) {
                                Text("\(stack.entryIDs.count) 条记录")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("下一条：\(stack.currentIndex + 1)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tag(stack.id)
                        .padding(.vertical, 2)
                    }
                }
                .frame(width: 220)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Stack detail
                stackDetail
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            }

            // Status
            if !viewModel.statusMessage.isEmpty {
                Divider()
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var stackDetail: some View {
        if let stack = viewModel.stack(id: selection) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(stack.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(stack.entryIDs.count) 条")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
                .padding(16)

                Divider()

                // Entries
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(stack.entryIDs.enumerated()), id: \.element) { index, entryID in
                            HStack(spacing: 10) {
                                // Index indicator
                                ZStack {
                                    Circle()
                                        .fill(index == stack.currentIndex ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                                        .frame(width: 24, height: 24)
                                    Text(index == stack.currentIndex ? "▶" : "\(index + 1)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(index == stack.currentIndex ? .white : .secondary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.title(for: entryID))
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Text(viewModel.preview(for: entryID))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if index == stack.currentIndex {
                                    Text("下一条")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(Color.accentColor.opacity(0.12))
                                        )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            if index < stack.entryIDs.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("暂无剪贴板栈")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("点击上方按钮从最近记录创建")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Snippets Tab

    private var snippetsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    Task { @MainActor in
                        await viewModel.saveLatestEntryAsSnippet()
                    }
                } label: {
                    Label("将最新记录保存为片段", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .padding(14)

            Divider()

            List(viewModel.snippets) { snippet in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                        Text(snippet.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(snippet.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.snippets.isEmpty {
                    ContentUnavailableView("暂无片段", systemImage: "text.quote")
                }
            }

            if !viewModel.statusMessage.isEmpty {
                Divider()
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial.opacity(0.5))
            }
        }
    }
}

// MARK: - View Model

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
