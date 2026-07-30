// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FinderV2",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FinderV2", targets: ["FinderV2"])
    ],
    targets: [
        .executableTarget(
            name: "FinderV2",
            path: "Sources/FinderV2"
        ),
        .testTarget(
            name: "FinderV2Tests",
            dependencies: ["FinderV2"],
            path: "Tests/FinderV2Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
