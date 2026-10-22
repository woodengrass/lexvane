// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContentKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ContentModel", targets: ["ContentModel"]),
        .library(name: "ContentCLI", targets: ["ContentCLI"]),
        .executable(name: "contentkit", targets: ["contentkit"]),
    ],
    targets: [
        .target(name: "ContentModel"),
        .target(name: "ContentCLI", dependencies: ["ContentModel"]),
        .executableTarget(name: "contentkit", dependencies: ["ContentCLI", "ContentModel"]),
        .testTarget(name: "ContentKitTests", dependencies: ["ContentModel", "ContentCLI"]),
    ]
)
