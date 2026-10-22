// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CurrentRecheck",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "ContentKit", path: "../ContentKit")],
    targets: [.executableTarget(name: "CurrentRecheck",
        dependencies: [.product(name: "ContentCLI", package: "ContentKit")])]
)
