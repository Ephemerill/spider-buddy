// swift-tools-version:6.0
import PackageDescription

// Convenience manifest for editing in Xcode. The shipping build is ./build.sh,
// which compiles with swiftc and assembles Spider.app (fetching Sparkle into
// build/Sparkle itself, pinned to the same version as here).
let package = Package(
    name: "DesktopSpider",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(name: "DesktopSpider",
                          dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/DesktopSpider",
                          swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
