import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 6 Paste Automation Tests")
struct Phase6PasteAutomationTests {
    @Test
    func pasteOriginalFallsBackToCopyOnlyWhenAutomationDisabled() async throws {
        let fixture = try await makePasteFixture(automaticPasteEnabled: false)

        let result = try await fixture.pasteEngine.perform(
            PasteRequest(
                entryID: fixture.entry.id,
                mode: .pasteOriginal,
                targetApplication: fixture.targetApplication
            )
        )

        let request = await fixture.pasteboardClient.lastRequest()
        let permissionRequestCount = await fixture.accessibilityClient.requestCount()
        let keyboardPostCount = await fixture.keyboardClient.postCount()

        #expect(result.didPaste == false)
        #expect(result.fallbackReason == .automationDisabled)
        #expect(request?.contentHash == fixture.entry.contentHash)
        #expect(request?.items.first?.representations.first?.data == Data("自动粘贴测试".utf8))
        #expect(permissionRequestCount == 0)
        #expect(keyboardPostCount == 0)
    }

    @Test
    func pastePlainTextRequestsPermissionActivatesTargetAndPostsCommandV() async throws {
        let fixture = try await makePasteFixture(automaticPasteEnabled: true)

        let result = try await fixture.pasteEngine.perform(
            PasteRequest(
                entryID: fixture.entry.id,
                mode: .pastePlainText,
                targetApplication: fixture.targetApplication
            )
        )

        let request = await fixture.pasteboardClient.lastRequest()
        let permissionRequestCount = await fixture.accessibilityClient.requestCount()
        let activatedApplications = await fixture.focusClient.activatedApplications()
        let keyboardPostCount = await fixture.keyboardClient.postCount()

        #expect(result.didPaste)
        #expect(result.fallbackReason == nil)
        #expect(request?.items.first?.representations.map(\.pasteboardType) == ["public.utf8-plain-text"])
        #expect(request?.items.first?.representations.first?.data == Data("自动粘贴测试".utf8))
        #expect(permissionRequestCount == 1)
        #expect(activatedApplications == [fixture.targetApplication])
        #expect(keyboardPostCount == 1)
    }

    @Test
    func pasteOriginalFallsBackWhenAccessibilityPermissionIsDenied() async throws {
        let fixture = try await makePasteFixture(
            automaticPasteEnabled: true,
            accessibilityTrusted: false
        )

        let result = try await fixture.pasteEngine.perform(
            PasteRequest(
                entryID: fixture.entry.id,
                mode: .pasteOriginal,
                targetApplication: fixture.targetApplication
            )
        )

        let activatedApplications = await fixture.focusClient.activatedApplications()
        let keyboardPostCount = await fixture.keyboardClient.postCount()

        #expect(result.didPaste == false)
        #expect(result.fallbackReason == .accessibilityPermissionDenied)
        #expect(activatedApplications.isEmpty)
        #expect(keyboardPostCount == 0)
    }

    @Test
    func pasteOriginalUsesFrontmostApplicationWhenRequestHasNoExplicitTarget() async throws {
        let fixture = try await makePasteFixture(automaticPasteEnabled: true)

        let result = try await fixture.pasteEngine.perform(
            PasteRequest(entryID: fixture.entry.id, mode: .pasteOriginal)
        )

        let frontmostRequestCount = await fixture.focusClient.frontmostRequestCount()
        let activatedApplications = await fixture.focusClient.activatedApplications()
        let keyboardPostCount = await fixture.keyboardClient.postCount()

        #expect(result.didPaste)
        #expect(frontmostRequestCount == 1)
        #expect(activatedApplications == [fixture.targetApplication])
        #expect(keyboardPostCount == 1)
    }

