// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dashboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dashboard",
            path: "Sources/Dashboard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
