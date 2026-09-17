import AppKit

/// A borderless, floating, non-activating panel that can still become key
/// (so the text field inside it can receive keystrokes immediately).
final class PopupPanel: NSPanel {
    /// Small enough to stay unobtrusive, large enough for the language bar, the input
    /// field and a line or two of translation.
    static let minimumSize = NSSize(width: 280, height: 150)

    /// How far inside the panel's edge a drag still counts as a resize. AppKit's own
    /// resize zone on a borderless window is a few points wide and invisible, so the
    /// panel handles edge drags itself with a more forgiving margin.
    private static let resizeMargin: CGFloat = 8

    private var resizeTrackingArea: NSTrackingArea?
    private var hoveredEdges: Edges = []

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

    // MARK: - Edge resizing

    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let bottom = Edges(rawValue: 1 << 2)
        static let top = Edges(rawValue: 1 << 3)
    }

    override var contentView: NSView? {
        didSet {
            if let resizeTrackingArea, let oldValue {
                oldValue.removeTrackingArea(resizeTrackingArea)
            }
            guard let contentView else { return }
            // Mouse-moved events over the whole panel, owned by the panel, so it can
            // show a resize cursor at the edges without the SwiftUI content knowing.
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            contentView.addTrackingArea(area)
            resizeTrackingArea = area
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let hit = edges(at: event.locationInWindow)
            if !hit.isEmpty {
                resize(from: event, along: hit)
                return
            }
        }
        super.sendEvent(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: edges(at: event.locationInWindow))
    }

    override func mouseExited(with event: NSEvent) {
        updateCursor(for: [])
    }

    private func edges(at point: NSPoint) -> Edges {
        let margin = PopupPanel.resizeMargin
        let size = frame.size
        var edges: Edges = []
        if point.x <= margin { edges.insert(.left) }
        if point.x >= size.width - margin { edges.insert(.right) }
        if point.y <= margin { edges.insert(.bottom) }
        if point.y >= size.height - margin { edges.insert(.top) }
        return edges
    }

    private func updateCursor(for edges: Edges) {
        guard edges != hoveredEdges else { return }
        hoveredEdges = edges
        if let cursor = cursor(for: edges) {
            cursor.set()
        } else {
            // Back to the default; views with their own cursor rects (the text field's
            // I-beam) take over again as the pointer enters them.
            NSCursor.arrow.set()
        }
    }

    private func cursor(for edges: Edges) -> NSCursor? {
        let position: NSCursor.FrameResizePosition
        switch edges {
        case [.left]: position = .left
        case [.right]: position = .right
        case [.top]: position = .top
        case [.bottom]: position = .bottom
        case [.left, .top]: position = .topLeft
        case [.right, .top]: position = .topRight
        case [.left, .bottom]: position = .bottomLeft
        case [.right, .bottom]: position = .bottomRight
        default: return nil
        }
        return .frameResize(position: position, directions: .all)
    }

    /// Runs a tracking loop for one resize drag. Positions are compared in screen
    /// space because dragging the left or bottom edge moves the window's own origin.
    private func resize(from mouseDown: NSEvent, along edges: Edges) {
        let startFrame = frame
        let startPoint = convertPoint(toScreen: mouseDown.locationInWindow)
        let minimum = minSize

        trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self, let event else { return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                return
            }

            let point = self.convertPoint(toScreen: event.locationInWindow)
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            var newFrame = startFrame

            if edges.contains(.right) {
                newFrame.size.width = max(minimum.width, startFrame.width + dx)
            } else if edges.contains(.left) {
                newFrame.size.width = max(minimum.width, startFrame.width - dx)
                newFrame.origin.x = startFrame.maxX - newFrame.width
            }
            if edges.contains(.top) {
                newFrame.size.height = max(minimum.height, startFrame.height + dy)
            } else if edges.contains(.bottom) {
                newFrame.size.height = max(minimum.height, startFrame.height - dy)
                newFrame.origin.y = startFrame.maxY - newFrame.height
            }

            self.setFrame(newFrame, display: true)
        }
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
