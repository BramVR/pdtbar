// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PortfolioPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PortfolioPulse", targets: ["PulseBar"]),
        .executable(name: "PulseFixtureChecks", targets: ["PulseFixtureChecks"]),
        .library(name: "PulseCore", targets: ["PulseCore"])
    ],
    targets: [
        .target(name: "PulseCore"),
        .executableTarget(
            name: "PulseBar",
            dependencies: ["PulseCore"]
        ),
        .executableTarget(
            name: "PulseFixtureChecks",
            dependencies: ["PulseCore"]
        ),
        .testTarget(
            name: "PulseCoreTests",
            dependencies: ["PulseCore"]
        )
    ]
)
