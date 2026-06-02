// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Clippy",
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
            exclude : [
                "Resources/Info.plist"
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

