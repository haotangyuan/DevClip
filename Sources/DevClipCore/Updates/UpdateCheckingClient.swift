/// Sparkle 2 integration boundary. The real updater is intentionally deferred.
public struct UpdateIntegrationStatus: Equatable, Sendable {
    public var interfaceName: String
    public var isSparkleLinked: Bool
    public var note: String

    public init(interfaceName: String, isSparkleLinked: Bool, note: String) {
        self.interfaceName = interfaceName
        self.isSparkleLinked = isSparkleLinked
        self.note = note
    }
}

public protocol UpdateCheckingClient: Sendable {
    func checkForUpdates() async throws
    func integrationStatus() async -> UpdateIntegrationStatus
}

public struct SparkleUpdateCheckingClient: UpdateCheckingClient {
    public init() {}

    public func checkForUpdates() async throws {
        throw DevClipError.notImplemented(feature: "Sparkle 2 update checking", phase: "Phase 8")
    }

    public func integrationStatus() async -> UpdateIntegrationStatus {
        UpdateIntegrationStatus(
            interfaceName: "Sparkle 2",
            isSparkleLinked: false,
            note: "已预留更新检查边界；当前未引入 Sparkle 2 运行时依赖。"
        )
    }
}
