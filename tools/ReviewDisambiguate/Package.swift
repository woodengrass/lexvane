// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReviewDisambiguate",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "review-disambiguate", targets: ["ReviewDisambiguate"]),
    ],
    dependencies: [
        .package(path: "../ContentKit"),
    ],
    targets: [
        .executableTarget(
            name: "ReviewDisambiguate",
            dependencies: [.product(name: "ContentModel", package: "ContentKit")]
        ),
    ]
)
