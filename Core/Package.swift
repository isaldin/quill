// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenWhisperCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "OpenWhisperCore", targets: ["OpenWhisperCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "OpenWhisperCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(name: "OpenWhisperCoreTests", dependencies: ["OpenWhisperCore"]),
    ]
)
