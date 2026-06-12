import DevClipCore
import Foundation

enum AppDependencyFactory {
    static func make() throws -> DependencyContainer {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        let rootURL = applicationSupport.appendingPathComponent("DevClip", isDirectory: true)
        let blobStore = FileSystemBlobStore(
            rootURL: rootURL.appendingPathComponent("Blobs", isDirectory: true)
        )
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let databasePool = try DatabaseBootstrap.makePool(
            at: rootURL.appendingPathComponent("devclip.sqlite").path
        )
        let repository = GRDBClipboardRepository(
            databasePool: databasePool,
            blobStore: blobStore
        )
        let pasteboardClient = SystemPasteboardClient()
        let writeGuard = ClipboardWriteGuard()
        let contentClassifier = DefaultContentClassifier()
        let sensitiveDetector = DefaultSensitiveContentDetector()
        let ephemeralSensitiveStore = SensitiveEphemeralStore()
        let transformEngine = TransformEngine()
        let snapshotBuilder = ClipboardSnapshotBuilder(
            contentClassifier: contentClassifier,
            sensitiveDetector: sensitiveDetector,
            blobStore: blobStore
        )
        let monitor = ClipboardMonitor(
            pasteboardClient: pasteboardClient,
            repository: repository,
            writeGuard: writeGuard,
            snapshotBuilder: snapshotBuilder,
            ephemeralSensitiveStore: ephemeralSensitiveStore
        )
        let pasteEngine = PasteEngine(
            repository: repository,
            pasteboardClient: pasteboardClient,
            writeGuard: writeGuard,
            automationPreferences: UserDefaultsPasteAutomationPreferences(),
            blobStore: blobStore
        )
        let clipboardStackStore = GRDBClipboardStackStore(databasePool: databasePool)
        let clipboardStackService = ClipboardStackService(
            repository: repository,
            store: clipboardStackStore
        )
        let transformPipelineStore = GRDBTransformPipelineStore(databasePool: databasePool)
        let snippetStore = GRDBSnippetStore(databasePool: databasePool)
        let searchService = SQLiteSearchService(repository: repository)

        return DependencyContainer(
            pasteboardClient: pasteboardClient,
            repository: repository,
            writeGuard: writeGuard,
            clipboardMonitor: monitor,
            ephemeralSensitiveStore: ephemeralSensitiveStore,
            contentClassifier: contentClassifier,
            sensitiveDetector: sensitiveDetector,
            transformEngine: transformEngine,
            searchService: searchService,
            blobStore: blobStore,
            pasteEngine: pasteEngine,
            clipboardStackStore: clipboardStackStore,
            clipboardStackService: clipboardStackService,
            sequentialPasteService: SequentialPasteService(
                stackService: clipboardStackService,
                pasteEngine: pasteEngine
            ),
            transformPipelineStore: transformPipelineStore,
            pipelinePreviewService: PipelinePreviewService(
                repository: repository,
                transformEngine: transformEngine
            ),
            snippetStore: snippetStore,
            snippetLibrary: SnippetLibrary(store: snippetStore),
            diffService: LineDiffService(),
            launchAtLoginClient: SystemLaunchAtLoginClient(),
            archiveService: AESGCMClipboardArchiveService(repository: repository),
            archiveFileClient: JSONClipboardArchiveFileClient(),
            searchPerformanceProbe: SearchPerformanceProbe(
                repository: repository,
                searchService: searchService
            ),
            updateClient: SparkleUpdateCheckingClient()
        )
    }

    static func makeFallbackInMemory() -> DependencyContainer {
        DependencyContainer.production()
    }
}
