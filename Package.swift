// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Avail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Avail", targets: ["AvailApp"]),
        .library(name: "AvailCore", targets: ["AvailCore"]),
        .library(name: "AvailEPUB", targets: ["AvailEPUB"]),
        .library(name: "AvailPDF", targets: ["AvailPDF"]),
        .library(name: "AvailPlayback", targets: ["AvailPlayback"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20"),
        // Includes SwiftSoup's merged Swift 6.4 Release-build optimizer workaround.
        // Return to a versioned requirement when the next SwiftSoup release contains it.
        .package(
            url: "https://github.com/scinfu/SwiftSoup.git",
            revision: "83336847e47b2f499330c15426ad2fb180e72d9b"
        ),
    ],
    targets: [
        .executableTarget(
            name: "AvailApp",
            dependencies: ["AvailCore", "AvailEPUB", "AvailPDF", "AvailPlayback"],
            resources: [.process("Resources")]
        ),
        .target(name: "AvailCore"),
        .target(
            name: "AvailPlayback",
            dependencies: ["AvailCore"]
        ),
        .target(
            name: "AvailEPUB",
            dependencies: [
                "AvailCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .target(
            name: "AvailPDF",
            dependencies: ["AvailCore"]
        ),
        .testTarget(
            name: "AvailAppTests",
            dependencies: [
                "AvailApp",
                "AvailEPUB",
                "AvailPDF",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "AvailCoreTests",
            dependencies: ["AvailCore"]
        ),
        .testTarget(
            name: "AvailEPUBTests",
            dependencies: [
                "AvailCore",
                "AvailEPUB",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "AvailPDFTests",
            dependencies: ["AvailCore", "AvailPDF"]
        ),
        .testTarget(
            name: "AvailPlaybackTests",
            dependencies: ["AvailCore", "AvailPlayback"]
        ),
    ]
)
