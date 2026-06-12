@preconcurrency import ServiceManagement
import Foundation

public protocol LaunchAtLoginClient: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ isEnabled: Bool) async throws
}

public struct SystemLaunchAtLoginClient: LaunchAtLoginClient {
    public init() {}

    public func isEnabled() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ isEnabled: Bool) async throws {
        let service = SMAppService.mainApp
        if isEnabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try await service.unregister()
        }
    }
}

public actor InMemoryLaunchAtLoginClient: LaunchAtLoginClient {
    private var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func isEnabled() async -> Bool {
        enabled
    }

    public func setEnabled(_ isEnabled: Bool) async throws {
        enabled = isEnabled
    }
}
