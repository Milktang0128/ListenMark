// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenMark",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ListenMark",
            path: "Sources/ListenMark",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
