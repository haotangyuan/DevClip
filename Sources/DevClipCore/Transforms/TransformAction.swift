import Foundation

public struct TransformInput: Equatable, Sendable {
    public var kind: ClipboardContentKind
    public var data: Data
    public var text: String?
    public var metadata: ClipboardMetadata

    public init(
        kind: ClipboardContentKind,
        data: Data,
        text: String? = nil,
        metadata: ClipboardMetadata = ClipboardMetadata()
    ) {
        self.kind = kind
        self.data = data
        self.text = text
        self.metadata = metadata
    }
}

public struct TransformOptions: Equatable, Sendable {
    public var values: [String: String]
    public var timeoutSeconds: TimeInterval

    public init(values: [String: String] = [:], timeoutSeconds: TimeInterval = 5) {
        self.values = values
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct TransformResult: Equatable, Sendable {
    public var outputKind: ClipboardContentKind
    public var data: Data
    public var previewText: String
    public var metadata: ClipboardMetadata

    public init(
        outputKind: ClipboardContentKind,
        data: Data,
        previewText: String,
        metadata: ClipboardMetadata = ClipboardMetadata()
    ) {
        self.outputKind = outputKind
        self.data = data
        self.previewText = previewText
        self.metadata = metadata
    }
}

public protocol TransformAction: Sendable {
    var id: String { get }
    var displayName: String { get }
    var category: TransformCategory { get }
    var acceptedInputKinds: [ClipboardContentKind] { get }
    var outputKind: ClipboardContentKind { get }
    var isDestructive: Bool { get }

    func canHandle(_ input: TransformInput) -> Bool
    func execute(_ input: TransformInput, options: TransformOptions) async throws -> TransformResult
}
