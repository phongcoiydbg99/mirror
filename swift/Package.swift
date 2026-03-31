// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MirrorCapture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MirrorCapture",
            path: "Sources/MirrorCapture",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
