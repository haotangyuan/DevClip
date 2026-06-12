import Foundation
@preconcurrency import GRDB
@testable import DevClipCore
import Testing

@Suite("Phase 7 Stack Diff Pipeline Tests")
struct Phase7StackDiffPipelineTests {
    @Test
    func grdbStoresPersistStacksPipelinesAndSnippets() async throws {
        let directory = try Phase7TemporaryDirectory()
        let pool = try DatabaseBootstrap.makePool(
            at: directory.url.appendingPathComponent("devclip.sqlite").path
        )
        let stackStore = GRDBClipboardStackStore(databasePool: pool)
        let pipelineStore = GRDBTransformPipelineStore(databasePool: pool)
        let snippetStore = GRDBSnippetStore(databasePool: pool)
        let firstID = UUID()
        let secondID = UUID()
        let stack = ClipboardStack(
            name: "测试栈",
            entryIDs: [firstID, secondID],
            currentIndex: 1
        )
        let pipeline = TransformPipeline(
            name: "测试流水线",
            steps: [TransformStep(actionID: "text.trim", order: 0)]
        )
        let snippet = ClipboardSnippet(
            title: "测试片段",
            content: "let value = 1",
            kind: .sourceCode,
            tags: ["swift"]
        )

        try await stackStore.save(stack)
        try await pipelineStore.save(pipeline)
        try await snippetStore.save(snippet)

        let tableNames = try await pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        }

        #expect(tableNames.contains("snippets"))
        #expect(try await stackStore.stack(id: stack.id)?.currentIndex == 1)
        #expect(try await pipelineStore.pipeline(id: pipeline.id)?.steps.map(\.actionID) == ["text.trim"])
        #expect(try await snippetStore.snippet(id: snippet.id)?.tags == ["swift"])
    }

    @Test
    func sequentialPasteAdvancesStackAndWritesEntriesInOrder() async throws {
        let repository = InMemoryClipboardRepository()
        let pasteboardClient = RecordingPhase7PasteboardClient()
        let pasteEngine = PasteEngine(
            repository: repository,
            pasteboardClient: pasteboardClient,
            writeGuard: ClipboardWriteGuard(persistMarkers: false)
        )
        let stackStore = InMemoryClipboardStackStore()
        let stackService = ClipboardStackService(repository: repository, store: stackStore)
        let sequentialPasteService = SequentialPasteService(
            stackService: stackService,
            pasteEngine: pasteEngine
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 2)
        let first = makePhase7Entry(groupID: group.id, title: "第一", text: "one", hash: "sha256:phase7-one")
        let second = makePhase7Entry(groupID: group.id, title: "第二", text: "two", hash: "sha256:phase7-two")

        try await repository.save(
            group: group,
            entries: [first, second],
            representations: [
                phase7Representation(entryID: first.id, text: "one"),
                phase7Representation(entryID: second.id, text: "two")
            ]
        )
        let stack = try await stackService.createStack(name: "顺序", entryIDs: [first.id, second.id])

        let firstResult = try await sequentialPasteService.pasteNext(stackID: stack.id)
        let secondResult = try await sequentialPasteService.pasteNext(stackID: stack.id)
        let requests = await pasteboardClient.requests()
        let updatedStack = try await stackStore.stack(id: stack.id)

        #expect(firstResult.candidate.entryID == first.id)
        #expect(secondResult.candidate.entryID == second.id)
        #expect(requests.map { $0.items.first?.representations.first?.data } == [
            Data("one".utf8),
            Data("two".utf8)
        ])
        #expect(updatedStack?.currentIndex == 0)
    }

    @Test
    func lineDiffMarksAddedAndRemovedLines() async throws {
        let diffService = LineDiffService()

        let result = try await diffService.diff(
            oldText: "alpha\nbeta\ngamma",
            newText: "alpha\ndelta\ngamma\nomega"
        )

        #expect(result.addedCount == 2)
        #expect(result.removedCount == 1)
        #expect(result.lines.contains { line in
            line.kind == .removed && line.oldLineNumber == 2 && line.text == "beta"
        })
        #expect(result.lines.contains { line in
            line.kind == .added && line.newLineNumber == 2 && line.text == "delta"
        })
    }

    @Test
    func pipelinePreviewFailureDoesNotModifyOriginalEntry() async throws {
        let repository = InMemoryClipboardRepository()
        let previewService = PipelinePreviewService(
            repository: repository,
            transformEngine: TransformEngine()
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makePhase7Entry(
            groupID: group.id,
            title: "原始记录",
            text: "  keep  ",
            hash: "sha256:phase7-pipeline"
        )
        let failingPipeline = TransformPipeline(
            name: "失败流水线",
            steps: [TransformStep(actionID: "missing.action", order: 0)]
        )

        try await repository.save(
            group: group,
            entries: [entry],
            representations: [phase7Representation(entryID: entry.id, text: "  keep  ")]
        )

        await #expect(throws: Error.self) {
            _ = try await previewService.preview(pipeline: failingPipeline, entryID: entry.id)
        }

        let storedEntry = try await repository.entry(id: entry.id)

        #expect(storedEntry == entry)
    }

    @Test
    func snippetLibraryReturnsTransformInput() async throws {
        let store = InMemorySnippetStore()
        let library = SnippetLibrary(store: store)

        let snippet = try await library.save(
            title: "URL 片段",
            content: "https://example.com",
            kind: .url,
            tags: ["api"]
        )
        let input = try await library.transformInput(for: snippet.id)

        #expect(input.kind == .url)
        #expect(input.text == "https://example.com")
        #expect(input.metadata.values["snippetTitle"] == "URL 片段")
    }
}

private actor RecordingPhase7PasteboardClient: PasteboardClient {
    private var changeCountValue = 700
    private var recordedRequests: [PasteboardWriteRequest] = []

    func changeCount() async throws -> Int {
        changeCountValue
    }

    func readSnapshot() async throws -> ClipboardSnapshot {
        ClipboardSnapshot(changeCount: changeCountValue, items: [])
    }

    func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt {
        changeCountValue += 1
        recordedRequests.append(request)
        return PasteboardWriteReceipt(
            transactionID: request.transactionID,
            changeCount: changeCountValue
        )
    }

    func requests() -> [PasteboardWriteRequest] {
        recordedRequests
    }
}

private struct Phase7TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevClipPhase7Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func makePhase7Entry(
    groupID: UUID,
    title: String,
    text: String,
    hash: String
) -> ClipboardEntry {
    ClipboardEntry(
        groupID: groupID,
        title: title,
        detectedKind: .plainText,
        sourceAppName: "测试应用",
        sourceBundleIdentifier: "dev.local.Tests",
        contentHash: hash,
        searchableText: text,
        previewText: text,
        createdAt: Date(timeIntervalSince1970: 70),
        updatedAt: Date(timeIntervalSince1970: 70),
        byteCount: Int64(text.utf8.count)
    )
}

private func phase7Representation(entryID: UUID, text: String) -> ClipboardRepresentation {
    ClipboardRepresentation(
        entryID: entryID,
        pasteboardType: "public.utf8-plain-text",
        uniformTypeIdentifier: "public.utf8-plain-text",
        storageKind: .inlineData,
        inlineData: Data(text.utf8),
        byteCount: Int64(text.utf8.count),
        textEncoding: "utf-8"
    )
}
