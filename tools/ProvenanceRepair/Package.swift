// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProvenanceRepair",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "ContentKit", path: "../ContentKit")],
    targets: [
        .target(name: "ProvenanceRepairCore", dependencies: [.product(name: "ContentModel", package: "ContentKit")]),
        .executableTarget(name: "ProvenanceRepair", dependencies: ["ProvenanceRepairCore"]),
        .testTarget(name: "ProvenanceRepairTests", dependencies: ["ProvenanceRepairCore", .product(name: "ContentModel", package: "ContentKit")]),
    ]
)
