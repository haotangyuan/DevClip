import AppKit
import DevClipCore
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case pinned
        case sensitive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                "历史"
            case .pinned:
                "固定"
            case .sensitive:
                "敏感"
            }
        }

        var iconName: String {
            switch self {
            case .all:
                "clock"
            case .pinned:
                "pin"
            case .sensitive:
                "lock.shield"
            }
        }
    }

    @Published var queryText = ""
    @Published var scope: Scope = .all
    @Published var selectedEntryID: UUID?
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var statusMessage = ""
    @Published private(set) var thumbnailImage: NSImage?

    private var allEntries: [ClipboardEntry] = []
    private let parser = SearchQueryParser()
    private let repository: any ClipboardRepository
    private let searchService: any SearchService
    private let pasteEngine: PasteEngine
    private let blobStore: (any BlobStore)?
    private var searchTask: Task<Void, Never>?

    init(dependencies: DependencyContainer) {
        self.repository = dependencies.repository
        self.searchService = dependencies.searchService
        self.pasteEngine = dependencies.pasteEngine
        self.blobStore = dependencies.blobStore
    }

    var selectedEntry: ClipboardEntry? {
        guard let selectedEntryID else {
            return entries.first
        }

        return entries.first { $0.id == selectedEntryID } ?? entries.first
    }

    var counts: [Scope: Int] {
        [
            .all: allEntries.count,
            .pinned: allEntries.filter(\.isPinned).count,
            .sensitive: allEntries.filter(\.isSensitive).count
        ]
    }

    func load() async {
        await refresh()
    }

    func debouncedRefresh() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        do {
            let loaded: [ClipboardEntry]
            if queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loaded = Array(try await repository.entries().reversed())
            } else {
                let query = try parser.parse(queryText)
                loaded = try await searchService.search(query, currentAppBundleIdentifier: nil)
                    .map(\.entry)
            }

            allEntries = loaded
            entries = applyScope(loaded)
            if selectedEntryID == nil || !entries.contains(where: { $0.id == selectedEntryID }) {
                selectedEntryID = entries.first?.id
            }
            statusMessage = entries.isEmpty ? "没有匹配记录" : "\(entries.count) 条记录"
        } catch {
            entries = []
            selectedEntryID = nil
            statusMessage = "加载失败：\(error.localizedDescription)"
        }
    }

    func setScope(_ nextScope: Scope) async {
        scope = nextScope
        await refresh()
    }

    func togglePinned() async {
        guard let entry = selectedEntry else {
            statusMessage = "没有可固定的记录"
            return
        }

        do {
            try await repository.setPinned(!entry.isPinned, entryID: entry.id)
            statusMessage = entry.isPinned ? "已取消固定" : "已固定"
            await refresh()
        } catch {
            statusMessage = "固定失败：\(error.localizedDescription)"
        }
    }

    func deleteSelected() async {
        guard let entry = selectedEntry else {
            statusMessage = "没有可删除的记录"
            return
        }

        do {
            try await repository.deleteEntry(id: entry.id)
            statusMessage = "已删除"
            await refresh()
        } catch {
            statusMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func copySelectedOriginal() async {
        guard let entry = selectedEntry else {
            statusMessage = "没有可复制的记录"
            return
        }

        do {
            try await pasteEngine.perform(PasteRequest(entryID: entry.id, mode: .copyOnly))
            statusMessage = "已复制原始格式"
        } catch {
            statusMessage = "复制失败：\(error.localizedDescription)"
        }
    }

    func pasteSelectedPlainText() async {
        guard let entry = selectedEntry else {
            statusMessage = "没有可粘贴的记录"
            return
        }

        do {
            let result = try await pasteEngine.perform(
                PasteRequest(entryID: entry.id, mode: .pastePlainText)
            )
            statusMessage = result.didPaste ? "已自动粘贴纯文本" : "已复制纯文本"
        } catch {
            statusMessage = "粘贴失败：\(error.localizedDescription)"
        }
    }

    func loadThumbnail(for entry: ClipboardEntry) async {
        guard entry.detectedKind == .image, let blobStore else {
            thumbnailImage = nil
            return
        }

        // Try thumbnail path first, fall back to main blob path
        let path = entry.metadata.values["thumbnailBlobPath"]
            ?? entry.metadata.values["blobPath"]

        guard let path else {
            thumbnailImage = nil
            return
        }

        do {
            let data = try await blobStore.load(relativePath: path)
            thumbnailImage = NSImage(data: data)
        } catch {
            thumbnailImage = nil
        }
    }

    func loadThumbnailForRow(entry: ClipboardEntry) async -> NSImage? {
        guard entry.detectedKind == .image, let blobStore else { return nil }
        let path = entry.metadata.values["thumbnailBlobPath"]
            ?? entry.metadata.values["blobPath"]
        guard let path else { return nil }
        do {
            let data = try await blobStore.load(relativePath: path)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    private func applyScope(_ values: [ClipboardEntry]) -> [ClipboardEntry] {
        switch scope {
        case .all:
            values
        case .pinned:
            values.filter(\.isPinned)
        case .sensitive:
            values.filter(\.isSensitive)
        }
    }
}
