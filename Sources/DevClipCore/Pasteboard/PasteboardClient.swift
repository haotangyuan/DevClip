import Foundation

/// A single pasteboard representation captured from one pasteboard item.
public struct PasteboardRepresentationSnapshot: Equatable, Sendable {
    public var pasteboardType: String
    public var uniformTypeIdentifier: String?
    public var data: Data

    public init(
        pasteboardType: String,
        uniformTypeIdentifier: String? = nil,
        data: Data
    ) {
        self.pasteboardType = pasteboardType
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.data = data
    }
}

/// A pasteboard item with all supported representations preserved.
public struct PasteboardItemSnapshot: Equatable, Sendable {
    public var representations: [PasteboardRepresentationSnapshot]

    public init(representations: [PasteboardRepresentationSnapshot]) {
        self.representations = representations
    }
}

/// One logical pasteboard read, including the source app observed at capture time.
public struct ClipboardSnapshot: Equatable, Sendable {
    public var changeCount: Int
    public var items: [PasteboardItemSnapshot]
    public var sourceAppName: String?
    public var sourceBundleIdentifier: String?
    public var capturedAt: Date
    public var internalWriteMarker: ClipboardWriteMarker?

    public init(
        changeCount: Int,
        items: [PasteboardItemSnapshot],
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        capturedAt: Date = Date(),
        internalWriteMarker: ClipboardWriteMarker? = nil
    ) {
        self.changeCount = changeCount
        self.items = items
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.capturedAt = capturedAt
        self.internalWriteMarker = internalWriteMarker
    }
}

public struct PasteboardWriteRequest: Equatable, Sendable {
    public var items: [PasteboardItemSnapshot]
    public var transactionID: UUID
    public var contentHash: String?

    public init(
        items: [PasteboardItemSnapshot],
        transactionID: UUID = UUID(),
        contentHash: String? = nil
    ) {
        self.items = items
        self.transactionID = transactionID
        self.contentHash = contentHash
    }
}

public struct PasteboardWriteReceipt: Equatable, Sendable {
    public var transactionID: UUID
    public var changeCount: Int

    public init(transactionID: UUID, changeCount: Int) {
        self.transactionID = transactionID
        self.changeCount = changeCount
    }
}

/// Boundary for NSPasteboard access. Business code must depend on this protocol only.
public protocol PasteboardClient: Sendable {
    func changeCount() async throws -> Int
    func readSnapshot() async throws -> ClipboardSnapshot
    func write(_ request: PasteboardWriteRequest) async throws -> PasteboardWriteReceipt
}
