import AppKit

/// Renders the enru wordmark (see `Wordmark`) for the two places it appears: the app
/// icon in Finder and the Dock-less menu-bar item. Drawn in code from vector data so
/// every size comes from one definition and stays crisp.
enum IconArtwork {

    // MARK: - App icon

    /// Draws the full-color icon to fill `rect` in the current graphics context.
    /// Laid out on Apple's 1024pt icon grid (an 824pt tile centered in the canvas),
    /// with the wordmark's own 36pt artboard mapped onto that tile so the proportions
    /// match the Figma source exactly.
    static func drawAppIcon(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(rect.width, rect.height) / 1024

        let tile = NSRect(
            x: rect.minX + 100 * scale,
            y: rect.minY + 100 * scale,
            width: 824 * scale,
            height: 824 * scale
        )
        let corner = 185 * scale

        NSColor.white.setFill()
        NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner).fill()

        // The tile is white, so on a light background it would otherwise dissolve into
        // whatever is behind it. A hairline edge keeps the icon's shape readable.
        NSColor(white: 0, alpha: 0.12).setStroke()
        let border = NSBezierPath(
            roundedRect: tile.insetBy(dx: scale / 2, dy: scale / 2),
            xRadius: corner,
            yRadius: corner
        )
        border.lineWidth = scale
        border.stroke()

        context.saveGState()
        context.translateBy(x: tile.minX, y: tile.minY)
        let fit = tile.width / Wordmark.viewBox.width
        context.scaleBy(x: fit, y: fit)
        context.addPath(Wordmark.path)
        NSColor.black.setFill()
        context.fillPath()
        context.restoreGState()
    }

    /// Renders the icon into a bitmap of exactly `pixels` × `pixels`, independent of
    /// whatever backing scale the current display happens to use.
    static func appIconPNG(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: pixels, height: pixels) // 1 point == 1 pixel

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.current = previous

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Menu bar

    /// Monochrome menu-bar version. The drawing handler re-runs per display, so the
    /// wordmark stays vector-crisp on Retina, and the template flag lets AppKit tint it
    /// for the current menu-bar appearance (light, dark, and while highlighted).
    ///
    /// Sized from the wordmark's ink bounds rather than its 36pt artboard: most of that
    /// artboard is margin, and honoring it would shrink the lettering to a few points
    /// tall. The image comes out wider than it is tall, so the status item uses
    /// `variableLength` to match.
    static func menuBarIcon(barHeight: CGFloat = 18, capHeight: CGFloat = 8.5) -> NSImage {
        let ink = Wordmark.inkBounds
        let fit = capHeight / ink.height
        let width = ceil(ink.width * fit)

        let image = NSImage(size: NSSize(width: width, height: barHeight), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            // Move the ink's own origin to the middle of the bar, then scale to fit.
            context.translateBy(
                x: rect.midX - ink.width * fit / 2,
                y: rect.midY - ink.height * fit / 2
            )
            context.scaleBy(x: fit, y: fit)
            context.translateBy(x: -ink.minX, y: -ink.minY)
            context.addPath(Wordmark.path)
            NSColor.black.setFill()
            context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
