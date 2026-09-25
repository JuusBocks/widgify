// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Widgify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Widgify", targets: ["SpotifyWidgetMac"]),
        .executable(name: "SpotifyWidgetExtension", targets: ["SpotifyWidgetExtension"])
    ],
    targets: [
        .executableTarget(
            name: "SpotifyWidgetMac",
            path: "Sources/SpotifyWidgetMac"
        ),
        .executableTarget(
            name: "SpotifyWidgetExtension",
            path: "Sources/SpotifyWidgetExtension",
            swiftSettings: [
                .unsafeFlags(["-application-extension"])
            ]
        )
    ]
)
