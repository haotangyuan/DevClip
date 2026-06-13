import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 8 Export Settings Performance Tests")
struct Phase8ExportSettingsPerformanceTests {
    @Test
    func encryptedExportIncludesAllEntriesAndImportsRoundTrip() async throws {
        let sourceRepository = InMemoryClipboardRepository()
        let targetRepository = InMemoryClipboardRepository()
        let sourceService = AESGCMClipboardArchiveService(
            repository: sourceRepository,
            saltGenerator: { Data(repeating: 7, count: 16) },
            dateProvider: { Date(timeIntervalSince1970: 80) }
        )
        let targetService = AESGCMClipboardArchiveService(repository: targetRepository)
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 2)
        let safeEntry = makePhase8Entry(
            groupID: group.id,
            title: "安全记录",
            text: "safe payload",
            hash: "sha256:phase8-safe"
        )
        let secretEntry = makePhase8Entry(
            groupID: group.id,
            title: "令牌记录",
            text: "SECRET_TOKEN=abc123456789",
            hash: "sha256:phase8-secret"
        )

        try await sourceRepository.save(
            group: group,
            entries: [safeEntry, secretEntry],
            representations: [
                phase8Representation(entryID: safeEntry.id, text: "safe payload"),
                phase8Representation(entryID: secretEntry.id, text: "SECRET_TOKEN=abc123456789")
            ]
        )

        let exportResult = try await sourceService.exportEncrypted(passphrase: "passphrase")
        let encodedArchive = try JSONEncoder().encode(exportResult.archive)
        let encodedArchiveText = String(data: encodedArchive, encoding: .utf8) ?? ""

        #expect(exportResult.summary.exportedEntryCount == 2)
        #expect(exportResult.summary.skippedEntryCount == 0)
        #expect(!encodedArchiveText.contains("SECRET_TOKEN"))

        let importSummary = try await targetService.importEncrypted(
            exportResult.archive,
            passphrase: "passphrase"
        )
        let importedEntries = try await targetRepository.entries()

        #expect(importSummary.importedEntryCount == 2)
        #expect(importedEntries.map(\.title).sorted() == ["令牌记录", "安全记录"])
        #expect(try await targetRepository.representations(entryID: safeEntry.id).first?.inlineData == Data("safe payload".utf8))
        #expect(try await targetRepository.representations(entryID: secretEntry.id).first?.inlineData == Data("SECRET_TOKEN=abc123456789".utf8))
    }

    @Test
    func encryptedImportRejectsWrongPassphrase() async throws {
        let repository = InMemoryClipboardRepository()
        let service = AESGCMClipboardArchiveService(
            repository: repository,
            saltGenerator: { Data(repeating: 3, count: 16) }
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makePhase8Entry(
            groupID: group.id,
            title: "安全记录",
            text: "safe payload",
            hash: "sha256:phase8-wrong-pass"
        )

        try await repository.save(
            group: group,
            entries: [entry],
            representations: [phase8Representation(entryID: entry.id, text: "safe payload")]
        )

        let exportResult = try await service.exportEncrypted(passphrase: "correct")

        await #expect(throws: Error.self) {
            _ = try await service.importEncrypted(exportResult.archive, passphrase: "wrong")
        }
    }

    @Test
    func archiveFileClientWritesAndReadsJSONArchive() async throws {
        let directory = try Phase8TemporaryDirectory()
        let fileClient = JSONClipboardArchiveFileClient()
        let archive = EncryptedClipboardArchive(
            formatVersion: 1,
            createdAt: Date(timeIntervalSince1970: 80),
            saltBase64: Data("salt".utf8).base64EncodedString(),
            nonceBase64: Data("nonce".utf8).base64EncodedString(),
            ciphertextBase64: Data("cipher".utf8).base64EncodedString(),
            tagBase64: Data("tag".utf8).base64EncodedString()
        )
        let url = directory.url.appendingPathComponent("archive.json")

        try await fileClient.write(archive, to: url)
        let loaded = try await fileClient.read(from: url)

        #expect(loaded == archive)
    }

    @Test
    func launchAtLoginClientCanBeMocked() async throws {
        let client = InMemoryLaunchAtLoginClient()

        #expect(await client.isEnabled() == false)
        try await client.setEnabled(true)
        #expect(await client.isEnabled())
        try await client.setEnabled(false)
        #expect(await client.isEnabled() == false)
    }

    @Test
    func sparkleIntegrationStatusIsExplicitlyReserved() async {
        let client = SparkleUpdateCheckingClient()
        let status = await client.integrationStatus()

        #expect(status.interfaceName == "Sparkle 2")
        #expect(status.isSparkleLinked == false)
        #expect(status.note.contains("已预留"))
    }

    @Test
    func tenThousandEntrySearchPerformanceBaseline() async throws {
        let repository = InMemoryClipboardRepository()
        let searchService = SQLiteSearchService(repository: repository)
        let probe = SearchPerformanceProbe(repository: repository, searchService: searchService)

        try await probe.seedEntries(count: 10_000, marker: "phase8needle")
        let measurement = try await probe.measure(query: SearchQuery(terms: ["phase8needle"]))

        #expect(measurement.entryCount == 10_000)
        #expect(measurement.resultCount == 1)
        #expect(measurement.elapsedSeconds < 1.0)
    }
}

private struct Phase8TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevClipPhase8Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func makePhase8Entry(
    groupID: UUID,
    title: String,
    text: String,
    hash: String,
    metadata: ClipboardMetadata = ClipboardMetadata()
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
        createdAt: Date(timeIntervalSince1970: 80),
        updatedAt: Date(timeIntervalSince1970: 80),
        byteCount: Int64(text.utf8.count),
        metadata: metadata
    )
}

private func phase8Representation(entryID: UUID, text: String) -> ClipboardRepresentation {
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
