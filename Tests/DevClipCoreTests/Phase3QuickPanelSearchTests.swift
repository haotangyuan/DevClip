import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 3 Quick Panel And Search Tests")
struct Phase3QuickPanelSearchTests {
    @Test
    func searchQueryParserExtractsTermsPhrasesAndFilters() throws {
        let parser = SearchQueryParser()

        let query = try parser.parse(
            #""exact phrase" type:json app:"Visual Studio Code" is:pinned is:sensitive before:2026-06-01 after:2026-01-01 #api token"#
        )

        #expect(query.terms == ["token"])
        #expect(query.exactPhrases == ["exact phrase"])
        #expect(query.filters.contains(.type(.json)))
        #expect(query.filters.contains(.app("Visual Studio Code")))
        #expect(query.filters.contains(.pinned(true)))
        #expect(query.filters.contains(.sensitive(true)))
        #expect(query.filters.contains(.tag("api")))
        #expect(query.filters.contains { filter in
            if case .before = filter {
                return true
            }
            return false
        })
        #expect(query.filters.contains { filter in
            if case .after = filter {
                return true
            }
            return false
        })
    }

    @Test
    func unknownFiltersRemainSearchTerms() throws {
        let parser = SearchQueryParser()

        let query = try parser.parse("type:notARealType app:")

        #expect(query.terms == ["type:notARealType", "app:"])
        #expect(query.filters.isEmpty)
    }

    @Test
    func searchServiceAppliesTextAndStructuredFilters() async throws {
        let repository = InMemoryClipboardRepository()
        let searchService = SQLiteSearchService(repository: repository)
        let parser = SearchQueryParser()
        let group = ClipboardGroup(sourceAppName: "Xcode", itemCount: 2)
        let sourceEntry = makeEntry(
            groupID: group.id,
            title: "Swift URL Helper",
            kind: .sourceCode,
            sourceAppName: "Xcode",
            sourceBundleIdentifier: "com.apple.dt.Xcode",
            searchableText: "func normalizeURL(_ value: String) -> URL?",
            contentHash: "sha256:phase3-source",
            isPinned: true,
            metadata: ClipboardMetadata(values: ["tags": "api,swift"])
        )
        let jsonEntry = makeEntry(
            groupID: group.id,
            title: "JSON Payload",
            kind: .json,
            sourceAppName: "Terminal",
            sourceBundleIdentifier: "com.apple.Terminal",
            searchableText: #"{"hello":"world"}"#,
            contentHash: "sha256:phase3-json",
            isSensitive: true
        )

        try await repository.save(group: group, entries: [sourceEntry, jsonEntry], representations: [])

        let query = try parser.parse("url type:sourceCode app:Xcode is:pinned #api")
        let results = try await searchService.search(
            query,
            currentAppBundleIdentifier: "com.apple.dt.Xcode"
        )

        #expect(results.map(\.entry.id) == [sourceEntry.id])
    }

    @Test
    func shortQueriesFallBackToModelFiltering() async throws {
        let repository = InMemoryClipboardRepository()
        let searchService = SQLiteSearchService(repository: repository)
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "中文路径",
            searchableText: "/Users/dev/项目",
            contentHash: "sha256:phase3-short"
        )

        try await repository.save(group: group, entries: [entry], representations: [])

        let results = try await searchService.search(
            SearchQuery(terms: ["项目"]),
            currentAppBundleIdentifier: nil
        )

        #expect(results.map(\.entry.id) == [entry.id])
    }

    @Test
    func repositorySetPinnedUpdatesSavedEntry() async throws {
        let repository = InMemoryClipboardRepository()
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "待固定",
            searchableText: "pin me",
            contentHash: "sha256:phase3-pin"
        )

        try await repository.save(group: group, entries: [entry], representations: [])
        try await repository.setPinned(true, entryID: entry.id)

        let updated = try await repository.entry(id: entry.id)

        #expect(updated?.isPinned == true)
    }

    @Test
    func pasteEngineCopyOnlyWritesOriginalRepresentationsAndRecordsGuard() async throws {
        let repository = InMemoryClipboardRepository()
        let pasteboardClient = RecordingPasteboardClient(changeCount: 99)
        let writeGuard = ClipboardWriteGuard()
        let pasteEngine = PasteEngine(
            repository: repository,
            pasteboardClient: pasteboardClient,
            writeGuard: writeGuard
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "复制",
            searchableText: "copy original",
            contentHash: "sha256:phase3-copy"
        )
        let representation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: "public.utf8-plain-text",
            uniformTypeIdentifier: "public.utf8-plain-text",
            storageKind: .inlineData,
            inlineData: Data("copy original".utf8),
            byteCount: 13,
            textEncoding: "utf-8"
        )

        try await repository.save(group: group, entries: [entry], representations: [representation])
        try await pasteEngine.perform(PasteRequest(entryID: entry.id, mode: .copyOnly))

        let request = await pasteboardClient.lastRequest()
        let shouldIgnore = try await writeGuard.shouldIgnore(
            changeCount: 99,
            contentHash: entry.contentHash
        )

        #expect(request?.contentHash == entry.contentHash)
        #expect(request?.items.first?.representations.first?.data == Data("copy original".utf8))
        #expect(shouldIgnore)
    }
}

private actor RecordingPasteboardClient: PasteboardClient {
    private let fixedChangeCount: Int
    private var request: PasteboardWriteRequest?

    init(changeCount: Int) {
        self.fixedChangeCount = changeCount
    }

    func changeCount() async throws -> Int {
        fixedChangeCount
    }

    func readSnapshot() async throws -> ClipboardSnapshot {
        ClipboardSnapshot(changeCount: fixedChangeCount, items: [])
    }

    func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt {
        self.request = request
        return PasteboardWriteReceipt(
            transactionID: request.transactionID,
            changeCount: fixedChangeCount
        )
    }

    func lastRequest() -> PasteboardWriteRequest? {
        request
    }
}

private func makeEntry(
    groupID: UUID,
    title: String,
    kind: ClipboardContentKind = .plainText,
    sourceAppName: String? = "测试应用",
    sourceBundleIdentifier: String? = "dev.local.Tests",
    searchableText: String,
    contentHash: String,
    isPinned: Bool = false,
    isSensitive: Bool = false,
    metadata: ClipboardMetadata = ClipboardMetadata()
) -> ClipboardEntry {
    ClipboardEntry(
        groupID: groupID,
        title: title,
        detectedKind: kind,
        sourceAppName: sourceAppName,
        sourceBundleIdentifier: sourceBundleIdentifier,
        contentHash: contentHash,
        searchableText: searchableText,
        previewText: searchableText,
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 10),
        copyCount: 1,
        isPinned: isPinned,
        isSensitive: isSensitive,
        byteCount: Int64(searchableText.utf8.count),
        metadata: metadata
    )
}
