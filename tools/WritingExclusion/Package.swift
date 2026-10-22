// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WritingExclusion",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "ContentKit", path: "../ContentKit"),
    ],
    targets: [
        .executableTarget(
            name: "WritingExclusion",
            dependencies: [.product(name: "ContentModel", package: "ContentKit")]
        ),
    ]
)