    @Test
    func pasteSpecificRepresentationWritesOnlyRequestedRepresentation() async throws {
        let fixture = try await makePasteFixture(automaticPasteEnabled: false)

        let result = try await fixture.pasteEngine.perform(
            PasteRequest(
                entryID: fixture.entry.id,
                mode: .pasteSpecificRepresentation,
                representationID: fixture.htmlRepresentation.id
            )
        )

        let request = await fixture.pasteboardClient.lastRequest()
        let representations = request?.items.first?.representations

        #expect(result.didPaste == false)
        #expect(result.fallbackReason == .automationDisabled)
        #expect(representations?.count == 1)
        #expect(representations?.first?.pasteboardType == "public.html")
        #expect(representations?.first?.data == Data("<p>自动粘贴测试</p>".utf8))
    }

    @Test
    func pasteOriginalRestoresBlobRepresentationAndSkipsInternalThumbnail() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevClipPasteBlob-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blobStore = FileSystemBlobStore(rootURL: directory.appendingPathComponent("Blobs"))
        let originalBlob = try await blobStore.store(data: Data("original-image".utf8), suggestedExtension: "png")
        let thumbnailBlob = try await blobStore.store(data: Data("thumbnail".utf8), suggestedExtension: "png")
        let repository = InMemoryClipboardRepository()
        let pasteboardClient = RecordingPhase6PasteboardClient(changeCount: 707)
        let pasteEngine = PasteEngine(
            repository: repository,
            pasteboardClient: pasteboardClient,
            writeGuard: ClipboardWriteGuard(persistMarkers: false),
            automationPreferences: MockPasteAutomationPreferences(isEnabled: false),
            blobStore: blobStore,
            stabilizationDelay: .milliseconds(0)
        )
        let group = ClipboardGroup(sourceAppName: "单元测试", itemCount: 1)
        let entry = ClipboardEntry(
            groupID: group.id,
            title: "图片",
            detectedKind: .image,
            contentHash: "sha256:blob-paste",
            searchableText: "图片",
            previewText: "图片",
            createdAt: Date(timeIntervalSince1970: 70),
            updatedAt: Date(timeIntervalSince1970: 70),
            byteCount: originalBlob.byteCount
        )
        let originalRepresentation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: "public.png",
            uniformTypeIdentifier: "public.png",
            storageKind: .blobFile,
            externalFilePath: originalBlob.relativePath,
            byteCount: originalBlob.byteCount,
            priority: 0
        )
        let thumbnailRepresentation = ClipboardRepresentation(
            entryID: entry.id,
            pasteboardType: PasteboardInternalTypes.thumbnailPNG,
            uniformTypeIdentifier: "public.png",
            storageKind: .blobFile,
            externalFilePath: thumbnailBlob.relativePath,
            byteCount: thumbnailBlob.byteCount,
            priority: 1
        )

        try await repository.save(
            group: group,
            entries: [entry],
            representations: [originalRepresentation, thumbnailRepresentation]
        )

        _ = try await pasteEngine.perform(PasteRequest(entryID: entry.id, mode: .copyOnly))
        let representations = await pasteboardClient.lastRequest()?.items.first?.representations

        #expect(representations?.count == 1)
        #expect(representations?.first?.pasteboardType == "public.png")
        #expect(representations?.first?.data == Data("original-image".utf8))
    }
}

private struct PasteFixture {
    var entry: ClipboardEntry
    var htmlRepresentation: ClipboardRepresentation
    var targetApplication: PasteTargetApplication
    var pasteEngine: PasteEngine
    var pasteboardClient: RecordingPhase6PasteboardClient
    var accessibilityClient: MockAccessibilityPermissionClient
    var focusClient: MockApplicationFocusClient
    var keyboardClient: MockKeyboardEventClient
}

