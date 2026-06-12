@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

/// NSPasteboard-backed implementation for capture and guarded internal writes.
public struct SystemPasteboardClient: PasteboardClient {
    private let maxRepresentationBytes: Int

    public init(maxRepresentationBytes: Int = 10 * 1024 * 1024) {
        self.maxRepresentationBytes = maxRepresentationBytes
    }

    public func changeCount() async throws -> Int {
        await MainActor.run { NSPasteboard.general.changeCount }
    }

    public func readSnapshot() async throws -> ClipboardSnapshot {
        let captured = await MainActor.run {
            let pasteboard = NSPasteboard.general
            let items = pasteboard.pasteboardItems ?? []
            let changeCount = pasteboard.changeCount
            let sourceApplication = NSWorkspace.shared.frontmostApplication
            let snapshots = items.map(self.readItemSnapshot).filter { !$0.representations.isEmpty }
            let marker = self.readInternalMarker(from: items, changeCount: changeCount)
            return (
                changeCount: changeCount,
                snapshots: snapshots,
                sourceAppName: sourceApplication?.localizedName,
                sourceBundleIdentifier: sourceApplication?.bundleIdentifier,
                marker: marker
            )
        }

        return ClipboardSnapshot(
            changeCount: captured.changeCount,
            items: captured.snapshots,
            sourceAppName: captured.sourceAppName,
            sourceBundleIdentifier: captured.sourceBundleIdentifier,
            internalWriteMarker: captured.marker
        )
    }

    public func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt {
        let contentHash = request.contentHash ?? hash(request.items)
        let pasteboardItems = request.items.map { itemSnapshot in
            let item = NSPasteboardItem()

            for representation in itemSnapshot.representations {
                item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.pasteboardType)
                )
            }

            item.setString(
                request.transactionID.uuidString,
                forType: NSPasteboard.PasteboardType(PasteboardInternalTypes.transactionID)
            )
            item.setString(
                contentHash,
                forType: NSPasteboard.PasteboardType(PasteboardInternalTypes.contentHash)
            )
            item.setString(
                "1",
                forType: NSPasteboard.PasteboardType(PasteboardInternalTypes.markerVersion)
            )

            return item
        }

        let receipt = try await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let didWrite = pasteboard.writeObjects(pasteboardItems)
            guard didWrite else {
                throw DevClipError.invalidInput(reason: "Failed to write pasteboard items.")
            }
            return PasteboardWriteReceipt(
                transactionID: request.transactionID,
                changeCount: pasteboard.changeCount
            )
        }

        return receipt
    }

    private func readItemSnapshot(_ item: NSPasteboardItem) -> PasteboardItemSnapshot {
        let representations = item.types.compactMap { type -> PasteboardRepresentationSnapshot? in
            guard !PasteboardInternalTypes.isInternal(type.rawValue) else {
                return nil
            }

            guard let data = item.data(forType: type) ?? fallbackData(from: item, type: type) else {
                return nil
            }

            guard data.count <= maxRepresentationBytes else {
                return nil
            }

            return PasteboardRepresentationSnapshot(
                pasteboardType: type.rawValue,
                uniformTypeIdentifier: uniformTypeIdentifier(for: type),
                data: data
            )
        }

        return PasteboardItemSnapshot(representations: representations)
    }

    private func fallbackData(from item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> Data? {
        item.string(forType: type)?.data(using: .utf8)
    }

    private func uniformTypeIdentifier(for type: NSPasteboard.PasteboardType) -> String? {
        UTType(type.rawValue)?.identifier
    }

    private func readInternalMarker(
        from items: [NSPasteboardItem],
        changeCount: Int
    ) -> ClipboardWriteMarker? {
        for item in items {
            guard
                let transactionIDString = item.string(
                    forType: NSPasteboard.PasteboardType(PasteboardInternalTypes.transactionID)
                ),
                let transactionID = UUID(uuidString: transactionIDString)
            else {
                continue
            }

            return ClipboardWriteMarker(
                transactionID: transactionID,
                contentHash: item.string(
                    forType: NSPasteboard.PasteboardType(PasteboardInternalTypes.contentHash)
                ),
                changeCount: changeCount
            )
        }

        return nil
    }

    private func hash(_ items: [PasteboardItemSnapshot]) -> String {
        let snapshot = ClipboardSnapshot(changeCount: 0, items: items)
        return ClipboardContentHasher.hash(snapshot: snapshot)
    }
}
