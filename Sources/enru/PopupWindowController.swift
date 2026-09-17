import AppKit
import SwiftUI

/// Owns the floating popup panel: positioning, show/hide/toggle,
/// click-outside dismiss, Escape-to-close, and frame persistence.
@MainActor
final class PopupWindowController: NSObject, NSWindowDelegate {
    private static let defaultSize = NSSize(width: 320, height: 172)
    private static let frameDefaultsKey = "PopupPanel.frame"
    private static let topRightInset = NSSize(width: 16, height: 12)

    private let panel: PopupPanel
    private let appState = AppState()
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    override init() {
        let savedFrame = PopupWindowController.loadSavedFrame()
        let initialRect = savedFrame ?? PopupWindowController.defaultTopRightRect(size: PopupWindowController.defaultSize)
        panel = PopupPanel(contentRect: initialRect)
        super.init()

        panel.delegate = self
        let content = ContentView(appState: appState)
        panel.contentView = NSHostingView(rootView: content)

        if savedFrame == nil {
            panel.setFrame(initialRect, display: false)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        appState.resetForShow()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.focusInput()
        installMonitors()
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
    }

    // MARK: - Positioning & persistence

    private static func defaultTopRightRect(size: NSSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        let x = visible.maxX - size.width - topRightInset.width
        let y = visible.maxY - size.height - topRightInset.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func loadSavedFrame() -> NSRect? {
        guard let raw = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return nil }
        var rect = NSRectFromString(raw)
        guard rect.width > 0, rect.height > 0 else { return nil }
        // A frame saved by an older build may be smaller than today's minimum.
        rect.size.width = max(rect.width, PopupPanel.minimumSize.width)
        rect.size.height = max(rect.height, PopupPanel.minimumSize.height)
        return rect
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameDefaultsKey)
    }

    // MARK: - Dismiss handling

    private func installMonitors() {
        removeMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { // Escape
                self.hide()
                return nil
            }
            if event.type == .leftMouseDown, event.window !== self.panel {
                self.hide()
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
