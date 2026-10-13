// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Reprise",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .executableTarget(
            name: "Reprise",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PremiereMonitor"
        )
    ]
)
