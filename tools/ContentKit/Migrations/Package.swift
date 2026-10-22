// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExistingIdentityRegistration20261022",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(
            name: "register-existing-20261022",
            dependencies: [
                .product(name: "ContentModel", package: "ContentKit"),
                .product(name: "ContentCLI", package: "ContentKit"),
            ],
            path: ".",
            sources: ["register-existing-20261022.swift"]
        ),
    ]
)
