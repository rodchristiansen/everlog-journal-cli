// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "everlog",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "everlog", targets: ["everlog"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "everlog",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [
                .copy("Resources/Shortcuts"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "everlogTests",
            dependencies: ["everlog"]
        ),
    ]
)
