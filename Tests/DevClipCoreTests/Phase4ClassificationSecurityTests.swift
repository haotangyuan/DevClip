import Foundation
@preconcurrency import GRDB
@testable import DevClipCore
import Testing

@Suite("Phase 4 Classification And Security Tests")
struct Phase4ClassificationSecurityTests {
    @Test(arguments: [
        ("plain text", ClipboardContentKind.plainText),
        ("https://example.com/path?q=1", ClipboardContentKind.url),
        ("dev@example.com", ClipboardContentKind.email),
        (#"{"name":"DevClip"}"#, ClipboardContentKind.json),
        ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.signature123", ClipboardContentKind.jwt),
        ("aGVsbG8=", ClipboardContentKind.base64),
        ("data:text/plain;base64,aGVsbG8=", ClipboardContentKind.dataURI),
        ("550e8400-e29b-41d4-a716-446655440000", ClipboardContentKind.uuid),
        ("1718100000", ClipboardContentKind.unixTimestamp),
        ("2026-06-11T12:00:00Z", ClipboardContentKind.isoDate),
        ("#FF00AA", ClipboardContentKind.color),
        ("192.168.1.1", ClipboardContentKind.ipAddress),
        ("0123456789abcdef0123456789abcdef01234567", ClipboardContentKind.gitCommit),
        ("-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----", ClipboardContentKind.privateKey),
        ("API_URL=https://example.com\nDEBUG=1", ClipboardContentKind.environmentVariables),
        ("git status --short", ClipboardContentKind.shellCommand),
        ("<root><name>DevClip</name></root>", ClipboardContentKind.xml),
        ("<html><body>DevClip</body></html>", ClipboardContentKind.html),
        ("# DevClip\n\n```swift\nlet value = 1\n```", ClipboardContentKind.markdown),
        ("name,age\nAda,36\nLinus,55", ClipboardContentKind.csv),
        ("diff --git a/a.swift b/a.swift\n@@ -1 +1 @@", ClipboardContentKind.gitDiff),
        ("Exception in thread main\n    at App.main(App.java:12)", ClipboardContentKind.stackTrace),
        ("func run() { return }", ClipboardContentKind.sourceCode)
    ])
    func classifierDetectsDeveloperContentKinds(
        sample: String,
        expectedKind: ClipboardContentKind
    ) async throws {
        let classifier = DefaultContentClassifier()

        let result = try await classifier.classify(
            ClassificationInput(data: Data(sample.utf8), pasteboardType: "public.utf8-plain-text")
        )

        #expect(result.detectedKind == expectedKind)
        #expect(result.candidates.contains { $0.kind == expectedKind })
    }

    @Test
    func classifierDetectsImageAndFileListRepresentations() async throws {
        let classifier = DefaultContentClassifier()

        let image = try await classifier.classify(
            ClassificationInput(data: Data([0x89, 0x50, 0x4E, 0x47]), uniformTypeIdentifier: "public.png")
        )
        let fileList = try await classifier.classify(
            ClassificationInput(data: Data("/tmp/a\n/tmp/b".utf8), pasteboardType: "NSFilenamesPboardType")
        )

        #expect(image.detectedKind == .image)
        #expect(fileList.detectedKind == .fileList)
    }

    @Test
    func classifierContinuesWhenDetectorThrows() async throws {
        let classifier = DefaultContentClassifier(detectors: [
            ThrowingDetector(),
            FixedDetector(kind: .json)
        ])

        let result = try await classifier.classify(ClassificationInput(data: Data("{}".utf8)))

        #expect(result.detectedKind == .json)
    }

    @Test
    func sensitiveDetectorClassifiesSecretTokenWithoutPersistingOrIndexing() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let detector = DefaultSensitiveContentDetector(clock: { now })

        let result = try await detector.detect(
            ClassificationInput(data: Data("Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456".utf8)),
            sourceBundleIdentifier: "com.apple.Terminal"
        )

        #expect(result.classification == .secret)
        #expect(result.evidence.contains("bearer_token"))
        #expect(result.expiresAt == now.addingTimeInterval(60))
        #expect(!result.shouldIndex)
        #expect(!result.shouldPersist)
        #expect(result.shouldRetainInMemory)
    }

    @Test
    func sensitiveDetectorClassifiesVerificationCodeAsPotential() async throws {
        let now = Date(timeIntervalSince1970: 200)
        let detector = DefaultSensitiveContentDetector(clock: { now })

        let result = try await detector.detect(
            ClassificationInput(data: Data("验证码 123456".utf8)),
            sourceBundleIdentifier: "com.apple.MobileSMS"
        )

        #expect(result.classification == .potential)
        #expect(result.evidence.contains("verification_code"))
        #expect(result.expiresAt == now.addingTimeInterval(10 * 60))
        #expect(result.shouldIndex)
        #expect(result.shouldPersist)
    }

    @Test
    func sensitiveDetectorIgnoresPasswordManagerSources() async throws {
        let detector = DefaultSensitiveContentDetector()

        let result = try await detector.detect(
            ClassificationInput(data: Data("ordinary copied text".utf8)),
            sourceBundleIdentifier: "com.1password.1password"
        )

        #expect(result.classification == .secret)
        #expect(result.evidence == ["source_app_ignored"])
        #expect(!result.shouldPersist)
        #expect(!result.shouldRetainInMemory)
    }

