import Foundation
import CoreGraphics
@preconcurrency import GRDB
@testable import DevClipCore
import Testing

@Suite("Phase 2 Persistence Tests")
struct Phase2PersistenceTests {
    @Test
    func databaseMigrationCreatesRequiredTablesAndPragmas() async throws {
        let directory = try TemporaryDirectory()
        let pool = try DatabaseBootstrap.makePool(at: directory.url.appendingPathComponent("devclip.sqlite").path)

        let result = try await pool.read { db in
            let tableNames = try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type IN ('table', 'virtual')
                    ORDER BY name
                    """
            )
            let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys") ?? 0
            let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
            let ftsSQL = try String.fetchOne(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE name = 'clipboard_fts'"
            ) ?? ""

            return (Set(tableNames), foreignKeys, journalMode, ftsSQL)
        }

        #expect(result.0.contains("clipboard_entries"))
        #expect(result.0.contains("clipboard_representations"))
        #expect(result.0.contains("clipboard_groups"))
        #expect(result.0.contains("clipboard_fts"))
        #expect(result.0.contains("settings_metadata"))
        #expect(result.1 == 1)
        #expect(result.2.lowercased() == "wal")
        #expect(result.3.contains("tokenize = 'trigram'"))
    }

    @Test
    func grdbRepositoryPersistsEntriesAndMergesDuplicates() async throws {
        let directory = try TemporaryDirectory()
        let repository = try GRDBClipboardRepository(
            databasePath: directory.url.appendingPathComponent("devclip.sqlite").path
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "第一条",
            searchableText: "hello sqlite",
            contentHash: "sha256:duplicate"
        )
        let representation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: "public.utf8-plain-text",
            uniformTypeIdentifier: "public.utf8-plain-text",
            storageKind: .inlineData,
            inlineData: Data("hello sqlite".utf8),
            byteCount: 12,
            textEncoding: "utf-8"
        )
        let duplicate = makeEntry(
            groupID: UUID(),
            title: "重复",
            searchableText: "hello sqlite",
            contentHash: "sha256:duplicate",
            copyCount: 1
        )

        try await repository.save(group: group, entries: [entry], representations: [representation])
        try await repository.save(
            group: ClipboardGroup(sourceAppName: "测试应用", itemCount: 1),
            entries: [duplicate],
            representations: []
        )

        let entries = try await repository.entries()
        let representations = try await repository.representations(entryID: entry.id)
        let groups = try await repository.groups()

        #expect(entries.count == 1)
        #expect(entries.first?.copyCount == 2)
        #expect(representations.count == 1)
        #expect(representations.first?.inlineData == Data("hello sqlite".utf8))
        #expect(groups.count == 1)
    }

    @Test
    func ftsSearchFindsSubstringBackedByTrigramTokenizer() async throws {
        let directory = try TemporaryDirectory()
        let repository = try GRDBClipboardRepository(
            databasePath: directory.url.appendingPathComponent("devclip.sqlite").path
        )
        let group = ClipboardGroup(sourceAppName: "Xcode", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "Swift 片段",
            searchableText: "func encodeBase64(value: String) -> String",
            contentHash: "sha256:fts"
        )

        try await repository.save(group: group, entries: [entry], representations: [])

        let results = try await repository.searchFTS("Base64")

        #expect(results.map(\.id).contains(entry.id))
    }

    @Test
    func fileSystemBlobStoreDeletesOnlyOrphanedFiles() async throws {
        let directory = try TemporaryDirectory()
        let blobStore = FileSystemBlobStore(rootURL: directory.url.appendingPathComponent("Blobs"))

        let kept = try await blobStore.store(data: Data("keep".utf8), suggestedExtension: "bin")
        let orphaned = try await blobStore.store(data: Data("remove".utf8), suggestedExtension: "bin")

        try await blobStore.deleteOrphanedBlobs(referencedPaths: [kept.relativePath])

        let keptExists = await FileManager.default.fileExists(atPath: blobStore.url(for: kept).path)
        let orphanedExists = await FileManager.default.fileExists(atPath: blobStore.url(for: orphaned).path)

        #expect(keptExists)
        #expect(!orphanedExists)
    }

    @Test
    func blobStoreLoadsStoredData() async throws {
        let directory = try TemporaryDirectory()
        let blobStore = FileSystemBlobStore(rootURL: directory.url.appendingPathComponent("Blobs"))

        let descriptor = try await blobStore.store(data: Data("blob-body".utf8), suggestedExtension: "bin")
        let loaded = try await blobStore.load(relativePath: descriptor.relativePath)

        #expect(loaded == Data("blob-body".utf8))
    }

    @Test
    func imageClipboardSnapshotStoresBlobAndThumbnail() async throws {
        let directory = try TemporaryDirectory()
        let blobStore = FileSystemBlobStore(rootURL: directory.url.appendingPathComponent("Blobs"))
        let builder = ClipboardSnapshotBuilder(
            blobStore: blobStore,
            thumbnailGenerator: MockThumbnailGenerator()
        )
        let snapshot = ClipboardSnapshot(
            changeCount: 42,
            items: [
                PasteboardItemSnapshot(representations: [
                    PasteboardRepresentationSnapshot(
                        pasteboardType: "public.png",
                        uniformTypeIdentifier: "public.png",
                        data: Data("png-body".utf8)
                    )
                ])
            ],
            sourceAppName: "测试应用",
            sourceBundleIdentifier: "dev.local.Tests"
        )

        let result = await builder.build(from: snapshot)
        let entry = try #require(result.entries.first)
        let original = try #require(
            result.representations.first { $0.pasteboardType == "public.png" }
        )
        let thumbnail = try #require(
            result.representations.first { $0.pasteboardType == PasteboardInternalTypes.thumbnailPNG }
        )

        #expect(entry.detectedKind == .image)
        #expect(original.storageKind == .blobFile)
        #expect(thumbnail.storageKind == .blobFile)
        #expect(entry.metadata.values["thumbnailBlobPath"] == thumbnail.externalFilePath)
        #expect(try await blobStore.load(relativePath: try #require(original.externalFilePath)) == Data("png-body".utf8))
        #expect(try await blobStore.load(relativePath: try #require(thumbnail.externalFilePath)) == Data("thumb".utf8))
    }

    @Test
    func imagePreviewServiceLoadsInlineImageRepresentation() async throws {
        let repository = InMemoryClipboardRepository()
        let service = ClipboardImagePreviewService(repository: repository, blobStore: nil)
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "旧图片",
            kind: .image,
            searchableText: "图片",
            contentHash: "sha256:inline-image"
        )
        let representation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: "public.png",
            uniformTypeIdentifier: "public.png",
            storageKind: .inlineData,
            inlineData: Data("inline-image-data".utf8),
            byteCount: 17
        )

        try await repository.save(group: group, entries: [entry], representations: [representation])

        let data = try await service.imageData(for: entry, preferThumbnail: false)

        #expect(data == Data("inline-image-data".utf8))
    }

    @Test
    func imagePreviewServicePrefersThumbnailForRowsAndOriginalForDetail() async throws {
        let directory = try TemporaryDirectory()
        let blobStore = FileSystemBlobStore(rootURL: directory.url.appendingPathComponent("Blobs"))
        let repository = InMemoryClipboardRepository()
        let service = ClipboardImagePreviewService(repository: repository, blobStore: blobStore)
        let original = try await blobStore.store(data: Data("original-image-data".utf8), suggestedExtension: "png")
        let thumbnail = try await blobStore.store(data: Data("thumbnail-data".utf8), suggestedExtension: "png")
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "Blob 图片",
            kind: .image,
            searchableText: "图片",
            contentHash: "sha256:blob-image",
            metadata: ClipboardMetadata(values: [
                "blobPath": original.relativePath,
                "thumbnailBlobPath": thumbnail.relativePath
            ])
        )
        let originalRepresentation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: "public.png",
            uniformTypeIdentifier: "public.png",
            storageKind: .blobFile,
            externalFilePath: original.relativePath,
            byteCount: original.byteCount,
            priority: 0
        )
        let thumbnailRepresentation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: PasteboardInternalTypes.thumbnailPNG,
            uniformTypeIdentifier: "public.png",
            storageKind: .blobFile,
            externalFilePath: thumbnail.relativePath,
            byteCount: thumbnail.byteCount,
            priority: 1
        )

        try await repository.save(
            group: group,
            entries: [entry],
            representations: [originalRepresentation, thumbnailRepresentation]
        )

        let rowData = try await service.imageData(for: entry, preferThumbnail: true)
        let detailData = try await service.imageData(for: entry, preferThumbnail: false)

        #expect(rowData == Data("thumbnail-data".utf8))
        #expect(detailData == Data("original-image-data".utf8))
    }

    @Test
    func deletingRepositoryEntryTriggersOrphanBlobCleanup() async throws {
        let directory = try TemporaryDirectory()
        let blobStore = FileSystemBlobStore(rootURL: directory.url.appendingPathComponent("Blobs"))
        let repository = try GRDBClipboardRepository(
            databasePath: directory.url.appendingPathComponent("devclip.sqlite").path,
            blobStore: blobStore
        )
        let firstBlob = try await blobStore.store(data: Data("first".utf8), suggestedExtension: "bin")
        let secondBlob = try await blobStore.store(data: Data("second".utf8), suggestedExtension: "bin")
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 2)
        let firstEntry = makeEntry(
            groupID: group.id,
            title: "第一",
            searchableText: "first",
            contentHash: "sha256:first"
        )
        let secondEntry = makeEntry(
            groupID: group.id,
            title: "第二",
            searchableText: "second",
            contentHash: "sha256:second"
        )
        let firstRepresentation = blobRepresentation(entryID: firstEntry.id, descriptor: firstBlob)
        let secondRepresentation = blobRepresentation(entryID: secondEntry.id, descriptor: secondBlob)

        try await repository.save(
            group: group,
            entries: [firstEntry, secondEntry],
            representations: [firstRepresentation, secondRepresentation]
        )

        try await repository.deleteEntry(id: firstEntry.id)

        let firstExists = await FileManager.default.fileExists(atPath: blobStore.url(for: firstBlob).path)
        let secondExists = await FileManager.default.fileExists(atPath: blobStore.url(for: secondBlob).path)
        let referencedPaths = try await repository.referencedExternalPaths()

        #expect(!firstExists)
        #expect(secondExists)
        #expect(referencedPaths == [secondBlob.relativePath])
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevClipTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func makeEntry(
    groupID: UUID,
    title: String,
    kind: ClipboardContentKind = .plainText,
    searchableText: String,
    contentHash: String,
    copyCount: Int = 1,
    metadata: ClipboardMetadata = ClipboardMetadata(values: ["snapshotChangeCount": "1"])
) -> ClipboardEntry {
    ClipboardEntry(
        groupID: groupID,
        title: title,
        detectedKind: kind,
        sourceAppName: "测试应用",
        sourceBundleIdentifier: "dev.local.Tests",
        contentHash: contentHash,
        searchableText: searchableText,
        previewText: searchableText,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        copyCount: copyCount,
        byteCount: Int64(searchableText.utf8.count),
        metadata: metadata
    )
}

private func blobRepresentation(
    entryID: UUID,
    descriptor: BlobDescriptor
) -> ClipboardRepresentation {
    ClipboardRepresentation(
        entryID: entryID,
        pasteboardType: "public.data",
        uniformTypeIdentifier: "public.data",
        storageKind: .blobFile,
        externalFilePath: descriptor.relativePath,
        byteCount: descriptor.byteCount
    )
}

private struct MockThumbnailGenerator: ImageThumbnailGenerating {
    func thumbnailPNGData(from data: Data, maxPixel: CGFloat) async throws -> Data? {
        Data("thumb".utf8)
    }
}
