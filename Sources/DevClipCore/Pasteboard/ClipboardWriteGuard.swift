import Foundation

public struct ClipboardWriteMarker: Equatable, Sendable {
    public var transactionID: UUID
    public var contentHash: String?
    public var changeCount: Int?

    public init(
        transactionID: UUID,
        contentHash: String? = nil,
        changeCount: Int? = nil
    ) {
        self.transactionID = transactionID
        self.contentHash = contentHash
        self.changeCount = changeCount
    }
}

/// Guard against re-ingesting writes produced by DevClip itself.
public actor ClipboardWriteGuard {
    private var markersByTransactionID: [UUID: ClipboardWriteMarker] = [:]
    private var transactionIDsByChangeCount: [Int: UUID] = [:]
    private var transactionIDsByHash: [String: UUID] = [:]

    public init() {}

    public func recordInternalWrite(_ marker: ClipboardWriteMarker) async throws {
        markersByTransactionID[marker.transactionID] = marker

        if let changeCount = marker.changeCount {
            transactionIDsByChangeCount[changeCount] = marker.transactionID
        }

        if let contentHash = marker.contentHash {
            transactionIDsByHash[contentHash] = marker.transactionID
        }
    }

    public func shouldIgnore(changeCount: Int, contentHash: String?) async throws -> Bool {
        if let transactionID = transactionIDsByChangeCount[changeCount] {
            removeMarker(transactionID: transactionID)
            return true
        }

        if let contentHash, let transactionID = transactionIDsByHash[contentHash] {
            let marker = markersByTransactionID[transactionID]
            if marker?.changeCount == nil {
                removeMarker(transactionID: transactionID)
                return true
            }
        }

        return false
    }

    public func shouldIgnore(snapshot: ClipboardSnapshot, contentHash: String?) async throws -> Bool {
        if
            let marker = snapshot.internalWriteMarker,
            markersByTransactionID[marker.transactionID] != nil
        {
            removeMarker(transactionID: marker.transactionID)
            return true
        }

        return try await shouldIgnore(
            changeCount: snapshot.changeCount,
            contentHash: contentHash ?? snapshot.internalWriteMarker?.contentHash
        )
    }

    public func pendingMarkerCount() -> Int {
        markersByTransactionID.count
    }

    private func removeMarker(transactionID: UUID) {
        guard let marker = markersByTransactionID.removeValue(forKey: transactionID) else {
            return
        }

        if let changeCount = marker.changeCount {
            transactionIDsByChangeCount.removeValue(forKey: changeCount)
        }

        if let contentHash = marker.contentHash {
            transactionIDsByHash.removeValue(forKey: contentHash)
        }
    }
}
