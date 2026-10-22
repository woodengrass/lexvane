// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuestionQualityAudit",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "ContentKit", path: "../ContentKit")],
    targets: [.executableTarget(name: "QuestionQualityAudit",
        dependencies: [.product(name: "ContentCLI", package: "ContentKit")])]
)
