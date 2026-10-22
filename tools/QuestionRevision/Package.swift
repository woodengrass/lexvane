// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuestionRevision",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../ContentKit")],
    targets: [.executableTarget(name: "qr-seal",
        dependencies: [.product(name: "ContentModel", package: "ContentKit")],
        path: ".", sources: ["seal.swift"])]
)
