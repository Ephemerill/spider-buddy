// swift-tools-version:6.0
import PackageDescription

// Convenience manifest for editing in Xcode. The shipping build is ./build.sh,
// which compiles with swiftc and assembles Spider.app.
let package = Package(
    name: "DesktopSpider",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DesktopSpider", path: "Sources/DesktopSpider",
                          swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
