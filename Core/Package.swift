// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuillCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "QuillCore", targets: ["QuillCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "QuillCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(name: "QuillCoreTests", dependencies: ["QuillCore"]),
    ]
)
