// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SaiShot",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SaiShot", targets: ["SaiShot"]),
    ],
    targets: [
        .target(
            name: "SystemSettingsKit",
            path: "ThirdParty/PermissionFlow/Sources/SystemSettingsKit"
        ),
        .target(
            name: "PermissionFlow",
            dependencies: ["SystemSettingsKit"],
            path: "ThirdParty/PermissionFlow/Sources/PermissionFlow",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SaiShot",
            dependencies: [
                "PermissionFlow"
            ],
            path: "SaiShot",
            exclude: ["App/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("VisionKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "SaiShotTests",
            dependencies: ["SaiShot"],
            path: "Tests/SaiShotTests"
        )
    ]
)
