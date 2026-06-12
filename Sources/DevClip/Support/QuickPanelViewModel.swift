import Combine
import DevClipCore
import Foundation

@MainActor
final class QuickPanelViewModel: ObservableObject {
    enum Mode: String {
        case history
        case actions
        case diff
    }

    @Published var queryText = ""
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var smartActions: [TransformDefinition] = []
    @Published private(set) var selectedActionIndex = 0
    @Published private(set) var actionPreviewText = ""
    @Published private(set) var diffPreviewText = ""
    @Published private(set) var diffBaseTitle: String?
    @Published private(set) var statusMessage = ""
    @Published var isPreviewVisible = false
    @Published private(set) var mode: Mode = .history

    private let parser: any SearchQueryParsing
    private let searchService: any SearchService
    private let repository: any ClipboardRepository
    private let pasteEngine: PasteEngine
    private let transformEngine: TransformEngine
    private let diffService: any DiffService
    private var currentAppBundleIdentifier: String?
    private var diffBaseEntry: ClipboardEntry?

    init(
        parser: any SearchQueryParsing = SearchQueryParser(),
        searchService: any SearchService,
        repository: any ClipboardRepository,
        pasteEngine: PasteEngine,
        transformEngine: TransformEngine,
        diffService: any DiffService
    ) {
        self.parser = parser
        self.searchService = searchService
        self.repository = repository
        self.pasteEngine = pasteEngine
        self.transformEngine = transformEngine
        self.diffService = diffService
    }

    var selectedResult: SearchResult? {
        guard results.indices.contains(selectedIndex) else {
            return nil
        }

        return results[selectedIndex]
    }

    var hasSelection: Bool {
        selectedResult != nil
    }

    var selectedAction: TransformDefinition? {
        guard smartActions.indices.contains(selectedActionIndex) else {
            return nil
        }

        return smartActions[selectedActionIndex]
    }

    var previewText: String {
        if !diffPreviewText.isEmpty {
            return diffPreviewText
        }

        if !actionPreviewText.isEmpty {
            return actionPreviewText
        }

        return selectedResult?.entry.previewText ?? ""
    }

    func prepareForPresentation(currentAppBundleIdentifier: String?) async {
        self.currentAppBundleIdentifier = currentAppBundleIdentifier
        mode = .history
        isPreviewVisible = false
        actionPreviewText = ""
        diffPreviewText = ""
        diffBaseEntry = nil
        diffBaseTitle = nil
        await refresh()
    }

    func updateQuery(_ query: String) async {
        queryText = query
        await refresh()
    }

    func refresh() async {
        do {
            let query = try parser.parse(queryText)
            results = try await searchService.search(
                query,
                currentAppBundleIdentifier: currentAppBundleIdentifier
            )
            clampSelection()
            if mode == .actions {
                await loadSmartActions()
            }
            statusMessage = results.isEmpty ? "暂无匹配记录" : "\(results.count) 条结果"
        } catch {
            results = []
            selectedIndex = 0
            statusMessage = "搜索失败：\(error.localizedDescription)"
        }
    }

    func selectNext() {
        guard mode != .actions else {
            selectNextAction()
            return
        }

        guard !results.isEmpty else {
            return
        }

        selectedIndex = min(selectedIndex + 1, results.count - 1)
    }

    func selectPrevious() {
        guard mode != .actions else {
            selectPreviousAction()
            return
        }

        guard !results.isEmpty else {
            return
        }

        selectedIndex = max(selectedIndex - 1, 0)
    }

    func select(index: Int) {
        guard results.indices.contains(index) else {
            return
        }

        selectedIndex = index
    }

    func selectAction(index: Int) {
        guard smartActions.indices.contains(index) else {
            return
        }

        selectedActionIndex = index
    }

    func selectNextAction() {
        guard !smartActions.isEmpty else {
            return
        }

        selectedActionIndex = min(selectedActionIndex + 1, smartActions.count - 1)
    }

    func selectPreviousAction() {
        guard !smartActions.isEmpty else {
            return
        }

        selectedActionIndex = max(selectedActionIndex - 1, 0)
    }

    func copySelectedOriginal() async -> Bool {
        guard let entry = selectedResult?.entry else {
            statusMessage = "没有可复制的记录"
            return false
        }

        do {
            try await pasteEngine.perform(PasteRequest(entryID: entry.id, mode: .copyOnly))
            statusMessage = "已复制原始格式"
            return true
        } catch {
            statusMessage = "复制失败：\(error.localizedDescription)"
            return false
        }
    }

