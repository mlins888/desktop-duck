// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopDuck",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DesktopDuck", path: "Sources/DesktopDuck")
    ]
)
