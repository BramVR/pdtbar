// swift-tools-version: 6.2

import PackageDescription
import Foundation

let developerDirectoryCandidates = [
    ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
    "/Library/Developer/CommandLineTools",
    "/Applications/Xcode.app/Contents/Developer",
].compactMap { $0 }
let testingInteropLibraryDirectory = developerDirectoryCandidates
    .map { "\($0)/Library/Developer/usr/lib" }
    .first { FileManager.default.fileExists(atPath: "\($0)/lib_TestingInterop.dylib") }
let testingInteropLinkerSettings: [LinkerSetting] = {
    guard let testingInteropLibraryDirectory else {
        return []
    }

    // The standalone swift-testing package links _TestingInterop with Swift 6.3.
    // Command Line Tools can install it outside the default linker/runtime path.
    return [
        .unsafeFlags([
            "-L\(testingInteropLibraryDirectory)",
            "-Xlinker",
            "-rpath",
            "-Xlinker",
            testingInteropLibraryDirectory,
        ], .when(platforms: [.macOS])),
    ]
}()

let package = Package(
    name: "pdtbar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDTBarCore", targets: ["PDTBarCore"]),
        .executable(name: "pdtbar", targets: ["PDTBarApp"]),
        .executable(name: "pdtbar-dev", targets: ["PDTBarDev"]),
        .executable(name: "pdtbar-smoke", targets: ["PDTBarSmoke"]),
        .executable(name: "pdtbar-checks", targets: ["PDTBarChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.3.2"),
    ],
    targets: [
        .target(name: "PDTBarCore"),
        .executableTarget(
            name: "PDTBarApp",
            dependencies: ["PDTBarCore"]
        ),
        .executableTarget(
            name: "PDTBarDev",
            dependencies: ["PDTBarCore"]
        ),
        .executableTarget(
            name: "PDTBarSmoke",
            dependencies: ["PDTBarCore"]
        ),
        .executableTarget(
            name: "PDTBarChecks",
            dependencies: ["PDTBarCore"]
        ),
        .testTarget(
            name: "PDTBarTests",
            dependencies: [
                "PDTBarCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            linkerSettings: testingInteropLinkerSettings
        ),
    ]
)