    func pasteSelectedOriginal(targetApplication: PasteTargetApplication?) async -> Bool {
        guard let entry = selectedResult?.entry else {
            statusMessage = "没有可粘贴的记录"
            return false
        }

        do {
            let result = try await pasteEngine.perform(
                PasteRequest(
                    entryID: entry.id,
                    mode: .pasteOriginal,
                    targetApplication: targetApplication
                )
            )
            statusMessage = pasteStatusMessage(result)
            return true
        } catch {
            statusMessage = "粘贴失败：\(error.localizedDescription)"
            return false
        }
    }

    func pasteSelectedPlainText(targetApplication: PasteTargetApplication?) async -> Bool {
        guard let entry = selectedResult?.entry else {
            statusMessage = "没有可粘贴的记录"
            return false
        }

        do {
            let result = try await pasteEngine.perform(
                PasteRequest(
                    entryID: entry.id,
                    mode: .pastePlainText,
                    targetApplication: targetApplication
                )
            )
            statusMessage = pasteStatusMessage(result)
            return true
        } catch {
            statusMessage = "粘贴失败：\(error.localizedDescription)"
            return false
        }
    }

    func deleteSelected() async {
        guard let entry = selectedResult?.entry else {
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

    func togglePinned() async {
        guard let entry = selectedResult?.entry else {
            statusMessage = "没有可固定的记录"
            return
        }

        let nextValue = !entry.isPinned

        do {
            try await repository.setPinned(nextValue, entryID: entry.id)
            statusMessage = nextValue ? "已固定" : "已取消固定"
            await refresh()
        } catch {
            statusMessage = "固定失败：\(error.localizedDescription)"
        }
    }

    func togglePreview() {
        isPreviewVisible.toggle()
    }

    func showActionMode() async {
        mode = .actions
        diffPreviewText = ""
        diffBaseEntry = nil
        diffBaseTitle = nil
        await loadSmartActions()
    }

    func showDiffMode() async {
        guard let selectedEntry = selectedResult?.entry else {
            statusMessage = "请选择一条记录作为差异输入"
            return
        }

        mode = .diff
        actionPreviewText = ""

        guard let baseEntry = diffBaseEntry else {
            diffBaseEntry = selectedEntry
            diffBaseTitle = selectedEntry.title
            diffPreviewText = ""
            statusMessage = "已选择旧记录，请选择新记录后再次按 Command+D"
            return
        }

        guard baseEntry.id != selectedEntry.id else {
            statusMessage = "请选择另一条记录进行对比"
            return
        }

        do {
            let result = try await diffService.diff(
                oldText: textForDiff(baseEntry),
                newText: textForDiff(selectedEntry)
            )
            diffPreviewText = preview(from: result)
            isPreviewVisible = true
            statusMessage = "差异完成：新增 \(result.addedCount) 行，删除 \(result.removedCount) 行"
            diffBaseEntry = nil
            diffBaseTitle = nil
        } catch {
            statusMessage = "差异失败：\(error.localizedDescription)"
        }
    }

    func toggleMode() async {
        switch mode {
        case .history:
            await showActionMode()
        case .actions:
            mode = .history
            statusMessage = results.isEmpty ? "暂无匹配记录" : "\(results.count) 条结果"
        case .diff:
            await showActionMode()
        }
    }

    func executeSelectedAction(copyResult: Bool) async -> Bool {
        guard let action = selectedAction, let entry = selectedResult?.entry else {
            statusMessage = "没有可执行的动作"
            return false
        }

        do {
            let input = try await transformInput(for: entry)
            let result = try await transformEngine.execute(actionID: action.id, input: input)
            actionPreviewText = transformPreviewText(result)
            isPreviewVisible = true

            if copyResult {
                try await saveAndCopy(result: result, sourceEntry: entry, action: action)
                statusMessage = "已执行并写回剪贴板"
            } else {
                statusMessage = "预览完成，原记录未修改"
            }

            return true
        } catch {
            statusMessage = "动作失败：\(error.localizedDescription)"
            return false
        }
    }

    private func clampSelection() {
        if results.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(max(selectedIndex, 0), results.count - 1)
        }
    }

    private func loadSmartActions() async {
        guard let entry = selectedResult?.entry else {
            smartActions = []
            selectedActionIndex = 0
            actionPreviewText = ""
            statusMessage = "没有可用动作"
            return
        }

        do {
            let input = try await transformInput(for: entry)
            smartActions = try await transformEngine.smartActions(for: input)
            selectedActionIndex = min(selectedActionIndex, max(smartActions.count - 1, 0))
            actionPreviewText = ""
            statusMessage = smartActions.isEmpty ? "当前内容没有可用动作" : "\(smartActions.count) 个可用动作"
        } catch {
            smartActions = []
            selectedActionIndex = 0
            statusMessage = "加载动作失败：\(error.localizedDescription)"
        }
    }

    private func transformInput(for entry: ClipboardEntry) async throws -> TransformInput {
        let representations = try await repository.representations(entryID: entry.id)
        let data = representations
            .filter { !PasteboardInternalTypes.isInternal($0.pasteboardType) }
            .sorted { $0.priority < $1.priority }
            .compactMap(\.inlineData)
            .first ?? Data(textForDiff(entry).utf8)

        return TransformInput(
            kind: entry.detectedKind,
            data: data,
            text: textForDiff(entry),
            metadata: entry.metadata
        )
    }

    private func saveAndCopy(
        result: TransformResult,
        sourceEntry: ClipboardEntry,
        action: TransformDefinition
    ) async throws {
        let representationSnapshot = PasteboardRepresentationSnapshot(
            pasteboardType: pasteboardType(for: result),
            uniformTypeIdentifier: pasteboardType(for: result),
            data: result.data
        )
        let contentHash = ClipboardContentHasher.hash(
            item: PasteboardItemSnapshot(representations: [representationSnapshot])
        )
        let group = ClipboardGroup(
            sourceAppName: "DevClip",
            sourceBundleIdentifier: "dev.local.DevClip",
            itemCount: 1,
            metadata: ClipboardMetadata(values: [
                "derivedFromEntryID": sourceEntry.id.uuidString,
                "transformActionID": action.id
            ])
        )
        let entry = ClipboardEntry(
            groupID: group.id,
            title: "\(action.displayName)：\(sourceEntry.title)",
            detectedKind: result.outputKind,
            sourceAppName: "DevClip",
            sourceBundleIdentifier: "dev.local.DevClip",
            contentHash: contentHash,
            searchableText: String(data: result.data, encoding: .utf8) ?? result.previewText,
            previewText: result.previewText,
            byteCount: Int64(result.data.count),
            metadata: ClipboardMetadata(values: [
                "derivedFromEntryID": sourceEntry.id.uuidString,
                "transformActionID": action.id,
                "shouldIndex": "true"
            ])
        )
        let representation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: representationSnapshot.pasteboardType,
            uniformTypeIdentifier: representationSnapshot.uniformTypeIdentifier,
            storageKind: .inlineData,
            inlineData: result.data,
            byteCount: Int64(result.data.count),
            textEncoding: String(data: result.data, encoding: .utf8) == nil ? nil : "utf-8"
        )

        try await repository.save(group: group, entries: [entry], representations: [representation])
        try await pasteEngine.perform(PasteRequest(entryID: entry.id, mode: .copyOnly))
    }

