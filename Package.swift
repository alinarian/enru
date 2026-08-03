// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "enru",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "enru",
            path: "Sources/enru",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
