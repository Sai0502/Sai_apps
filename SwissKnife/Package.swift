// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwissKnife",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SwissKnife", targets: ["SwissKnife"])
    ],
    targets: [
        .executableTarget(
            name: "SwissKnife",
            path: "Sources/SwissKnife"
        )
    ]
)
