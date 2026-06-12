// swift-tools-version: 6.0

import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .unsafeFlags([
        "-strict-concurrency=complete",
        "-warn-concurrency"
    ])
]

let package = Package(
    name: "DevClip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DevClip", targets: ["DevClip"]),
        .library(name: "DevClipCore", targets: ["DevClipCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.9.4")
    ],
    targets: [
        .executableTarget(
            name: "DevClip",
            dependencies: [
                "DevClipCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/DevClip",
            resources: [
                .process("Resources")
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "DevClipCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/DevClipCore",
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "DevClipCoreTests",
            dependencies: [
                "DevClipCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/DevClipCoreTests",
            swiftSettings: strictSwiftSettings
        )
    ],
    swiftLanguageModes: [.v6]
)
