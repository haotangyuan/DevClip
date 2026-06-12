import Foundation

public struct ClipboardGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var sourceAppName: String?
    public var sourceBundleIdentifier: String?
    public var itemCount: Int
    public var metadata: ClipboardMetadata

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        itemCount: Int = 0,
        metadata: ClipboardMetadata = ClipboardMetadata()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.itemCount = itemCount
        self.metadata = metadata
    }
}

public struct ClipboardTag: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct ClipboardCollection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ClipboardStack: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var entryIDs: [UUID]
    public var currentIndex: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        entryIDs: [UUID] = [],
        currentIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entryIDs = entryIDs
        self.currentIndex = currentIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
