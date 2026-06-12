@preconcurrency import GRDB
import Foundation

/// Production dependency graph. Services remain protocol-isolated for tests.
public struct DependencyContainer: Sendable {
    public var pasteboardClient: any PasteboardClient
    public var repository: any ClipboardRepository
    public var writeGuard: ClipboardWriteGuard
    public var clipboardMonitor: ClipboardMonitor
    public var ephemeralSensitiveStore: SensitiveEphemeralStore
    public var contentClassifier: any ContentClassifier
    public var sensitiveDetector: any SensitiveContentDetecting
    public var transformEngine: TransformEngine
    public var searchService: any SearchService
    public var blobStore: any BlobStore
    public var pasteEngine: PasteEngine
    public var clipboardStackStore: any ClipboardStackStore
    public var clipboardStackService: ClipboardStackService
    public var sequentialPasteService: SequentialPasteService
    public var transformPipelineStore: any TransformPipelineStore
    public var pipelinePreviewService: PipelinePreviewService
    public var snippetStore: any SnippetStore
    public var snippetLibrary: SnippetLibrary
    public var diffService: any DiffService
    public var launchAtLoginClient: any LaunchAtLoginClient
    public var archiveService: any ClipboardArchiveService
    public var archiveFileClient: any ClipboardArchiveFileClient
    public var searchPerformanceProbe: SearchPerformanceProbe
    public var updateClient: any UpdateCheckingClient

    public init(
        pasteboardClient: any PasteboardClient,
        repository: any ClipboardRepository,
        writeGuard: ClipboardWriteGuard,
        clipboardMonitor: ClipboardMonitor,
        ephemeralSensitiveStore: SensitiveEphemeralStore,
        contentClassifier: any ContentClassifier,
        sensitiveDetector: any SensitiveContentDetecting,
        transformEngine: TransformEngine,
        searchService: any SearchService,
        blobStore: any BlobStore,
        pasteEngine: PasteEngine,
        clipboardStackStore: any ClipboardStackStore,
        clipboardStackService: ClipboardStackService,
        sequentialPasteService: SequentialPasteService,
        transformPipelineStore: any TransformPipelineStore,
        pipelinePreviewService: PipelinePreviewService,
        snippetStore: any SnippetStore,
        snippetLibrary: SnippetLibrary,
        diffService: any DiffService,
        launchAtLoginClient: any LaunchAtLoginClient,
        archiveService: any ClipboardArchiveService,
        archiveFileClient: any ClipboardArchiveFileClient,
        searchPerformanceProbe: SearchPerformanceProbe,
        updateClient: any UpdateCheckingClient
    ) {
        self.pasteboardClient = pasteboardClient
        self.repository = repository
        self.writeGuard = writeGuard
        self.clipboardMonitor = clipboardMonitor
        self.ephemeralSensitiveStore = ephemeralSensitiveStore
        self.contentClassifier = contentClassifier
        self.sensitiveDetector = sensitiveDetector
        self.transformEngine = transformEngine
        self.searchService = searchService
        self.blobStore = blobStore
        self.pasteEngine = pasteEngine
        self.clipboardStackStore = clipboardStackStore
        self.clipboardStackService = clipboardStackService
        self.sequentialPasteService = sequentialPasteService
        self.transformPipelineStore = transformPipelineStore
        self.pipelinePreviewService = pipelinePreviewService
        self.snippetStore = snippetStore
        self.snippetLibrary = snippetLibrary
        self.diffService = diffService
        self.launchAtLoginClient = launchAtLoginClient
        self.archiveService = archiveService
        self.archiveFileClient = archiveFileClient
        self.searchPerformanceProbe = searchPerformanceProbe
        self.updateClient = updateClient
    }

    public static func production() -> DependencyContainer {
        let pasteboardClient = SystemPasteboardClient()
        let writeGuard = ClipboardWriteGuard()
        let contentClassifier = DefaultContentClassifier()
        let sensitiveDetector = DefaultSensitiveContentDetector()
        let ephemeralSensitiveStore = SensitiveEphemeralStore()
        let transformEngine = TransformEngine()

        var blobStore: FileSystemBlobStore
        var repository: any ClipboardRepository
        var clipboardStackStore: any ClipboardStackStore
        var transformPipelineStore: any TransformPipelineStore
        var snippetStore: any SnippetStore

        do {
            let fileManager = FileManager.default
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)

            let rootURL = applicationSupport.appendingPathComponent("DevClip", isDirectory: true)
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            blobStore = FileSystemBlobStore(
                rootURL: rootURL.appendingPathComponent("Blobs", isDirectory: true)
            )

            let databasePool = try DatabaseBootstrap.makePool(
                at: rootURL.appendingPathComponent("devclip.sqlite").path
            )
            repository = GRDBClipboardRepository(
                databasePool: databasePool,
                blobStore: blobStore
            )
            clipboardStackStore = GRDBClipboardStackStore(databasePool: databasePool)
            transformPipelineStore = GRDBTransformPipelineStore(databasePool: databasePool)
            snippetStore = GRDBSnippetStore(databasePool: databasePool)
        } catch {
            blobStore = FileSystemBlobStore()
            repository = InMemoryClipboardRepository()
            clipboardStackStore = InMemoryClipboardStackStore()
            transformPipelineStore = InMemoryTransformPipelineStore()
            snippetStore = InMemorySnippetStore()
        }

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
        let clipboardStackService = ClipboardStackService(
            repository: repository,
            store: clipboardStackStore
        )
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
}
