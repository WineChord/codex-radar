// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "codex-radar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "CodexRadarSentinel",
            targets: ["CodexRadarSentinel"]
        ),
    ],
    targets: [
        .target(
            name: "CodexRadarCore"
        ),
        .executableTarget(
            name: "CodexRadarSentinel",
            dependencies: ["CodexRadarCore"]
        ),
        .testTarget(
            name: "CodexRadarCoreTests",
            dependencies: ["CodexRadarCore"]
        ),
    ]
)
