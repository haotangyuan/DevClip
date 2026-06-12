import Foundation

public struct ClipboardMonitorOptions: Equatable, Sendable {
    public var activePollingInterval: Duration
    public var idlePollingInterval: Duration
    public var idleThreshold: Int

    public init(
        activePollingInterval: Duration = .milliseconds(350),
        idlePollingInterval: Duration = .seconds(1),
        idleThreshold: Int = 10
    ) {
        self.activePollingInterval = activePollingInterval
        self.idlePollingInterval = idlePollingInterval
        self.idleThreshold = idleThreshold
    }
}

public enum ClipboardMonitorPollResult: Equatable, Sendable {
    case initialized(changeCount: Int)
    case noChange(changeCount: Int)
    case ignoredInternalWrite(changeCount: Int)
    case saved(changeCount: Int, entryCount: Int)
    case protectedSecret(changeCount: Int, entryCount: Int)
}

/// Background actor that polls pasteboard changes and saves new snapshots.
public actor ClipboardMonitor {
    private let pasteboardClient: any PasteboardClient
    private let repository: any ClipboardRepository
    private let writeGuard: ClipboardWriteGuard
    private let snapshotBuilder: ClipboardSnapshotBuilder
    private let ephemeralSensitiveStore: SensitiveEphemeralStore
    private let options: ClipboardMonitorOptions

    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount: Int?
    private var idlePollCount = 0
    private var lastFailureDescription: String?

    public init(
        pasteboardClient: any PasteboardClient,
        repository: any ClipboardRepository,
        writeGuard: ClipboardWriteGuard = ClipboardWriteGuard(),
        snapshotBuilder: ClipboardSnapshotBuilder = ClipboardSnapshotBuilder(),
        ephemeralSensitiveStore: SensitiveEphemeralStore = SensitiveEphemeralStore(),
        options: ClipboardMonitorOptions = ClipboardMonitorOptions()
    ) {
        self.pasteboardClient = pasteboardClient
        self.repository = repository
        self.writeGuard = writeGuard
        self.snapshotBuilder = snapshotBuilder
        self.ephemeralSensitiveStore = ephemeralSensitiveStore
        self.options = options
    }

    public func start() async throws {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task.detached(priority: .background) { [weak self] in
            await self?.runPollingLoop()
        }
    }

    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func lastFailure() -> String? {
        lastFailureDescription
    }

    @discardableResult
    public func pollOnce() async throws -> ClipboardMonitorPollResult {
        let currentChangeCount = try await pasteboardClient.changeCount()

        guard let previousChangeCount = lastChangeCount else {
            lastChangeCount = currentChangeCount
            return .initialized(changeCount: currentChangeCount)
        }

        guard currentChangeCount != previousChangeCount else {
            idlePollCount += 1
            return .noChange(changeCount: currentChangeCount)
        }

        let snapshot = try await pasteboardClient.readSnapshot()
        lastChangeCount = snapshot.changeCount
        idlePollCount = 0
        return try await processSnapshot(snapshot)
    }

    @discardableResult
    public func processSnapshot(_ snapshot: ClipboardSnapshot) async throws -> ClipboardMonitorPollResult {
        _ = try await repository.deleteExpiredEntries(now: Date())
        _ = await ephemeralSensitiveStore.purgeExpired()

        let buildResult = await snapshotBuilder.build(from: snapshot)

        guard !buildResult.entries.isEmpty || !buildResult.protectedEntries.isEmpty else {
            return .noChange(changeCount: snapshot.changeCount)
        }

        if try await writeGuard.shouldIgnore(snapshot: snapshot, contentHash: buildResult.snapshotHash) {
            return .ignoredInternalWrite(changeCount: snapshot.changeCount)
        }

        if !buildResult.protectedEntries.isEmpty {
            await ephemeralSensitiveStore.store(
                entries: buildResult.protectedEntries,
                representations: buildResult.protectedRepresentations
            )
        }

        if !buildResult.entries.isEmpty {
            try await repository.save(
                group: buildResult.group,
                entries: buildResult.entries,
                representations: buildResult.representations
            )

            return .saved(changeCount: snapshot.changeCount, entryCount: buildResult.entries.count)
        }

        return .protectedSecret(
            changeCount: snapshot.changeCount,
            entryCount: buildResult.protectedEntries.count
        )
    }

    private func runPollingLoop() async {
        while !Task.isCancelled {
            do {
                _ = try await pollOnce()
                lastFailureDescription = nil
            } catch {
                lastFailureDescription = String(describing: error)
            }

            try? await Task.sleep(for: pollingInterval())
        }
    }

    private func pollingInterval() -> Duration {
        idlePollCount >= options.idleThreshold ? options.idlePollingInterval : options.activePollingInterval
    }
}
