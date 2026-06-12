import Combine
import DevClipCore
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    @Published private(set) var statusMessage: String?

    let dependencies: DependencyContainer
    private let quickPanelController: AppKitQuickPanelController
    private var didStart = false

    init() {
        do {
            let dependencies = try AppDependencyFactory.make()
            self.dependencies = dependencies
            self.quickPanelController = AppKitQuickPanelController(dependencies: dependencies)
        } catch {
            let dependencies = AppDependencyFactory.makeFallbackInMemory()
            self.dependencies = dependencies
            self.quickPanelController = AppKitQuickPanelController(dependencies: dependencies)
            self.statusMessage = "已使用内存仓储：\(error.localizedDescription)"
        }
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        KeyboardShortcutBootstrap.configure { [weak self] in
            self?.showQuickPanel()
        }

        Task { @MainActor in
            do {
                try await dependencies.clipboardMonitor.start()
            } catch {
                statusMessage = "剪贴板监听启动失败：\(error.localizedDescription)"
            }
        }
    }

    func showQuickPanel() {
        quickPanelController.show()
    }
}
