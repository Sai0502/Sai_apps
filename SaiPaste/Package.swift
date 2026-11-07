// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SaiPaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SaiPaste", targets: ["SaiPaste"])
    ],
    targets: [
        .executableTarget(
            name: "SaiPaste",
            path: "Sources/SaiPaste",
            resources: [.process("Resources")],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "SaiPasteTests",
            dependencies: ["SaiPaste"],
            path: "Tests/SaiPasteTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
