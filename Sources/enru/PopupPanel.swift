import AppKit

/// A borderless, floating, non-activating panel that can still become key
/// (so the text field inside it can receive keystrokes immediately).
final class PopupPanel: NSPanel {
    /// Small enough to stay unobtrusive, large enough for the language bar, the input
    /// field and a line or two of translation.
    static let minimumSize = NSSize(width: 280, height: 150)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        minSize = PopupPanel.minimumSize
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    /// The app has no main menu (it's a menu-bar accessory), so the standard editing
    /// shortcuts have nothing to match against and never reach the field editor.
    /// Dispatch them down the responder chain by hand.
    private static let editingActions: [String: Selector] = [
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "x": #selector(NSText.cut(_:)),
        "a": #selector(NSText.selectAll(_:))
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        if flags == .command,
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let action = PopupPanel.editingActions[key],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
