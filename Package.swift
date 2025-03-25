// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "libopus",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "libopus",
            targets: ["libopus"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "libopus-lib",
            path: "Sources/libopus/libopus.xcframework"
        ),
        .target(
            name: "libopus",
            dependencies: ["libopus-lib"],
            path: "Sources/libopus",
            publicHeadersPath: "include"
        )
    ],
    swiftLanguageVersions: [.v5]
)
