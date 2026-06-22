// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pdtbar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDTBarCore", targets: ["PDTBarCore"]),
        .executable(name: "pdtbar-dev", targets: ["PDTBarDev"]),
        .executable(name: "pdtbar-checks", targets: ["PDTBarChecks"]),
    ],
    targets: [
        .target(name: "PDTBarCore"),
        .executableTarget(
            name: "PDTBarDev",
            dependencies: ["PDTBarCore"]
        ),
        .executableTarget(
            name: "PDTBarChecks",
            dependencies: ["PDTBarCore"]
        ),
    ]
)
