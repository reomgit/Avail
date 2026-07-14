// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Avail", targets: ["AvailApp"]),
    ],
    targets: [
        .executableTarget(
            name: "AvailApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AvailAppTests",
            dependencies: ["AvailApp"]
        ),
    ]
)
