@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    @MainActor
    static let showQuickPanel = Self(
        "showQuickPanel",
        default: .init(.space, modifiers: [.command, .shift])
    )
}

@MainActor
enum KeyboardShortcutBootstrap {
    private static var didConfigure = false

    static func configure(showQuickPanel: @escaping @MainActor () -> Void) {
        guard !didConfigure else {
            return
        }

        didConfigure = true
        KeyboardShortcuts.onKeyUp(for: .showQuickPanel) {
            Task { @MainActor in
                showQuickPanel()
            }
        }
    }
}
