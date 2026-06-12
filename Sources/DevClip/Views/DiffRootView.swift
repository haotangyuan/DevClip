import DevClipCore
import SwiftUI

struct DiffRootView: View {
    @StateObject private var viewModel: DiffRootViewModel

    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: DiffRootViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    DevClipSectionHeader(title: "旧记录", systemImage: "doc.text")
                    Picker("", selection: $viewModel.oldEntryID) {
                        ForEach(viewModel.entries) { entry in
                            Text(entry.title).tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 200)
                }

                VStack(alignment: .leading, spacing: 4) {
                    DevClipSectionHeader(title: "新记录", systemImage: "doc.text")
                    Picker("", selection: $viewModel.newEntryID) {
                        ForEach(viewModel.entries) { entry in
                            Text(entry.title).tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 200)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("")
                        .font(.system(size: 13))
                    Button {
                        Task { @MainActor in
                            await viewModel.compare()
                        }
                    } label: {
                        Label("对比", systemImage: "square.split.2x1")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()
            }
            .padding(16)

            Divider()

            // Diff stats
            if let result = viewModel.result {
                HStack(spacing: 12) {
                    Label("\(result.addedCount) 行新增", systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Label("\(result.removedCount) 行删除", systemImage: "minus.circle.fill")
                        .foregroundStyle(.red)
                    Spacer()
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }

            // Diff content
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.result?.lines ?? []) { line in
                        DiffLineRow(line: line)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))

            // Status bar
            if !viewModel.statusMessage.isEmpty {
                Divider()
                HStack {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.thinMaterial.opacity(0.5))
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.load()
        }
    }
}

// MARK: - Diff Line Row

private struct DiffLineRow: View {
    var line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Prefix indicator
            Text(prefix)
                .foregroundStyle(.white)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 24, alignment: .center)
                .padding(.vertical, 2)
                .background(prefixBackground)

            // Line numbers
            Text(lineNumberText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.horizontal, 8)

            // Content
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
        .background(rowBackground)
    }

    private var prefix: String {
        switch line.kind {
        case .unchanged: " "
        case .added: "+"
        case .removed: "-"
        }
    }

    private var prefixBackground: Color {
        switch line.kind {
        case .unchanged: .secondary.opacity(0.3)
        case .added: .green
        case .removed: .red
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .unchanged: .clear
        case .added: .green.opacity(0.08)
        case .removed: .red.opacity(0.08)
        }
    }

    private var lineNumberText: String {
        let oldNumber = line.oldLineNumber.map(String.init) ?? "-"
        let newNumber = line.newLineNumber.map(String.init) ?? "-"
        return "\(oldNumber) / \(newNumber)"
    }
}

// MARK: - View Model

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