    @Test
    func monitorStoresSecretOnlyInEphemeralMemory() async throws {
        let repository = InMemoryClipboardRepository()
        let ephemeralStore = SensitiveEphemeralStore()
        let monitor = ClipboardMonitor(
            pasteboardClient: EmptyPasteboardClient(),
            repository: repository,
            writeGuard: ClipboardWriteGuard(persistMarkers: false),
            ephemeralSensitiveStore: ephemeralStore
        )
        let privateKey = """
        -----BEGIN PRIVATE KEY-----
        abcdefghijklmnopqrstuvwxyz
        -----END PRIVATE KEY-----
        """

        let result = try await monitor.processSnapshot(
            makeSnapshot(changeCount: 401, text: privateKey)
        )

        let persistedEntries = try await repository.entries()
        let ephemeralRecords = await ephemeralStore.records()

        #expect(result == .protectedSecret(changeCount: 401, entryCount: 1))
        #expect(persistedEntries.isEmpty)
        #expect(ephemeralRecords.count == 1)
        #expect(ephemeralRecords.first?.entry.isSensitive == true)
        #expect(ephemeralRecords.first?.entry.metadata.values["shouldIndex"] == "false")
    }

    @Test
    func monitorMasksPotentialSensitiveContentAndSetsExpiry() async throws {
        let repository = InMemoryClipboardRepository()
        let monitor = ClipboardMonitor(
            pasteboardClient: EmptyPasteboardClient(),
            repository: repository,
            writeGuard: ClipboardWriteGuard(persistMarkers: false)
        )

        let result = try await monitor.processSnapshot(
            makeSnapshot(changeCount: 402, text: "验证码 123456")
        )
        let entries = try await repository.entries()

        #expect(result == .saved(changeCount: 402, entryCount: 1))
        #expect(entries.count == 1)
        #expect(entries.first?.isSensitive == true)
        #expect(entries.first?.previewText == "可能敏感内容已遮罩")
        #expect(entries.first?.searchableText == "可能敏感内容已遮罩")
        #expect(entries.first?.expiresAt != nil)
        #expect(entries.first?.metadata.values["sensitiveClassification"] == "potential")
    }

    @Test
    func repositoriesDeleteExpiredEntries() async throws {
        let repository = InMemoryClipboardRepository()
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "过期",
            text: "expired",
            contentHash: "sha256:phase4-expired",
            expiresAt: Date(timeIntervalSince1970: 10)
        )

        try await repository.save(group: group, entries: [entry], representations: [])
        let deleted = try await repository.deleteExpiredEntries(now: Date(timeIntervalSince1970: 11))

        #expect(deleted == 1)
        #expect(try await repository.entries().isEmpty)
    }

    @Test
    func grdbDoesNotIndexEntriesMarkedShouldNotIndex() async throws {
        let directory = try TemporaryDirectory()
        let repository = try GRDBClipboardRepository(
            databasePath: directory.url.appendingPathComponent("devclip.sqlite").path
        )
        let group = ClipboardGroup(sourceAppName: "测试应用", itemCount: 1)
        let entry = makeEntry(
            groupID: group.id,
            title: "Secret",
            text: "secret-token-value",
            contentHash: "sha256:phase4-no-index",
            metadata: ClipboardMetadata(values: ["shouldIndex": "false"])
        )

        try await repository.save(group: group, entries: [entry], representations: [])

        let allEntries = try await repository.entries()
        let searchResults = try await repository.searchFTS("secret-token-value")

        #expect(allEntries.map(\.id) == [entry.id])
        #expect(searchResults.isEmpty)
    }
}

private struct ThrowingDetector: ContentDetector {
    let id = "throwing"

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        _ = input
        throw DevClipError.invalidInput(reason: "测试错误")
    }
}

private struct FixedDetector: ContentDetector {
    let id = "fixed"
    var kind: ClipboardContentKind

    func detect(_ input: ClassificationInput) async throws -> [ClassificationCandidate] {
        _ = input
        return [
            ClassificationCandidate(kind: kind, confidence: 0.9, evidence: "fixed")
        ]
    }
}

private actor EmptyPasteboardClient: PasteboardClient {
    func changeCount() async throws -> Int {
        0
    }

    func readSnapshot() async throws -> ClipboardSnapshot {
        ClipboardSnapshot(changeCount: 0, items: [])
    }

    func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt {
        PasteboardWriteReceipt(transactionID: request.transactionID, changeCount: 0)
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevClipPhase4Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func makeSnapshot(changeCount: Int, text: String) -> ClipboardSnapshot {
    ClipboardSnapshot(
        changeCount: changeCount,
        items: [
            PasteboardItemSnapshot(representations: [
                PasteboardRepresentationSnapshot(
                    pasteboardType: "public.utf8-plain-text",
                    uniformTypeIdentifier: "public.utf8-plain-text",
                    data: Data(text.utf8)
                )
            ])
        ],
        sourceAppName: "测试应用",
        sourceBundleIdentifier: "dev.local.Tests",
        capturedAt: Date(timeIntervalSince1970: TimeInterval(changeCount))
    )
}

private func makeEntry(
    groupID: UUID,
    title: String,
    text: String,
    contentHash: String,
    expiresAt: Date? = nil,
    metadata: ClipboardMetadata = ClipboardMetadata()
) -> ClipboardEntry {
    ClipboardEntry(
        groupID: groupID,
        title: title,
        detectedKind: .plainText,
        sourceAppName: "测试应用",
        sourceBundleIdentifier: "dev.local.Tests",
        contentHash: contentHash,
        searchableText: text,
        previewText: text,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1),
        expiresAt: expiresAt,
        byteCount: Int64(text.utf8.count),
        metadata: metadata
    )
}
