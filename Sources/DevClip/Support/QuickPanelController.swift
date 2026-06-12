@preconcurrency import AppKit
import DevClipCore
import SwiftUI

@MainActor
protocol QuickPanelControlling: AnyObject {
    func show()
    func close()
}

/// AppKit panel boundary for keyboard-first floating history search.
@MainActor
final class AppKitQuickPanelController: NSObject, QuickPanelControlling {
    private let viewModel: QuickPanelViewModel
    private var panel: QuickPanelWindow?
    private nonisolated(unsafe) var eventMonitor: Any?
    private var previousApplication: NSRunningApplication?

    init(dependencies: DependencyContainer) {
        self.viewModel = QuickPanelViewModel(
            searchService: dependencies.searchService,
            repository: dependencies.repository,
            pasteEngine: dependencies.pasteEngine,
            transformEngine: dependencies.transformEngine,
            diffService: dependencies.diffService
        )
        super.init()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        let currentAppBundleIdentifier = previousApplication?.bundleIdentifier
        let panel = ensurePanel()
        positionPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        Task { @MainActor in
            await viewModel.prepareForPresentation(
                currentAppBundleIdentifier: currentAppBundleIdentifier
            )
        }
    }

    func close() {
        panel?.orderOut(nil)
        previousApplication?.activate()
        previousApplication = nil
    }

    private func ensurePanel() -> QuickPanelWindow {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: QuickPanelView(viewModel: viewModel))
        let panel = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        self.panel = panel
        installEventMonitorIfNeeded()
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 96
        )
        panel.setFrameOrigin(origin)
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let didHandle = MainActor.assumeIsolated {
                self?.handleKeyDown(event) == true
            }
            return didHandle ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let usesCommand = modifiers.contains(.command)
        let usesShift = modifiers.contains(.shift)

        switch Int(event.keyCode) {
        case 53:
            close()
            return true

        case 125:
            viewModel.selectNext()
            return true

        case 126:
            viewModel.selectPrevious()
            return true

        case 36, 76:
            if viewModel.mode == .actions {
                Task { @MainActor in
                    _ = await viewModel.executeSelectedAction(copyResult: usesCommand)
                }
            } else if usesCommand {
                copySelected(closesPanel: false)
            } else {
                pasteSelected(plainText: usesShift)
            }
            return true

        case 40 where usesCommand:
            Task { @MainActor in
                await viewModel.showActionMode()
            }
            return true

        case 35 where usesCommand:
            Task { @MainActor in
                await viewModel.togglePinned()
            }
            return true

        case 2 where usesCommand:
            Task { @MainActor in
                await viewModel.showDiffMode()
            }
            return true

        case 49:
            viewModel.togglePreview()
            return true

        case 51:
            Task { @MainActor in
                await viewModel.deleteSelected()
            }
            return true

        case 48:
            Task { @MainActor in
                await viewModel.toggleMode()
            }
            return true

        default:
            return false
        }
    }

    private func copySelected(closesPanel: Bool) {
        Task { @MainActor in
            let didCopy = await viewModel.copySelectedOriginal()

            if didCopy && closesPanel {
                close()
            }
        }
    }

    private func pasteSelected(plainText: Bool) {
        guard viewModel.hasSelection else {
            return
        }

        let targetApplication = previousApplication?.pasteTargetApplication
        close()

        Task { @MainActor in
            if plainText {
                _ = await viewModel.pasteSelectedPlainText(targetApplication: targetApplication)
            } else {
                _ = await viewModel.pasteSelectedOriginal(targetApplication: targetApplication)
            }
        }
    }
}

private final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
