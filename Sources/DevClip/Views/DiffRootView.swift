import DevClipCore
import SwiftUI

struct DiffRootView: View {
    @StateObject private var viewModel: DiffRootViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: DiffRootViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Picker("旧记录", selection: $viewModel.oldEntryID) {
                    ForEach(viewModel.entries) { entry in
                        Text(entry.title).tag(Optional(entry.id))
                    }
                }
                .frame(minWidth: 220)

                Picker("新记录", selection: $viewModel.newEntryID) {
                    ForEach(viewModel.entries) { entry in
                        Text(entry.title).tag(Optional(entry.id))
                    }
                }
                .frame(minWidth: 220)

                Button {
                    Task { @MainActor in
                        await viewModel.compare()
                    }
                } label: {
                    Label("对比", systemImage: "square.split.2x1")
                }

                Spacer()
            }

            if let result = viewModel.result {
                Text("新增 \(result.addedCount) 行，删除 \(result.removedCount) 行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.result?.lines ?? []) { line in
                        DiffLineRow(line: line)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .devClipPanel()

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 460)
        .background(DevClipWorkspaceBackground())
        .task {
            await viewModel.load()
        }
    }
}

private struct DiffLineRow: View {
    var line: DiffLine

    var body: some View {
        HStack(spacing: 8) {
            Text(prefix)
                .foregroundStyle(prefixColor)
                .frame(width: 18, alignment: .center)

            Text(lineNumberText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text(line.text.isEmpty ? " " : line.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private var prefix: String {
        switch line.kind {
        case .unchanged:
            " "
        case .added:
            "+"
        case .removed:
            "-"
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .unchanged:
            .secondary
        case .added:
            .green
        case .removed:
            .red
        }
    }

    private var lineNumberText: String {
        let oldNumber = line.oldLineNumber.map(String.init) ?? "-"
        let newNumber = line.newLineNumber.map(String.init) ?? "-"
        return "\(oldNumber) / \(newNumber)"
    }
}

@MainActor
final class DiffRootViewModel: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var oldEntryID: UUID?
    @Published var newEntryID: UUID?
    @Published private(set) var result: DiffResult?
    @Published private(set) var statusMessage = ""

    private let repository: any ClipboardRepository
    private let diffService: any DiffService

    init(dependencies: DependencyContainer) {
        self.repository = dependencies.repository
        self.diffService = dependencies.diffService
    }

    func load() async {
        do {
            entries = Array(try await repository.entries().reversed())
            oldEntryID = entries.dropFirst().first?.id ?? entries.first?.id
            newEntryID = entries.first?.id
            statusMessage = entries.count >= 2 ? "\(entries.count) 条可对比记录" : "至少需要两条历史记录"
            await compare()
        } catch {
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    func compare() async {
        guard
            let oldEntry = entry(id: oldEntryID),
            let newEntry = entry(id: newEntryID)
        else {
            result = nil
            return
        }

        do {
            result = try await diffService.diff(
                oldText: oldEntry.searchableText.isEmpty ? oldEntry.previewText : oldEntry.searchableText,
                newText: newEntry.searchableText.isEmpty ? newEntry.previewText : newEntry.searchableText
            )
            statusMessage = "对比完成"
        } catch {
            statusMessage = "对比失败：\(error.localizedDescription)"
        }
    }

    private func entry(id: UUID?) -> ClipboardEntry? {
        guard let id else {
            return nil
        }

        return entries.first { $0.id == id }
    }
}
