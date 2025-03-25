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
        .target(
            name: "libopus",
            path: "Sources/libopus",
            publicHeadersPath: "include"
        )
    ],
    swiftLanguageVersions: [.v5]
)
