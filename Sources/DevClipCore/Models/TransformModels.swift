import Foundation

public enum TransformCategory: String, Codable, CaseIterable, Sendable {
    case base64
    case json
    case url
    case jwt
    case hash
    case date
    case text
}

public enum TransformExecutionStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
}

public struct TransformDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var category: TransformCategory
    public var acceptedInputKinds: [ClipboardContentKind]
    public var outputKind: ClipboardContentKind
    public var isDestructive: Bool

    public init(
        id: String,
        displayName: String,
        category: TransformCategory,
        acceptedInputKinds: [ClipboardContentKind],
        outputKind: ClipboardContentKind,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.acceptedInputKinds = acceptedInputKinds
        self.outputKind = outputKind
        self.isDestructive = isDestructive
    }
}

public struct TransformStep: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var actionID: String
    public var order: Int
    public var options: ClipboardMetadata

    public init(
        id: UUID = UUID(),
        actionID: String,
        order: Int,
        options: ClipboardMetadata = ClipboardMetadata()
    ) {
        self.id = id
        self.actionID = actionID
        self.order = order
        self.options = options
    }
}

public struct TransformPipeline: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [TransformStep]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [TransformStep] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TransformExecution: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var pipelineID: UUID?
    public var entryID: UUID?
    public var status: TransformExecutionStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        pipelineID: UUID? = nil,
        entryID: UUID? = nil,
        status: TransformExecutionStatus = .pending,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.pipelineID = pipelineID
        self.entryID = entryID
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
    }
}
