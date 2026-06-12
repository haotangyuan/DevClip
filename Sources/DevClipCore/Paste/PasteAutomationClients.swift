@preconcurrency import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct PasteTargetApplication: Equatable, Sendable {
    public var processIdentifier: Int32
    public var bundleIdentifier: String?
    public var localizedName: String?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String? = nil,
        localizedName: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

public protocol PasteAutomationPreferenceProviding: Sendable {
    func isAutomaticPasteEnabled() async -> Bool
}

public struct StaticPasteAutomationPreferences: PasteAutomationPreferenceProviding {
    private let isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func isAutomaticPasteEnabled() async -> Bool {
        isEnabled
    }
}

public struct UserDefaultsPasteAutomationPreferences: PasteAutomationPreferenceProviding {
    public static let automaticPasteEnabledKey = "paste.autoPasteEnabled"

    private let key: String

    public init(key: String = Self.automaticPasteEnabledKey) {
        self.key = key
    }

    public func isAutomaticPasteEnabled() async -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

public protocol AccessibilityPermissionClient: Sendable {
    func isTrusted() async -> Bool
    func requestTrustIfNeeded() async -> Bool
}

public struct SystemAccessibilityPermissionClient: AccessibilityPermissionClient {
    public init() {}

    public func isTrusted() async -> Bool {
        AXIsProcessTrusted()
    }

    public func requestTrustIfNeeded() async -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

public protocol ApplicationFocusClient: Sendable {
    func frontmostApplication() async -> PasteTargetApplication?
    func activate(_ application: PasteTargetApplication) async -> Bool
}

public struct SystemApplicationFocusClient: ApplicationFocusClient {
    public init() {}

    public func frontmostApplication() async -> PasteTargetApplication? {
        await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.pasteTargetApplication
        }
    }

    public func activate(_ application: PasteTargetApplication) async -> Bool {
        await MainActor.run {
            guard let runningApplication = NSRunningApplication(
                processIdentifier: pid_t(application.processIdentifier)
            ) else {
                return false
            }

            return runningApplication.activate()
        }
    }
}

public protocol KeyboardEventClient: Sendable {
    func postCommandV() async throws
}

public struct SystemKeyboardEventClient: KeyboardEventClient {
    public init() {}

    public func postCommandV() async throws {
        let keyCodeV: CGKeyCode = 0x09
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeV, keyDown: false)
        else {
            throw DevClipError.invalidInput(reason: "无法创建 Command+V 键盘事件。")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

public extension NSRunningApplication {
    var pasteTargetApplication: PasteTargetApplication {
        PasteTargetApplication(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: localizedName
        )
    }
}
