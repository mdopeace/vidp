// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VidP",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "VidP"),
        .testTarget(name: "VidPTests", dependencies: ["VidP"]),
    ]
)