    private func pasteboardType(for result: TransformResult) -> String {
        switch result.outputKind {
        case .image:
            "public.png"
        case .binary:
            "public.data"
        default:
            "public.utf8-plain-text"
        }
    }

    private func transformPreviewText(_ result: TransformResult) -> String {
        let notice = result.metadata.values["warning"] ?? result.metadata.values["notice"]
        return [notice, result.previewText]
            .compactMap { value in
                guard let value, !value.isEmpty else {
                    return nil
                }

                return value
            }
            .joined(separator: "\n\n")
    }

    private func textForDiff(_ entry: ClipboardEntry) -> String {
        entry.searchableText.isEmpty ? entry.previewText : entry.searchableText
    }

    private func preview(from result: DiffResult) -> String {
        result.lines.prefix(120).map { line in
            let marker: String
            switch line.kind {
            case .unchanged:
                marker = " "
            case .added:
                marker = "+"
            case .removed:
                marker = "-"
            }
            return "\(marker) \(line.text)"
        }.joined(separator: "\n")
    }

    private func pasteStatusMessage(_ result: PasteExecutionResult) -> String {
        if result.didPaste {
            return "已自动粘贴"
        }

        switch result.fallbackReason {
        case .automationDisabled:
            return "已复制，自动粘贴未启用"
        case .accessibilityPermissionDenied:
            return "已复制，需要辅助功能权限"
        case .noTargetApplication:
            return "已复制，未找到目标应用"
        case nil:
            return "已复制"
        }
    }
}
