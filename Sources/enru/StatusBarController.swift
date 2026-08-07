import AppKit

/// Owns the menu-bar status item: click toggles the popup, right side offers Quit.
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        // Variable length: the "AЯ" mark is wider than it is tall, so a square item clips it.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = IconArtwork.menuBarIcon()
            button.image?.accessibilityDescription = "enru"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Popup (\u{2318}E)", action: #selector(toggleFromMenu), keyEquivalent: "e"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit enru", action: #selector(quitFromMenu), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach so left-click goes back to normal toggle behavior
    }

    @objc private func toggleFromMenu() {
        onToggle()
    }

    @objc private func quitFromMenu() {
        onQuit()
    }
}
