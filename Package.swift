// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplitPages",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplitPages", targets: ["SplitPages"]),
        .executable(name: "SplitPagesDemo", targets: ["SplitPagesDemo"]),
    ],
    targets: [
        .target(name: "SplitPages"),
        .executableTarget(name: "SplitPagesDemo", dependencies: ["SplitPages"]),
        .testTarget(name: "SplitPagesTests", dependencies: ["SplitPages"]),
    ]
)