private func makePasteFixture(
    automaticPasteEnabled: Bool,
    accessibilityTrusted: Bool = true
) async throws -> PasteFixture {
    let repository = InMemoryClipboardRepository()
    let pasteboardClient = RecordingPhase6PasteboardClient(changeCount: 606)
    let accessibilityClient = MockAccessibilityPermissionClient(trusted: accessibilityTrusted)
    let targetApplication = PasteTargetApplication(
        processIdentifier: 1234,
        bundleIdentifier: "dev.local.Target",
        localizedName: "目标应用"
    )
    let focusClient = MockApplicationFocusClient(frontmostApplication: targetApplication)
    let keyboardClient = MockKeyboardEventClient()
    let pasteEngine = PasteEngine(
        repository: repository,
        pasteboardClient: pasteboardClient,
        writeGuard: ClipboardWriteGuard(persistMarkers: false),
        automationPreferences: MockPasteAutomationPreferences(isEnabled: automaticPasteEnabled),
        accessibilityPermissionClient: accessibilityClient,
        applicationFocusClient: focusClient,
        keyboardEventClient: keyboardClient,
        stabilizationDelay: .milliseconds(0)
    )
    let group = ClipboardGroup(sourceAppName: "单元测试", itemCount: 1)
    let entry = ClipboardEntry(
        groupID: group.id,
        title: "自动粘贴测试",
        detectedKind: .plainText,
        sourceAppName: "单元测试",
        sourceBundleIdentifier: "dev.local.Tests",
        contentHash: "sha256:phase6-paste",
        searchableText: "自动粘贴测试",
        previewText: "自动粘贴测试",
        createdAt: Date(timeIntervalSince1970: 60),
        updatedAt: Date(timeIntervalSince1970: 60),
        byteCount: Int64("自动粘贴测试".utf8.count)
    )
    let plainTextRepresentation = ClipboardRepresentation(
        entryID: entry.id,
        pasteboardType: "public.utf8-plain-text",
        uniformTypeIdentifier: "public.utf8-plain-text",
        storageKind: .inlineData,
        inlineData: Data("自动粘贴测试".utf8),
        byteCount: Int64("自动粘贴测试".utf8.count),
        textEncoding: "utf-8",
        priority: 0
    )
    let htmlRepresentation = ClipboardRepresentation(
        entryID: entry.id,
        pasteboardType: "public.html",
        uniformTypeIdentifier: "public.html",
        storageKind: .inlineData,
        inlineData: Data("<p>自动粘贴测试</p>".utf8),
        byteCount: Int64("<p>自动粘贴测试</p>".utf8.count),
        textEncoding: "utf-8",
        priority: 1
    )

    try await repository.save(
        group: group,
        entries: [entry],
        representations: [plainTextRepresentation, htmlRepresentation]
    )

    return PasteFixture(
        entry: entry,
        htmlRepresentation: htmlRepresentation,
        targetApplication: targetApplication,
        pasteEngine: pasteEngine,
        pasteboardClient: pasteboardClient,
        accessibilityClient: accessibilityClient,
        focusClient: focusClient,
        keyboardClient: keyboardClient
    )
}

private struct MockPasteAutomationPreferences: PasteAutomationPreferenceProviding {
    var isEnabled: Bool

    func isAutomaticPasteEnabled() async -> Bool {
        isEnabled
    }
}

private actor RecordingPhase6PasteboardClient: PasteboardClient {
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

private actor MockAccessibilityPermissionClient: AccessibilityPermissionClient {
    private let trusted: Bool
    private var requests = 0

    init(trusted: Bool) {
        self.trusted = trusted
    }

    func isTrusted() async -> Bool {
        trusted
    }

    func requestTrustIfNeeded() async -> Bool {
        requests += 1
        return trusted
    }

    func requestCount() -> Int {
        requests
    }
}

private actor MockApplicationFocusClient: ApplicationFocusClient {
    private let currentFrontmostApplication: PasteTargetApplication?
    private var frontmostRequests = 0
    private var activations: [PasteTargetApplication] = []

    init(frontmostApplication: PasteTargetApplication?) {
        self.currentFrontmostApplication = frontmostApplication
    }

    func frontmostApplication() async -> PasteTargetApplication? {
        frontmostRequests += 1
        return currentFrontmostApplication
    }

    func activate(_ application: PasteTargetApplication) async -> Bool {
        activations.append(application)
        return true
    }

    func frontmostRequestCount() -> Int {
        frontmostRequests
    }

    func activatedApplications() -> [PasteTargetApplication] {
        activations
    }
}

private actor MockKeyboardEventClient: KeyboardEventClient {
    private var posts = 0

    func postCommandV() async throws {
        posts += 1
    }

    func postCount() -> Int {
        posts
    }
}
