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
        .executable(name: "PDTContractChecks", targets: ["PDTContractChecks"]),
        .executable(name: "AllocationFacetChecks", targets: ["AllocationFacetChecks"]),
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
        .executableTarget(
            name: "PDTContractChecks",
            dependencies: ["PulseCore"]
        ),
        .executableTarget(
            name: "AllocationFacetChecks",
            dependencies: ["PulseCore"]
        ),
        .testTarget(
            name: "PulseCoreTests",
            dependencies: ["PulseCore"]
        )
    ]
)
