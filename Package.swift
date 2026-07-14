// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Avail", targets: ["AvailApp"]),
        .library(name: "AvailCore", targets: ["AvailCore"]),
    ],
    targets: [
        .executableTarget(
            name: "AvailApp",
            dependencies: ["AvailCore"],
            resources: [.process("Resources")]
        ),
        .target(name: "AvailCore"),
        .testTarget(
            name: "AvailAppTests",
            dependencies: ["AvailApp"]
        ),
        .testTarget(
            name: "AvailCoreTests",
            dependencies: ["AvailCore"]
        ),
    ]
)
