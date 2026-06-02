// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ClipboardHistory",
            targets: ["ClipboardHistory"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardHistory",
            dependencies: [],
            path: "Sources/ClipboardHistory",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipboardHistoryTests",
            dependencies: [
                "ClipboardHistory",
                "SwiftCheck"
            ],
            path: "Tests/ClipboardHistoryTests"
        )
    ]
)
