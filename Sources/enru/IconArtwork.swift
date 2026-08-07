import AppKit

/// Renders the enru wordmark (see `Wordmark`) as the app icon shown in Finder.
/// Drawn in code from vector data so every iconset size stays crisp.
/// The menu-bar item uses an SF Symbol instead — see `StatusBarController`.
enum IconArtwork {

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
}
