import Foundation

/// Storage location for a pasteboard representation.
public enum RepresentationStorageKind: String, Codable, CaseIterable, Sendable {
    case inlineData
    case blobFile
    case fileReference
}

/// One raw representation for one clipboard entry.
public struct ClipboardRepresentation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var entryID: UUID
    public var pasteboardType: String
    public var uniformTypeIdentifier: String?
    public var storageKind: RepresentationStorageKind
    public var inlineData: Data?
    public var externalFilePath: String?
    public var byteCount: Int64
    public var textEncoding: String?
    public var priority: Int

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        pasteboardType: String,
        uniformTypeIdentifier: String? = nil,
        storageKind: RepresentationStorageKind,
        inlineData: Data? = nil,
        externalFilePath: String? = nil,
        byteCount: Int64 = 0,
        textEncoding: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.entryID = entryID
        self.pasteboardType = pasteboardType
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.storageKind = storageKind
        self.inlineData = inlineData
        self.externalFilePath = externalFilePath
        self.byteCount = byteCount
        self.textEncoding = textEncoding
        self.priority = priority
    }
}
