import Foundation

/// Small string metadata bag for detector candidates and source details.
public struct ClipboardMetadata: Codable, Equatable, Sendable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }
}

/// Top-level clipboard history record. Raw payloads live in representations.
public struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var groupID: UUID?
    public var title: String
    public var detectedKind: ClipboardContentKind
    public var sourceAppName: String?
    public var sourceBundleIdentifier: String?
    public var contentHash: String
    public var searchableText: String
    public var previewText: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var copyCount: Int
    public var useCount: Int
    public var isPinned: Bool
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var byteCount: Int64
    public var metadata: ClipboardMetadata

    public init(
        id: UUID = UUID(),
        groupID: UUID? = nil,
        title: String,
        detectedKind: ClipboardContentKind,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        contentHash: String,
        searchableText: String,
        previewText: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        copyCount: Int = 1,
        useCount: Int = 0,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        byteCount: Int64 = 0,
        metadata: ClipboardMetadata = ClipboardMetadata()
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.detectedKind = detectedKind
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.contentHash = contentHash
        self.searchableText = searchableText
        self.previewText = previewText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.copyCount = copyCount
        self.useCount = useCount
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.byteCount = byteCount
        self.metadata = metadata
    }
}
