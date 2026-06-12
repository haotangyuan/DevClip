import AppKit
import SwiftUI

@main
@MainActor
struct DevClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var runtime: AppRuntime

    init() {
        let runtime = AppRuntime()
        runtime.start()
        _runtime = StateObject(wrappedValue: runtime)
    }

    var body: some Scene {
        MenuBarExtra("DevClip", systemImage: "doc.on.clipboard") {
            Button("快速面板") {
                runtime.showQuickPanel()
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("打开历史") {
                openWindow(id: WindowID.history.rawValue)
            }

            Button("转换预览") {
                openWindow(id: WindowID.transformPreview.rawValue)
            }

            Button("差异对比") {
                openWindow(id: WindowID.diff.rawValue)
            }

            Button("剪贴板栈") {
                openWindow(id: WindowID.clipboardStack.rawValue)
            }

            Divider()

            if let statusMessage = runtime.statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                Divider()
            }

            SettingsLink()
            Divider()

            Button("退出 DevClip") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        WindowGroup("DevClip", id: WindowID.history.rawValue) {
            HistoryRootView(dependencies: runtime.dependencies)
        }

        Window("转换预览", id: WindowID.transformPreview.rawValue) {
            TransformPreviewRootView(dependencies: runtime.dependencies)
        }

        Window("差异对比", id: WindowID.diff.rawValue) {
            DiffRootView(dependencies: runtime.dependencies)
        }

        Window("剪贴板栈", id: WindowID.clipboardStack.rawValue) {
            ClipboardStackRootView(dependencies: runtime.dependencies)
        }

        Settings {
            SettingsRootView(dependencies: runtime.dependencies)
        }
    }
}
