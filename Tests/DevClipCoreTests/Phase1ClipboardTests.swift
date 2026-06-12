import Foundation
@testable import DevClipCore
import Testing

@Suite("Phase 1 Clipboard Tests")
struct Phase1ClipboardTests {
    @Test
    func monitorPollsChangeCountBeforeReadingSnapshot() async throws {
        let snapshot = makeSnapshot(changeCount: 8, textItems: ["hello"])
        let pasteboardClient = MockPasteboardClient(
            changeCounts: [7, 7, 8],
            snapshots: [snapshot]
        )
        let repository = InMemoryClipboardRepository()
        let monitor = ClipboardMonitor(
            pasteboardClient: pasteboardClient,
            repository: repository
        )

        let first = try await monitor.pollOnce()
        let second = try await monitor.pollOnce()
        let third = try await monitor.pollOnce()
        let readCount = await pasteboardClient.readSnapshotCallCount()
        let entries = try await repository.entries()

        #expect(first == .initialized(changeCount: 7))
        #expect(second == .noChange(changeCount: 7))
        #expect(third == .saved(changeCount: 8, entryCount: 1))
        #expect(readCount == 1)
        #expect(entries.count == 1)
    }

    @Test
    func duplicateClipboardContentMergesInsteadOfAddingEntry() async throws {
        let repository = InMemoryClipboardRepository()
        let monitor = ClipboardMonitor(
            pasteboardClient: MockPasteboardClient(),
            repository: repository
        )

        let firstSnapshot = makeSnapshot(changeCount: 1, textItems: ["repeat"])
        let secondSnapshot = makeSnapshot(changeCount: 2, textItems: ["repeat"])

        try await monitor.processSnapshot(firstSnapshot)
        try await monitor.processSnapshot(secondSnapshot)

        let entries = try await repository.entries()
        let groups = try await repository.groups()

        #expect(entries.count == 1)
        #expect(entries.first?.copyCount == 2)
        #expect(groups.count == 1)
    }

    @Test
    func multiplePasteboardItemsShareOneClipboardGroup() async throws {
        let repository = InMemoryClipboardRepository()
        let monitor = ClipboardMonitor(
            pasteboardClient: MockPasteboardClient(),
            repository: repository
        )

        try await monitor.processSnapshot(makeSnapshot(changeCount: 3, textItems: ["one", "two"]))

        let entries = try await repository.entries()
        let groups = try await repository.groups()
        let groupIDs = Set(entries.compactMap(\.groupID))

        #expect(entries.count == 2)
        #expect(groups.count == 1)
        #expect(groups.first?.itemCount == 2)
        #expect(groupIDs.count == 1)

        for entry in entries {
            let representations = try await repository.representations(entryID: entry.id)
            #expect(representations.count == 1)
            #expect(representations.first?.storageKind == .inlineData)
        }
    }

    @Test
    func writeGuardIgnoresRecordedChangeCountOnce() async throws {
        // Clear any persisted marker from previous test runs
        UserDefaults.standard.removeObject(forKey: "devclip.writeGuard.lastMarker")
        let guardActor = ClipboardWriteGuard()
        let marker = ClipboardWriteMarker(
            transactionID: UUID(),
            contentHash: "sha256:internal",
            changeCount: 42
        )

        try await guardActor.recordInternalWrite(marker)

        let firstMatch = try await guardActor.shouldIgnore(changeCount: 42, contentHash: nil)
        let secondMatch = try await guardActor.shouldIgnore(changeCount: 42, contentHash: nil)
        let pendingCount = await guardActor.pendingMarkerCount()

        #expect(firstMatch)
        #expect(!secondMatch)
        #expect(pendingCount == 0)
    }

    @Test
    func monitorSkipsSnapshotWithInternalWriteMarker() async throws {
        let repository = InMemoryClipboardRepository()
        let guardActor = ClipboardWriteGuard()
        let transactionID = UUID()
        let marker = ClipboardWriteMarker(
            transactionID: transactionID,
            contentHash: "sha256:internal",
            changeCount: nil
        )
        let monitor = ClipboardMonitor(
            pasteboardClient: MockPasteboardClient(),
            repository: repository,
            writeGuard: guardActor
        )
        let snapshot = makeSnapshot(
            changeCount: 5,
            textItems: ["internal"],
            internalWriteMarker: marker
        )

        try await guardActor.recordInternalWrite(marker)
        let result = try await monitor.processSnapshot(snapshot)
        let entries = try await repository.entries()

        #expect(result == .ignoredInternalWrite(changeCount: 5))
        #expect(entries.isEmpty)
    }

    @Test
    func stableHashIgnoresRepresentationOrdering() {
        let first = PasteboardItemSnapshot(representations: [
            makeRepresentation(type: "public.utf8-plain-text", text: "hello"),
            makeRepresentation(type: "public.html", text: "<p>hello</p>")
        ])
        let second = PasteboardItemSnapshot(representations: [
            makeRepresentation(type: "public.html", text: "<p>hello</p>"),
            makeRepresentation(type: "public.utf8-plain-text", text: "hello")
        ])

        #expect(ClipboardContentHasher.hash(item: first) == ClipboardContentHasher.hash(item: second))
    }
}

private actor MockPasteboardClient: PasteboardClient {
    private var changeCounts: [Int]
    private var snapshots: [ClipboardSnapshot]
    private var changeCountIndex = 0
    private var snapshotReadCount = 0

    init(
        changeCounts: [Int] = [],
        snapshots: [ClipboardSnapshot] = []
    ) {
        self.changeCounts = changeCounts
        self.snapshots = snapshots
    }

    func changeCount() async throws -> Int {
        guard !changeCounts.isEmpty else {
            return 0
        }

        let index = min(changeCountIndex, changeCounts.count - 1)
        changeCountIndex += 1
        return changeCounts[index]
    }

    func readSnapshot() async throws -> ClipboardSnapshot {
        snapshotReadCount += 1
        guard !snapshots.isEmpty else {
            return makeSnapshot(changeCount: 0, textItems: [])
        }

        return snapshots.removeFirst()
    }

    func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt {
        PasteboardWriteReceipt(
            transactionID: request.transactionID,
            changeCount: changeCounts.last ?? 0
        )
    }

    func readSnapshotCallCount() -> Int {
        snapshotReadCount
    }
}

private func makeSnapshot(
    changeCount: Int,
    textItems: [String],
    internalWriteMarker: ClipboardWriteMarker? = nil
) -> ClipboardSnapshot {
    ClipboardSnapshot(
        changeCount: changeCount,
        items: textItems.map { text in
            PasteboardItemSnapshot(representations: [
                makeRepresentation(type: "public.utf8-plain-text", text: text)
            ])
        },
        sourceAppName: "Unit Test",
        sourceBundleIdentifier: "dev.local.DevClipTests",
        capturedAt: Date(timeIntervalSince1970: TimeInterval(changeCount)),
        internalWriteMarker: internalWriteMarker
    )
}

private func makeRepresentation(
    type: String,
    text: String
) -> PasteboardRepresentationSnapshot {
    PasteboardRepresentationSnapshot(
        pasteboardType: type,
        uniformTypeIdentifier: type,
        data: Data(text.utf8)
    )
}
