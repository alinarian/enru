import AppKit

/// Regenerates Resources/enru.icns from IconArtwork. Run via Scripts/make-icon.sh.
@main
struct MakeIcon {
    /// The iconset slots macOS expects: file name and the pixel size to render at.
    private static let slots: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Resources")
        let iconset = resources.appendingPathComponent("enru.iconset")

        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for slot in slots {
            guard let png = IconArtwork.appIconPNG(pixels: slot.pixels) else {
                fatalError("Could not render \(slot.name)")
            }
            try png.write(to: iconset.appendingPathComponent("\(slot.name).png"))
        }

        let iconutil = Process()
        iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        iconutil.arguments = [
            "-c", "icns", iconset.path,
            "-o", resources.appendingPathComponent("enru.icns").path
        ]
        try iconutil.run()
        iconutil.waitUntilExit()
        guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

        try FileManager.default.removeItem(at: iconset)
        print("Wrote Resources/enru.icns")
    }
}
